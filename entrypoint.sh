#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════
#  Ultimate WindowsVM — container entrypoint
#
#  Boots a Windows 10 / 11 VM with auto-detected host capabilities.
#
#  Environment variables:
#    OS_VERSION   win10 | win11                   (default: win10)
#    MODE         iso | disk                      (default: iso)
#                 iso  = download ISO + fresh Windows install
#                 disk = boot a pre-built /data/disk.qcow2
#    ACCESS       novnc | rdp | both              (default: both)
#    CORES        vCPU count, e.g. 4              (default: 4)
#    RAM          e.g. 4G                         (default: 4G)
#    DISK         e.g. 64G                        (default: 64G)
#    ISO_URL      custom ISO download URL (MODE=iso only)
#    NOVNC_PORT   noVNC web port inside container (default: 6080)
#    ENABLE_TPM   auto | true | false  (auto = enabled for win11)
# ══════════════════════════════════════════════════════════════════
set -euo pipefail

OS_VERSION="${OS_VERSION:-win10}"
MODE="${MODE:-iso}"
ACCESS="${ACCESS:-both}"
CORES="${CORES:-4}"
RAM="${RAM:-4G}"
DISK="${DISK:-64G}"
ISO_URL="${ISO_URL:-}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
ENABLE_TPM="${ENABLE_TPM:-auto}"

DISK_IMG="/data/disk.qcow2"
ISO_IMG="/iso/os.iso"
MONITOR_SOCK="/data/qemu-monitor.sock"
NOVNC_WEB="/usr/share/novnc"

log()  { printf '\033[1;36m[ultimate-windowsvm]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[ultimate-windowsvm]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ultimate-windowsvm]\033[0m %s\n' "$*" >&2; exit 1; }

# ─────────────────────────────────────────────── validate & defaults
case "$OS_VERSION" in
  win10|win11) ;;
  *) die "Unsupported OS_VERSION '$OS_VERSION' (use win10 or win11)" ;;
esac
case "$MODE" in
  iso|disk) ;;
  *) die "Unsupported MODE '$MODE' (use iso or disk)" ;;
esac
case "$ACCESS" in
  novnc|rdp|both) ;;
  *) die "Unsupported ACCESS '$ACCESS' (use novnc, rdp or both)" ;;
esac

# ISO sources: first entry = primary, remaining = automatic fallbacks.
# win10 primary = the exact link shipped with the original windows10vm repo.
ISO_URLS=()
if [[ -n "$ISO_URL" ]]; then
  ISO_URLS=("$ISO_URL")
else
  case "$OS_VERSION" in
    win10)
      ISO_URLS=(
        "https://archive.org/download/windows-10-lite-edition-19h2-x64/Windows%2010%20Lite%20Edition%2019H2%20x64.iso"
        "https://archive.org/download/windows-10-22-h-2-lite-x-64/Win10Daniel.iso"
      )
      ;;
    win11)
      ISO_URLS=(
        "https://archive.org/download/windows-11-24h2-iso_202501/Win11_24H2_English_x64.iso"
        "https://archive.org/download/windows11_20220930/Win11_22H2_English_x64v1.iso"
      )
      ;;
  esac
fi

mkdir -p /data /iso

# ─────────────────────────────────────────────── auto-detect KVM
QEMU=(qemu-system-x86_64)
MACHINE="pc"

if [[ -e /dev/kvm ]]; then
  log "KVM acceleration detected — near-native performance"
  QEMU+=(-enable-kvm -cpu host)
else
  warn "/dev/kvm not found — falling back to software emulation (TCG). This will be SLOW."
  QEMU+=(-cpu qemu64)
fi

# ─────────────────────────────── Windows 11 extras: UEFI + TPM 2.0
TPM_ARGS=()
if [[ "$OS_VERSION" == "win11" ]]; then
  MACHINE="q35"

  if [[ -f /usr/share/OVMF/OVMF_CODE.fd ]]; then
    mkdir -p /data/uefi
    if [[ ! -f /data/uefi/OVMF_VARS.fd ]]; then
      cp /usr/share/OVMF/OVMF_VARS.fd /data/uefi/OVMF_VARS.fd
    fi
    QEMU+=(
      -drive "if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE.fd"
      -drive "if=pflash,format=raw,file=/data/uefi/OVMF_VARS.fd"
    )
    log "UEFI (OVMF) firmware enabled"
  else
    warn "OVMF firmware not found — falling back to legacy BIOS"
  fi

  if [[ "$ENABLE_TPM" != "false" && -x /usr/bin/swtpm ]]; then
    mkdir -p /data/tpm
    rm -f /data/tpm/swtpm.sock
    swtpm socket --tpm2 --tpmstate "dir=/data/tpm" \
      --ctrl "type=unixio,path=/data/tpm/swtpm.sock" --daemon
    TPM_READY=0
    for _ in 1 2 3 4 5; do
      if [[ -S /data/tpm/swtpm.sock ]]; then TPM_READY=1; break; fi
      sleep 1
    done
    if [[ "$TPM_READY" == "1" ]]; then
      TPM_ARGS=(-chardev "socket,id=chrtpm,path=/data/tpm/swtpm.sock"
                -tpmdev "emulator,id=tpm0,chardev=chrtpm"
                -device "tpm-tis,tpmdev=tpm0")
      log "TPM 2.0 device enabled (Windows 11 requirement satisfied)"
    else
      warn "swtpm socket not ready — continuing without TPM (patched ISOs still install)"
    fi
  fi
fi

