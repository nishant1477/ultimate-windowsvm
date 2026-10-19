#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
#   Ultimate WindowsVM — interactive installer
#   Repo : https://github.com/hopingboyz/ultimate-windowsvm
#
#   One-liner:
#     curl -fsSL https://raw.githubusercontent.com/hopingboyz/ultimate-windowsvm/main/install.sh | bash
#
#   The installer asks:
#     1) Which OS      → Windows 10 or Windows 11 (auto-suggested)
#     2) System config → CPU cores, RAM (GB), Disk (GB)
#     3) Install mode  → Fresh ISO install  OR  pre-built .qcow2 disk
#     4) Access mode   → noVNC + RDP / noVNC only / RDP only
#   …then builds the image and launches the VM container.
#
#   Flags (for non-interactive use):
#     --os win10|win11        --cores N        --ram GB         --disk GB
#     --mode iso|disk         --access novnc|rdp|both           --iso-url URL
#     --qcow2 /path/file.qcow2 (disk mode)     --port-novnc N   --port-rdp N
#     --no-tpm                --yes / -y       --uninstall      --help
# ══════════════════════════════════════════════════════════════════
set -euo pipefail

VERSION="1.0.0"
REPO="hopingboyz/ultimate-windowsvm"
IMAGE="ultimate-windowsvm:latest"
CONTAINER="ultimate-windowsvm"
SRC_DIR="${HOME}/.ultimate-windowsvm"
VOL_DATA="ultimate-windowsvm-data"
VOL_ISO="ultimate-windowsvm-iso"

# ── colors / output helpers ────────────────────────────────────────
C_G="\033[1;32m"; C_Y="\033[1;33m"; C_R="\033[1;31m"
C_C="\033[1;36m"; C_B="\033[1;94m"; C_0="\033[0m"

log()  { printf '%b\n' "${C_C}▸${C_0} $*"; }
ok()   { printf '%b\n' "${C_G}✔${C_0} $*"; }
warn() { printf '%b\n' "${C_Y}⚠${C_0} $*"; }
err()  { printf '%b\n' "${C_R}✖${C_0} $*" >&2; }
die()  { err "$*"; exit 1; }

banner() {
  printf '%b' "$C_B"
  cat <<'EOF'
  _   _ _   _ __  __    _    ____  __  __ ___ _   _   _____ __  __ _____ ____
 | | | | | | |  \/  |  / \  |  _ \|  \/  |_ _| \ | | | ____|  \/  | ____/ ___|
 | | | | | | | |\/| | / _ \ | |_) | |\/| || ||  \| | |  _| | |\/| |  _| \___ \
 | |_| | |_| | |  | |/ ___ \|  _ <| |  | || || |\  | | |___| |  | | |___ ___) |
  \___/ \___/|_|  |_/_/   \_\_| \_\_|  |_|___|_| \_| |_____|_|  |_|_____|____/
EOF
  printf '%b\n' "$C_0  Windows 10 & 11 in Docker • noVNC + RDP • v${VERSION}"
  printf '%b\n' "  https://github.com/hopingboyz/ultimate-windowsvm"
  echo ""
}

# ── prompt helpers (work even when piped: curl … | bash) ───────────
# stdin is the pipe in that case, so we read from /dev/tty when needed
TTY_FD=""
if [[ -t 0 ]]; then
  TTY_FD="stdin"
elif [[ -e /dev/tty ]] && { true < /dev/tty; } 2>/dev/null; then
  TTY_FD="/dev/tty"
fi

INTERACTIVE=0
if [[ -n "$TTY_FD" ]]; then INTERACTIVE=1; fi

ask() { # ask "prompt" "default" → echoes answer
  local prompt="$1" default="${2:-}" answer=""
  if [[ -n "$TTY_FD" ]]; then
    local colored
    colored="$(printf '%b' "${C_C}?${C_0} ${prompt}")"
    if [[ "$TTY_FD" == "stdin" ]]; then
      read -r -p "${colored} " answer || true
    else
      read -r -p "${colored} " answer < /dev/tty || true
    fi
  fi
  printf '%s' "${answer:-$default}"
}

