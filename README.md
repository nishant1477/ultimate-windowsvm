<div align="center">

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:0078D4,50:00A4EF,100:00C4CC&height=190&section=header&text=Ultimate%20WindowsVM&fontSize=44&fontColor=ffffff&desc=Windows%2010%20%2F%2011%20in%20Docker%20%E2%80%A2%20One%20Installer%20%E2%80%A2%20noVNC%20%2B%20RDP&descSize=16&descColor=ffffff&animation=fadeIn" width="100%"/>

<!-- badges -->
[![CI](https://img.shields.io/github/actions/workflow/status/hopingboyz/ultimate-windowsvm/ci.yml?branch=main&style=for-the-badge&label=CI&logo=githubactions&logoColor=white)](https://github.com/hopingboyz/ultimate-windowsvm/actions/workflows/ci.yml)
![Docker](https://img.shields.io/badge/Docker-QEMU%20%2B%20KVM-2496ED?style=for-the-badge&logo=docker&logoColor=white)
![Windows](https://img.shields.io/badge/Windows-10%20%7C%2011-0078D4?style=for-the-badge&logo=windows&logoColor=white)
![noVNC](https://img.shields.io/badge/noVNC-Browser%20Access-00C4CC?style=for-the-badge&logo=googlechrome&logoColor=white)
![RDP](https://img.shields.io/badge/RDP-Port%203389-5E5E5E?style=for-the-badge&logo=microsoftremotedesktop&logoColor=white)
![Platform](https://img.shields.io/badge/Platform-Linux-FCC624?style=for-the-badge&logo=linux&logoColor=black)
[![License](https://img.shields.io/badge/License-DragonLabs%20MIT%2B-blue?style=for-the-badge&logo=github&logoColor=white)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-2ea44f?style=for-the-badge&logo=github&logoColor=white)](.github/PULL_REQUEST_TEMPLATE.md)

**One repo. One command. Any Windows VM.**
The combined evolution of *windows10vm* + *Windows11VM* — with an interactive installer, auto-detected hardware, and full CI.

</div>

---

## 📑 Table of Contents

- [✨ Features](#-features)
- [🚀 Quick Start](#-quick-start)
- [🧙 What the Installer Asks](#-what-the-installer-asks)
- [🐳 Manual Installation](#-manual-installation)
- [🔌 Accessing the VM](#-accessing-the-vm)
- [⚙️ Configuration Reference](#️-configuration-reference)
- [🖥️ Recommended Specs](#️-recommended-specs)
- [🤖 GitHub Workflows](#-github-workflows)
- [🧰 Troubleshooting](#-troubleshooting)
- [📁 Project Structure](#-project-structure)
- [⚠️ Disclaimer](#️-disclaimer)
- [📜 License](#-license)

---

## ✨ Features

| | |
|---|---|
| 🎯 **Auto-detect everything** | Suggests the best Windows version for your host, detects KVM, cores, and RAM automatically |
| 🪟 **Windows 10 & 11** | One image for both — Windows 11 gets **UEFI (OVMF) + TPM 2.0** enabled automatically |
| 🧙 **Interactive installer** | Choose OS → cores / RAM / disk → install mode → access mode, then it just runs |
| 📦 **Both install modes** | Boot a pre-built `.qcow2` instantly *(default — auto-detected in `./disk/`)* or fresh-install from ISO *(auto-downloaded)* |
| 🔌 **Both access modes** | **noVNC** in the browser and/or native **RDP** — your choice at install time |
| ⚡ **KVM acceleration** | Near-native speed when `/dev/kvm` exists, graceful TCG fallback when it doesn't |
| 💾 **Persistent storage** | Disk and ISO live in Docker volumes — restart anytime, your data stays |
| 🛑 **Graceful shutdown** | ACPI power-down on `docker stop` (no corrupted qcow2 files) |
| 🤖 **Full CI** | ShellCheck linting + Docker build smoke-test on every push |
| 🖥️ **Free RDP workflow** | Spin up a Windows VM on GitHub Actions with an ngrok tunnel in one click |

---

## 🚀 Quick Start

**One-liner** — open a terminal on any Linux host with Docker and paste:

```bash
curl -fsSL https://raw.githubusercontent.com/nishant1477/ultimate-windowsvm/main/install.sh | bash
```

That's it. The installer will ask you a few questions (or use flags to skip them):

```bash
# Fully non-interactive example:
curl -fsSL https://raw.githubusercontent.com/nishant1477/ultimate-windowsvm/main/install.sh | bash -s -- \
  --os win11 --cores 4 --ram 8 --disk 80 --mode iso --access both --yes
```

> [!TIP]
> **Requirements:** Linux host (best), Docker Engine, and `/dev/kvm` for fast virtualization.
> No Docker yet? The installer offers to install it for you.
> 💡 **Already have a Windows disk?** Drop your `.qcow2` into `./disk/` — the installer
> auto-detects it and boots instantly (no ISO download needed).

---

## 🧙 What the Installer Asks

```
  _   _ _   _ __  __    _    ____  __  __ ___ _   _   _____ __  __ _____ ____
 | | | | | | |  \/  |  / \  |  _ \|  \/  |_ _| \ | | | ____|  \/  | ____/ ___|
 | | | | | | | |\/| | / _ \ | |_) | |\/| || ||  \| | |  _| | |\/| |  _| \___ \
 | |_| | |_| | |  | |/ ___ \|  _ <| |  | || || |\  | | |___| |  | | |___ ___) |
```

| Step | Prompt | Default (auto-detected) |
|:----:|--------|-------------------------|
| 1️⃣ | **Which OS?** Windows 10 or Windows 11 | Suggested from your host RAM (≥ 8 GB → Win11) |
| 2️⃣ | **System config** — CPU cores | Half of your host cores (2–8) |
| 2️⃣ | **System config** — RAM in GB | Half of your host RAM (2–16) |
| 2️⃣ | **System config** — Disk in GB | 64 GB (Win10) / 80 GB (Win11), thin-provisioned |
| 3️⃣ | **Install mode** — pre-built `.qcow2` or fresh ISO | Pre-built qcow2 (auto-detects `./disk/`) |
| 4️⃣ | **Access mode** — noVNC / RDP / both | Both |

Then it builds the image, starts the container, and prints your access links. ☕

<details>
<summary><b>All installer flags (for scripts & VPS provisioning)</b></summary>

| Flag | Description | Default |
|------|-------------|---------|
| `--os win10\|win11` | Windows version | auto-suggested |
| `--cores N` | vCPUs for the VM | auto |
| `--ram GB` | RAM in GB | auto |
| `--disk GB` | Virtual disk size | auto |
| `--mode iso\|disk` | Install mode | `iso` |
| `--access novnc\|rdp\|both` | Access method | `both` |
| `--iso-url URL` | Custom ISO download URL | per-OS default |
| `--qcow2 PATH` | Pre-built disk file (disk mode) | — |
| `--port-novnc N` | Host port for noVNC | `6080` |
| `--port-rdp N` | Host port for RDP | `3389` |
| `--no-tpm` | Disable TPM 2.0 (pre-patched Win11 ISOs) | auto |
| `-y, --yes` | Accept all defaults, no prompts | — |
| `--uninstall` | Remove container, image & volumes | — |

</details>

---

## 🐳 Manual Installation

Prefer to run things yourself? No problem.

```bash
git clone https://github.com/hopingboyz/ultimate-windowsvm.git
cd ultimate-windowsvm

# Build the image
docker build -t ultimate-windowsvm .

# Windows 11 fresh install — 4 cores, 8 GB RAM, 80 GB disk, noVNC + RDP
docker run -d --name ultimate-windowsvm \
  --device /dev/kvm \
  -p 6080:6080 -p 3389:3389 \
  -v ultimate-windowsvm-data:/data \
  -v ultimate-windowsvm-iso:/iso \
  -e OS_VERSION=win11 -e MODE=iso -e ACCESS=both \
  -e CORES=4 -e RAM=8G -e DISK=80G \
  --restart unless-stopped --stop-timeout 90 \
  ultimate-windowsvm
```

**Or with Docker Compose:**

```bash
cp .env.example .env      # edit OS_VERSION, CORES, RAM, DISK …
docker compose up -d --build
```

> [!NOTE]
> On hosts **without** `/dev/kvm`, remove the `devices:` line from `docker-compose.yml`
> (or drop `--device /dev/kvm` from the `docker run` command). The VM falls back to
> software emulation — functional, but slow.

---

## 🔌 Accessing the VM

| Method | URL / Address | Use for |
|--------|---------------|---------|
| 🌐 **noVNC** | `http://localhost:6080/vnc.html` | Installing Windows, watching the boot screen, repairs |
| 🔌 **RDP** | `localhost:3389` | Daily use — native client, better performance |

**First boot flow:**

1. Open **noVNC** and wait — Windows installs itself (20–60 min with KVM ☕)
2. Complete the Windows setup (create your username & password)
3. Enable RDP inside Windows: **Settings → System → Remote Desktop → On**
4. Connect with your favourite RDP client to `localhost:3389` 🎉

> [!IMPORTANT]
> RDP only works **after** it is enabled inside the guest Windows. noVNC always works
> — it is your safety net if RDP misbehaves.

---

## ⚙️ Configuration Reference

All configuration happens through environment variables (the installer sets them for you):

<details open>
<summary><b>Environment variables</b></summary>

| Variable | Values | Description |
|----------|--------|-------------|
| `OS_VERSION` | `win10` \| `win11` | Target Windows version |
| `MODE` | `iso` \| `disk` | Fresh ISO install or pre-built qcow2 |
| `ACCESS` | `novnc` \| `rdp` \| `both` | Which ports/services to expose |
| `CORES` | `4` | vCPUs assigned to the VM |
| `RAM` | `4G` | Memory assigned to the VM |
| `DISK` | `64G` | Virtual disk size (thin-provisioned) |
| `ISO_URL` | any URL | Custom ISO source (MODE=iso) |
| `ENABLE_TPM` | `auto` \| `true` \| `false` | TPM 2.0 for Win11 (auto = on) |
| `NOVNC_PORT` | `6080` | noVNC port **inside** the container |

</details>

<details>
<summary><b>Default ISO sources</b></summary>

| OS | Primary source | Fallback (automatic) |
|----|----------------|----------------------|
| Windows 10 | [Lite 19H2 x64](https://archive.org/details/windows-10-lite-edition-19h2-x64) · 1.1 GB | [Win10 Pro Lite 22H2](https://archive.org/details/windows-10-22-h-2-lite-x-64) · 1.2 GB |
| Windows 11 | [official 24H2 x64](https://archive.org/details/windows-11-24h2-iso_202501) · 5.4 GB | [official 22H2 x64](https://archive.org/details/windows11_20220930) · 5.2 GB |

Downloads are hardened against flaky mirrors: browser-style User-Agent, **7 retries**
with backoff, **automatic resume** of interrupted downloads, a **size sanity check**
(fakes < 500 MB are rejected), and an **automatic fallback** to the second source if
the first one fails. Swap in any ISO with `--iso-url` / `ISO_URL=` — a genuine
Microsoft ISO is the safest choice.

</details>

---

## 🖥️ Recommended Specs

| Profile | Windows 10 | Windows 11 |
|---------|-----------:|-----------:|
| **Minimum** | 2 cores • 2 GB • 32 GB | 2 cores • 4 GB • 48 GB |
| **Comfortable** ✅ | 4 cores • 4 GB • 64 GB | 4 cores • 8 GB • 80 GB |
| **Gaming / heavy** | 6 cores • 8 GB • 128 GB | 8 cores • 16 GB • 128 GB |

> The disk is **thin-provisioned** (qcow2) — it only grows as Windows fills it, so a
> "80 GB" disk takes just a few GB on your host at first.

---

## 🤖 GitHub Workflows

This repo ships with two workflows under [`.github/workflows/`](.github/workflows/):

### 1. CI — ShellCheck + Docker build
Runs automatically on every push/PR to `main`:
- 🔍 **ShellCheck** lints `install.sh` and `entrypoint.sh`
- 🐳 **Docker build** + smoke test verifies all binaries (QEMU, swtpm, noVNC, OVMF) are present in the image

[![CI status](https://img.shields.io/github/actions/workflow/status/hopingboyz/ultimate-windowsvm/ci.yml?branch=main&style=flat-square&label=run%20status)](https://github.com/hopingboyz/ultimate-windowsvm/actions/workflows/ci.yml)

### 2. RDP workflow — free Windows VM on GitHub Actions ✨
One-click Windows VM you can RDP into through an ngrok tunnel:

1. Get a free authtoken at [dashboard.ngrok.com](https://dashboard.ngrok.com/get-started/your-authtoken)
2. Add it as a repo secret: **Settings → Secrets and variables → Actions → `NGROK_AUTH`**
   *(optional: `RDP_PASSWORD` secret for a custom password)*
3. **Actions → Windows VM • RDP Access → Run workflow**
4. Open the job log → copy the printed **address** → connect with any RDP client:

   | | |
   |---|---|
   | **Address** | from the log (e.g. `0.tcp.in.ngrok.io:12345`) |
   | **Username** | `runneradmin` |
   | **Password** | your `RDP_PASSWORD` secret, or `UltimateVM@2025` |

> [!WARNING]
> Sessions last up to **6 hours** (GitHub-hosted runner limit). Use this for
> legitimate testing/debugging — GitHub's ToS prohibits using runners as free
> personal cloud machines.

---

## 🧰 Troubleshooting

<details>
<summary><b>🐢 The VM is extremely slow</b></summary>

Your host has no `/dev/kvm`:

```bash
ls -l /dev/kvm                       # does it exist?
egrep -c '(vmx|svm)' /proc/cpuinfo   # >0 = CPU supports virtualization
```

- Enable **VT-x / AMD-V** (and **IOMMU**) in your BIOS/UEFI
- Load the module: `sudo modprobe kvm_intel` (or `kvm_amd`)
- Add yourself to the kvm group: `sudo usermod -aG kvm $USER`
- ⚠️ Docker Desktop on **macOS** and **Windows 10** does not expose KVM — use a Linux host
</details>

<details>
<summary><b>🔌 RDP refuses to connect</b></summary>

- RDP must be enabled **inside Windows** first: Settings → System → Remote Desktop
- Only publish port 3389 when `ACCESS=rdp|both` — re-run the installer with `--access both`
- Check the container is healthy: `docker ps` and `docker logs ultimate-windowsvm`
</details>

<details>
<summary><b>🪟 Windows 11 says "This PC can't run Windows 11"</b></summary>

Ultimate WindowsVM auto-enables **UEFI + TPM 2.0**, which satisfies the requirement on
stock ISOs. If you are on a very old checkout:

- Make sure you rebuilt the image (`docker build -t ultimate-windowsvm .`)
- Only use `--no-tpm` for pre-patched/bypass ISOs
</details>

<details>
<summary><b>📥 ISO download fails or is slow</b></summary>

The default ISOs are served from archive.org (free, but sometimes slow). Point to your
own mirror:

```bash
bash install.sh --iso-url "https://your-mirror/Win11_24H2_English_x64.iso"
```

Downloads resume automatically on retry.
</details>

<details>
<summary><b>🚫 Port already in use (6080 / 3389)</b></summary>

Map different host ports:

```bash
bash install.sh --port-novnc 8080 --port-rdp 13389
```
</details>

<details>
<summary><b>🗑️ Full reset / uninstall</b></summary>

```bash
bash install.sh --uninstall          # removes container + image + volumes
```
</details>

---

## 📁 Project Structure

```text
ultimate-windowsvm/
├── install.sh                     # 🧙 interactive installer (the one-liner)
├── entrypoint.sh                  # VM boot logic: autodetect, modes, graceful shutdown
├── Dockerfile                     # unified image: QEMU + noVNC + OVMF + swtpm
├── docker-compose.yml             # compose deployment
├── .env.example                   # environment template
├── LICENSE                        # DragonLabs MIT+
└── .github/
    ├── workflows/
    │   ├── ci.yml                 # ShellCheck + Docker build smoke test
    │   └── rdp.yml                # free Windows VM with RDP tunnel (ngrok)
    ├── ISSUE_TEMPLATE/
    │   ├── bug_report.yml         # structured bug reports
    │   ├── feature_request.yml    # structured feature requests
    │   └── config.yml
    ├── PULL_REQUEST_TEMPLATE.md
    └── SECURITY.md                # private vulnerability reporting + hardening notes
```

---

## ⚠️ Disclaimer

This project is for **personal, lab, and educational use**. You are responsible for
holding a valid Windows license for any guest OS you install, and for choosing ISO
sources you trust (modified "lite" ISOs from random mirrors may contain malware —
prefer genuine Microsoft media). The container requires KVM device access; do not run
it on multi-tenant hosts you don't control, and never expose port 3389 directly to the
internet without a VPN or authenticated tunnel.

---

## 📜 License

Released under the [DragonLabs MIT+ License](LICENSE) — free to use, modify, and
redistribute with attribution to **Immortal**.

<div align="center">

**⭐ Found this useful? Star the repo — it helps a lot!**

<img src="https://capsule-render.vercel.app/api?type=waving&color=0:00C4CC,50:00A4EF,100:0078D4&height=120&section=footer" width="100%"/>

</div>