# ─────────────────────────────────────────────── ISO downloader (hardened)
# Browser-style User-Agent + retries + resume + size sanity check + fallbacks
# (archive.org throttles plain wget UAs and drops idle connections)
download_iso() { # download_iso DEST URL...
  local dest="$1"; shift
  local url size_mb
  for url in "$@"; do
    log "Source: ${url}"
    if wget -c -q --show-progress \
         --tries=7 --waitretry=15 --timeout=60 --retry-connrefused \
         --user-agent="Mozilla/5.0 (X11; Linux x86_64) UltimateWindowsVM/1.0" \
         -O "${dest}.part" "$url"; then
      size_mb=$(( $(stat -c%s "${dest}.part") / 1024 / 1024 ))
      if [[ "$size_mb" -lt 500 ]]; then
        warn "Downloaded file is only ${size_mb} MB — not a valid ISO, trying next source…"
        rm -f "${dest}.part"
        continue
      fi
      mv "${dest}.part" "$dest"
      log "ISO downloaded successfully (${size_mb} MB)"
      return 0
    fi
    warn "This source failed — trying the next one…"
    rm -f "${dest}.part"
  done
  return 1
}

# ─────────────────────────────────────────────── disk / ISO setup
FRESH_DISK=0
if [[ "$MODE" == "disk" ]]; then
  if [[ ! -s "$DISK_IMG" ]]; then
    die "MODE=disk but $DISK_IMG is missing or empty.
Mount your pre-built qcow2 file at /data/disk.qcow2, e.g.:
  docker run ... -v /path/to/windows11.qcow2:/data/disk.qcow2 ..."
  fi
  log "Booting pre-built disk image: $DISK_IMG"
else
  if [[ ! -s "$ISO_IMG" ]]; then
    log "Downloading Windows ISO (first run only — auto-resumes if interrupted)…"
    if ! download_iso "$ISO_IMG" "${ISO_URLS[@]}"; then
      die "All ISO sources failed. Check your network, or pass a custom ISO_URL / --iso-url."
    fi
  else
    log "ISO already present — skipping download"
  fi

  if [[ ! -s "$DISK_IMG" ]]; then
    log "Creating ${DISK} virtual disk (thin-provisioned qcow2)…"
    qemu-img create -f qcow2 "$DISK_IMG" "$DISK" >/dev/null
    FRESH_DISK=1
  fi
fi

# ─────────────────────────────────────────────── networking
NETDEV="user,id=net0"
if [[ "$ACCESS" == "rdp" || "$ACCESS" == "both" ]]; then
  NETDEV="${NETDEV},hostfwd=tcp::3389-:3389"
fi

# ─────────────────────────────────────────────── build QEMU command
BOOT_ORDER="order=c,menu=on"
if [[ "$FRESH_DISK" == "1" ]]; then
  BOOT_ORDER="order=d,menu=on"
fi

QEMU+=(
  -machine "${MACHINE},accel=kvm:tcg"
  -m "$RAM"
  -smp "$CORES"
  -vga std
  -usb -device usb-tablet
  -rtc "base=localtime,clock=host"
  -name "ultimate-windowsvm-${OS_VERSION}"
  -drive "file=${DISK_IMG},format=qcow2"
  "${TPM_ARGS[@]}"
  -monitor "unix:${MONITOR_SOCK},server,nowait"
  -boot "$BOOT_ORDER"
  -vnc :0
  -netdev "$NETDEV" -device "e1000,netdev=net0"
)
if [[ "$MODE" == "iso" ]]; then
  QEMU+=(-drive "file=${ISO_IMG},media=cdrom")
fi

# ─────────────────────────────────────────────── start services
rm -f "$MONITOR_SOCK"

WEBSOCKIFY_PID=""
if [[ "$ACCESS" == "novnc" || "$ACCESS" == "both" ]]; then
  websockify --web "$NOVNC_WEB" "$NOVNC_PORT" localhost:5900 &
  WEBSOCKIFY_PID=$!
  log "noVNC listening on port ${NOVNC_PORT}"
fi

log "Starting VM: ${CORES} vCPU • ${RAM} RAM • ${MACHINE} machine"
"${QEMU[@]}" &
QEMU_PID=$!

# Graceful shutdown: ACPI powerdown via QEMU monitor, force-kill fallback
shutdown_vm() {
  log "Shutdown requested — sending ACPI powerdown to Windows…"
  if [[ -S "$MONITOR_SOCK" ]]; then
    printf 'system_powerdown\n' | nc -U "$MONITOR_SOCK" >/dev/null 2>&1 || true
    for _ in $(seq 1 45); do
      if ! kill -0 "$QEMU_PID" 2>/dev/null; then break; fi
      sleep 1
    done
  fi
  if kill -0 "$QEMU_PID" 2>/dev/null; then
    warn "VM did not power down in time — forcing stop"
    kill -TERM "$QEMU_PID" 2>/dev/null || true
  fi
  if [[ -n "$WEBSOCKIFY_PID" ]]; then
    kill "$WEBSOCKIFY_PID" 2>/dev/null || true
  fi
}
trap shutdown_vm TERM INT

echo ""
log "═══════════════════════════════════════════════════════════════"
log "  Ultimate WindowsVM (${OS_VERSION}) is running"
if [[ "$ACCESS" == "novnc" || "$ACCESS" == "both" ]]; then
  log "  🌐  noVNC (browser) : http://localhost:${NOVNC_PORT}/vnc.html"
fi
if [[ "$ACCESS" == "rdp" || "$ACCESS" == "both" ]]; then
  log "  🔌  RDP             : <host-ip>:3389"
  log "      (enable 'Remote Desktop' inside Windows first — see README)"
fi
log "  ⏳  Fresh installs take 20–60 min with KVM (much longer on TCG)"
log "  💾  Disk data persists in the /data volume across restarts"
log "═══════════════════════════════════════════════════════════════"
echo ""

wait "$QEMU_PID" || true
log "VM exited — container stopping"