ask_number() { # ask_number "prompt" default min max → echoes number
  local prompt="$1" default="$2" min="$3" max="$4" v=""
  while :; do
    v="$(ask "$prompt [$min-$max]" "$default")"
    if [[ "$v" =~ ^[0-9]+$ ]] && [[ "$v" -ge "$min" ]] && [[ "$v" -le "$max" ]]; then
      printf '%s' "$v"
      return 0
    fi
    if [[ "$INTERACTIVE" == "0" ]]; then
      printf '%s' "$default"
      return 0
    fi
    warn "Please enter a number between ${min} and ${max}"
  done
}

confirm() { # confirm "question" [default_y|default_n] → 0=yes
  local q="$1" def="${2:-y}" a=""
  if [[ "$INTERACTIVE" == "0" ]]; then
    [[ "$def" == "y" ]] && return 0 || return 1
  fi
  if [[ "$def" == "y" ]]; then
    a="$(ask "${q} [Y/n]" "y")"
  else
    a="$(ask "${q} [y/N]" "n")"
  fi
  [[ "$a" == "y" || "$a" == "Y" || "$a" == "yes" || "$a" == "YES" ]]
}

usage() {
  cat <<EOF
Usage: bash install.sh [options]

Interactive installer for Ultimate WindowsVM.

Options:
  --os win10|win11          Windows version (default: auto-suggested)
  --cores N                 vCPUs for the VM
  --ram GB                  RAM in GB
  --disk GB                 Virtual disk size in GB (ISO mode)
  --mode iso|disk           iso = fresh install from ISO, disk = pre-built qcow2
  --access novnc|rdp|both   Access method (default: both)
  --iso-url URL             Custom Windows ISO download URL
  --qcow2 PATH              Path to pre-built .qcow2 (disk mode)
  --port-novnc N            Host port for noVNC   (default: 6080)
  --port-rdp N              Host port for RDP     (default: 3389)
  --no-tpm                  Disable TPM 2.0 (Win11, for pre-patched ISOs)
  -y, --yes                 Non-interactive: accept all defaults
  --uninstall               Remove container, image and volumes
  -h, --help                Show this help
EOF
}

# ── defaults & argument parsing ────────────────────────────────────
OS="" CORES="" RAM_GB="" DISK_GB="" MODE="" ACCESS=""
ISO_URL="" QCOW2_PATH="" NOVNC_PORT="6080" RDP_PORT="3389" TPM="auto"
ASSUME_YES=0 DO_UNINSTALL=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --os)         OS="${2:-}"; shift 2 ;;
    --cores)      CORES="${2:-}"; shift 2 ;;
    --ram)        RAM_GB="${2:-}"; shift 2 ;;
    --disk)       DISK_GB="${2:-}"; shift 2 ;;
    --mode)       MODE="${2:-}"; shift 2 ;;
    --access)     ACCESS="${2:-}"; shift 2 ;;
    --iso-url)    ISO_URL="${2:-}"; shift 2 ;;
    --qcow2)      QCOW2_PATH="${2:-}"; shift 2 ;;
    --port-novnc) NOVNC_PORT="${2:-}"; shift 2 ;;
    --port-rdp)   RDP_PORT="${2:-}"; shift 2 ;;
    --no-tpm)     TPM="false"; shift ;;
    -y|--yes)     ASSUME_YES=1; shift ;;
    --uninstall)  DO_UNINSTALL=1; shift ;;
    -h|--help)    usage; exit 0 ;;
    *)            err "Unknown option: $1"; echo; usage; exit 1 ;;
  esac
done

