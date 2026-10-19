# ══════════════════════════════════════════════════════════════════
#  Ultimate WindowsVM — unified QEMU/KVM container
#  Windows 10 & 11 • noVNC (browser) + RDP access • auto-detect KVM
#  All runtime behaviour is configured via environment variables
#  (see README.md or run install.sh)
# ══════════════════════════════════════════════════════════════════

FROM ubuntu:22.04

ARG DEBIAN_FRONTEND=noninteractive

LABEL org.opencontainers.image.title="Ultimate WindowsVM" \
      org.opencontainers.image.description="Windows 10/11 VM in Docker — auto-detect, noVNC + RDP, ISO or pre-built disk" \
      org.opencontainers.image.licenses="DragonLabs MIT+"

# QEMU + noVNC stack, plus OVMF (UEFI) and swtpm (TPM 2.0) so that
# stock Windows 11 ISOs install without "This PC can't run Windows 11".
RUN apt-get update && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        wget \
        netcat-openbsd \
        procps \
        net-tools \
        iproute2 \
        unzip \
        qemu-system-x86 \
        qemu-utils \
        novnc \
        websockify \
        ovmf \
        swtpm \
        swtpm-tools \
    && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Defaults — install.sh overrides these at `docker run` time
ENV OS_VERSION=win10 \
    MODE=iso \
    ACCESS=both \
    CORES=4 \
    RAM=4G \
    DISK=64G \
    NOVNC_PORT=6080 \
    ENABLE_TPM=auto

VOLUME ["/data", "/iso"]

EXPOSE 6080 3389 5900

# Healthy while QEMU runs OR an ISO is still downloading
HEALTHCHECK --interval=60s --timeout=10s --start-period=120s --retries=3 \
    CMD pgrep -f qemu-system-x86_64 >/dev/null || pgrep -f "wget" >/dev/null || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