# ── uninstall path ─────────────────────────────────────────────────
if [[ "$DO_UNINSTALL" == "1" ]]; then
  banner
  log "Removing Ultimate WindowsVM…"
  docker rm -f "$CONTAINER" 2>/dev/null || true
  docker rmi "$IMAGE" 2>/dev/null || true
  docker volume rm "$VOL_DATA" "$VOL_ISO" 2>/dev/null || true
  if [[ -d "$SRC_DIR" ]] && confirm "Also remove downloaded source at ${SRC_DIR}?" "n"; then
    rm -rf "$SRC_DIR"
  fi
  ok "Uninstalled. Goodbye 👋"
  exit 0
fi

banner

# ── host auto-detection ────────────────────────────────────────────
log "Detecting host system…"
HOST_CORES="$(nproc 2>/dev/null || echo 2)"
HOST_RAM_GB="$(awk '/MemTotal/ {printf "%d", $2/1024/1024}' /proc/meminfo 2>/dev/null || echo 4)"
KVM_OK=0
if [[ -e /dev/kvm ]]; then KVM_OK=1; fi

ok "Host CPU cores : ${HOST_CORES}"
ok "Host RAM       : ~${HOST_RAM_GB} GB"
if [[ "$KVM_OK" == "1" ]]; then
  ok "KVM            : available (near-native speed)"
else
  warn "KVM            : NOT available — VM will run in slow emulation mode"
  warn "  (Docker Desktop on macOS / Windows 10 does not expose /dev/kvm —"
  warn "   for best results run this on a Linux host with virtualization enabled)"
fi
echo ""

# ── docker check ───────────────────────────────────────────────────
if ! command -v docker >/dev/null 2>&1; then
  warn "Docker is not installed."
  if [[ "$INTERACTIVE" == "1" ]] && confirm "Install Docker automatically now (get.docker.com)?" "y"; then
    log "Installing Docker…"
    curl -fsSL "https://get.docker.com" | sh
    ok "Docker installed"
  else
    die "Docker is required. Install it from https://docs.docker.com/engine/install/ and re-run."
  fi
fi
if ! docker info >/dev/null 2>&1; then
  die "Cannot talk to the Docker daemon. Either:
  • start Docker (sudo systemctl start docker), or
  • add yourself to the docker group (sudo usermod -aG docker \$USER, then re-login), or
  • re-run this script with sudo."
fi
ok "Docker is ready"

# ── source code (clone when run via one-liner) ─────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
if [[ -f "${SCRIPT_DIR}/Dockerfile" ]]; then
  SRC_DIR="${SCRIPT_DIR}"
  log "Using source from: ${SRC_DIR}"
else
  if [[ ! -f "${SRC_DIR}/Dockerfile" ]]; then
    log "Downloading Ultimate WindowsVM source…"
    rm -rf "$SRC_DIR"
    if command -v git >/dev/null 2>&1; then
      git clone --depth=1 "https://github.com/${REPO}.git" "$SRC_DIR" >/dev/null 2>&1
    else
      TMP_DL="$(mktemp -d)"
      curl -fsSL "https://github.com/${REPO}/archive/refs/heads/main.tar.gz" | tar -xz -C "$TMP_DL"
      mv "${TMP_DL}/ultimate-windowsvm-main" "$SRC_DIR"
      rm -rf "$TMP_DL"
    fi
    ok "Source saved to: ${SRC_DIR}"
  fi
fi

# ── 1) OS choice (auto-suggested = "target autodetect") ────────────
SUGGEST=1
if [[ "$HOST_RAM_GB" -ge 8 ]]; then SUGGEST=2; fi

if [[ -z "$OS" ]]; then
  echo ""
  log "Which Windows version do you want to install?"
  local_tag=""
  [[ "$SUGGEST" == "1" ]] && local_tag="  ${C_G}← recommended for your system${C_0}"
  printf '   %b1%b) Windows 10  — lighter (1.1 GB ISO), great for low-spec hosts%b\n' "$C_G" "$C_0" "$local_tag"
  local_tag=""
  [[ "$SUGGEST" == "2" ]] && local_tag="  ${C_G}← recommended for your system${C_0}"
  printf '   %b2%b) Windows 11  — modern (5.4 GB ISO), UEFI + TPM 2.0 auto-configured%b\n' "$C_G" "$C_0" "$local_tag"
  OS_NUM="$(ask_number "Choose [1-2]" "$SUGGEST" 1 2)"
  if [[ "$OS_NUM" == "2" ]]; then OS="win11"; else OS="win10"; fi
fi
case "$OS" in win10|win11) ;; *) die "Invalid --os '$OS' (use win10 or win11)" ;; esac
ok "Target OS: ${OS}"

# ── 2) system config: cores / RAM / disk ───────────────────────────
DEF_CORES=$(( HOST_CORES / 2 ))
if [[ "$DEF_CORES" -lt 2 ]]; then DEF_CORES=2; fi
if [[ "$DEF_CORES" -gt 8 ]]; then DEF_CORES=8; fi

DEF_RAM=$(( HOST_RAM_GB / 2 ))
if [[ "$DEF_RAM" -lt 2 ]]; then DEF_RAM=2; fi
if [[ "$DEF_RAM" -gt 16 ]]; then DEF_RAM=16; fi

if [[ "$OS" == "win11" ]]; then DEF_DISK=80; else DEF_DISK=64; fi

echo ""
log "System configuration for the VM:"
if [[ -z "$CORES" ]]; then
  CORES="$(ask_number "CPU cores" "$DEF_CORES" 1 "$HOST_CORES")"
fi
if [[ -z "$RAM_GB" ]]; then
  RAM_GB="$(ask_number "RAM in GB" "$DEF_RAM" 2 "$HOST_RAM_GB")"
fi
if [[ -z "$DISK_GB" ]]; then
  DISK_GB="$(ask_number "Disk in GB (virtual, thin-provisioned)" "$DEF_DISK" 20 500)"
fi

if [[ "$RAM_GB" -ge "$HOST_RAM_GB" ]]; then
  warn "VM RAM (${RAM_GB} GB) >= host RAM (${HOST_RAM_GB} GB) — the host may become unstable"
fi
ok "VM config: ${CORES} vCPU • ${RAM_GB} GB RAM • ${DISK_GB} GB disk"

# ── 3) install mode: pre-built disk (default) OR fresh ISO install ─
if [[ -z "$MODE" ]]; then
  echo ""
  log "Install mode:"
  printf '   %b1%b) Pre-built disk image (.qcow2) — boots instantly (recommended)\n' "$C_G" "$C_0"
  printf '   %b2%b) Fresh install from ISO — downloads Windows automatically\n' "$C_G" "$C_0"
  MODE_NUM="$(ask_number "Choose [1-2]" 1 1 2)"
  if [[ "$MODE_NUM" == "2" ]]; then MODE="iso"; else MODE="disk"; fi
fi
case "$MODE" in iso|disk) ;; *) die "Invalid --mode '$MODE' (use iso or disk)" ;; esac

if [[ "$MODE" == "iso" ]]; then
  ok "Mode: fresh install from ISO"
  if [[ -n "$ISO_URL" ]]; then ok "Custom ISO URL will be used"
  else ok "Default ${OS} ISO will be downloaded automatically"; fi
else
  ok "Mode: pre-built disk image"
  if [[ -z "$QCOW2_PATH" ]]; then
    DETECTED_QCOW=""
    for cand in ./disk/*.qcow2 ./*.qcow2 "${SRC_DIR}/disk"/*.qcow2; do
      if [[ -s "$cand" ]]; then
        DETECTED_QCOW="$(readlink -f "$cand" 2>/dev/null || echo "$cand")"
        break
      fi
    done
    if [[ -n "$DETECTED_QCOW" ]]; then
      ok "Found disk image: ${DETECTED_QCOW}"
    fi
    QCOW2_PATH="$(ask "Path to your .qcow2 file" "$DETECTED_QCOW")"
  fi
  if [[ -z "$QCOW2_PATH" ]]; then
    die "Disk mode needs a .qcow2 file — drop it into ./disk/ or pass --qcow2 /path/file.qcow2"
  fi
  QCOW2_PATH="$(readlink -f "$QCOW2_PATH" 2>/dev/null || echo "$QCOW2_PATH")"
  if [[ ! -s "$QCOW2_PATH" ]]; then
    die "File not found or empty: ${QCOW2_PATH}"
  fi
  ok "Disk image: ${QCOW2_PATH}"
fi

# ── 4) access mode: noVNC / RDP / both ─────────────────────────────
if [[ -z "$ACCESS" ]]; then
  echo ""
  log "How do you want to access the VM?"
  printf '   %b1%b) Both    — noVNC in browser + RDP  (recommended)\n' "$C_G" "$C_0"
  printf '   %b2%b) noVNC   — browser access only (install/repair screen)\n' "$C_G" "$C_0"
  printf '   %b3%b) RDP     — Remote Desktop only (needs Windows already set up)\n' "$C_G" "$C_0"
  ACCESS_NUM="$(ask_number "Choose [1-3]" 1 1 3)"
  case "$ACCESS_NUM" in
    2) ACCESS="novnc" ;;
    3) ACCESS="rdp" ;;
    *) ACCESS="both" ;;
  esac
fi
case "$ACCESS" in novnc|rdp|both) ;; *) die "Invalid --access '$ACCESS' (use novnc, rdp or both)" ;; esac

# Fresh ISO installs need a screen to click through Windows setup
if [[ "$MODE" == "iso" && "$ACCESS" == "rdp" ]]; then
  warn "Fresh ISO installs need a display — noVNC will be enabled too (ignore it after setup)."
  ACCESS="both"
fi
ok "Access: ${ACCESS}"

# ── summary + confirmation ─────────────────────────────────────────
ACCESS_LABEL="noVNC + RDP"
[[ "$ACCESS" == "novnc" ]] && ACCESS_LABEL="noVNC (browser) only"
[[ "$ACCESS" == "rdp" ]]   && ACCESS_LABEL="RDP only"
MODE_LABEL="Fresh install from ISO"
[[ "$MODE" == "disk" ]] && MODE_LABEL="Pre-built disk: ${QCOW2_PATH}"

echo ""
printf '%b\n' "${C_B}  ┌─────────────────────────────────────────────────────────┐${C_0}"
printf '%b\n' "${C_B}  │${C_0}  INSTALL SUMMARY                                        ${C_B}│${C_0}"
printf '%b\n' "${C_B}  ├─────────────────────────────────────────────────────────┤${C_0}"
printf '%b\n' "${C_B}  │${C_0}  OS      : ${OS}                                          ${C_B}│${C_0}"
printf '%b\n' "${C_B}  │${C_0}  System  : ${CORES} vCPU • ${RAM_GB} GB RAM • ${DISK_GB} GB disk                ${C_B}│${C_0}"
printf '%b\n' "${C_B}  │${C_0}  Mode    : ${MODE_LABEL}"
printf '%b\n' "${C_B}  │${C_0}  Access  : ${ACCESS_LABEL}                     ${C_B}│${C_0}"
printf '%b\n' "${C_B}  │${C_0}  Ports   : noVNC ${NOVNC_PORT} • RDP ${RDP_PORT}                        ${C_B}│${C_0}"
printf '%b\n' "${C_B}  └─────────────────────────────────────────────────────────┘${C_0}"
echo ""

if [[ "$ASSUME_YES" != "1" ]]; then
  confirm "Proceed with installation?" "y" || die "Cancelled by user"
fi

# ── build image ────────────────────────────────────────────────────
echo ""
log "Building Docker image (this takes a few minutes on first run)…"
if ! docker build -t "$IMAGE" "$SRC_DIR"; then
  die "Docker build failed. Check the output above and re-run this script."
fi
ok "Image built: ${IMAGE}"

# ── replace existing container ─────────────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  warn "Existing container '${CONTAINER}' found — removing it (your data volume is kept)"
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
fi

# ── assemble & run ─────────────────────────────────────────────────
PORT_ARGS=()
if [[ "$ACCESS" == "novnc" || "$ACCESS" == "both" ]]; then
  PORT_ARGS+=(-p "${NOVNC_PORT}:6080")
fi
if [[ "$ACCESS" == "rdp" || "$ACCESS" == "both" ]]; then
  PORT_ARGS+=(-p "${RDP_PORT}:3389")
fi

VOL_ARGS=(-v "${VOL_DATA}:/data")
if [[ "$MODE" == "iso" ]]; then
  VOL_ARGS+=(-v "${VOL_ISO}:/iso")
else
  VOL_ARGS+=(-v "${QCOW2_PATH}:/data/disk.qcow2")
fi

DEV_ARGS=()
if [[ "$KVM_OK" == "1" ]]; then
  DEV_ARGS=(--device /dev/kvm)
fi

ENV_ARGS=(
  -e OS_VERSION="$OS"
  -e MODE="$MODE"
  -e ACCESS="$ACCESS"
  -e CORES="$CORES"
  -e RAM="${RAM_GB}G"
  -e DISK="${DISK_GB}G"
  -e ENABLE_TPM="$TPM"
)
if [[ -n "$ISO_URL" && "$MODE" == "iso" ]]; then
  ENV_ARGS+=(-e ISO_URL="$ISO_URL")
fi

log "Starting container…"
CID="$(docker run -d --name "$CONTAINER" \
  "${DEV_ARGS[@]}" "${PORT_ARGS[@]}" "${VOL_ARGS[@]}" "${ENV_ARGS[@]}" \
  --restart unless-stopped \
  --stop-timeout 90 \
  "$IMAGE")"
ok "Container started: ${CID}"

# ── final info panel ───────────────────────────────────────────────
HOST_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"
echo ""
printf '%b\n' "${C_G}  ═══════════════════════════════════════════════════════════${C_0}"
printf '%b\n' "${C_G}   ✔  Ultimate WindowsVM (${OS}) is running!${C_0}"
printf '%b\n' "${C_G}  ═══════════════════════════════════════════════════════════${C_0}"
echo ""
if [[ "$ACCESS" == "novnc" || "$ACCESS" == "both" ]]; then
  printf '   🌐  noVNC (browser) : %bhttp://localhost:%s/vnc.html%b\n' "$C_B" "$NOVNC_PORT" "$C_0"
  [[ -n "$HOST_IP" ]] && printf '       on your LAN    : %bhttp://%s:%s/vnc.html%b\n' "$C_B" "$HOST_IP" "$NOVNC_PORT" "$C_0"
  echo ""
fi
if [[ "$ACCESS" == "rdp" || "$ACCESS" == "both" ]]; then
  printf '   🔌  RDP             : %b%s:%s%b  (username/password = the account you create in Windows)\n' "$C_B" "${HOST_IP:-localhost}" "$RDP_PORT" "$C_0"
  printf '       💡 After installing Windows, enable: Settings → System → Remote Desktop\n'
  echo ""
fi
printf '   ⏳  First boot installs Windows — open noVNC and wait 20–60 min (KVM)\n'
printf '   💾  Disk data persists across restarts (volume: %s)\n' "$VOL_DATA"
echo ""
printf '   %bManagement:%b\n' "$C_C" "$C_0"
printf '     docker logs -f %s        # live VM output\n' "$CONTAINER"
printf '     docker stop %s           # graceful shutdown (ACPI powerdown)\n' "$CONTAINER"
printf '     docker start %s          # boot it again\n' "$CONTAINER"
printf '     bash %s/install.sh --uninstall   # full removal\n' "$SRC_DIR"
echo ""
ok "Done — enjoy your Windows VM! ⭐ Star the repo if you like it: https://github.com/${REPO}"
