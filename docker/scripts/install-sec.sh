#!/usr/bin/env bash
# ==============================================================================
# OpenRig Module: Security, AppSec & Pentesting (Exegol-style lightweight suite)
# Includes: nmap, sqlmap, gobuster, ffuf, nuclei, httpx, subfinder, trivy, gitleaks, semgrep, mitmproxy
# ==============================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
echo "🛡️ [OpenRig] Installing Security, AppSec & Pentesting Module..."

apt-get update && apt-get install -y --no-install-recommends \
    nmap \
    sqlmap \
    gobuster \
    tcpdump \
    net-tools \
    openssl \
    libpcap-dev \
    openvpn \
    wireguard-tools \
    openconnect \
    openfortivpn \
    proxychains4 \
    openssh-server \
    oathtool \
    qrencode
apt-get clean && rm -rf /var/lib/apt/lists/*
mkdir -p /run/sshd
# Allow passing OPENRIG_HW_ID over SSH for hardware-bound key verification
if ! grep -q "AcceptEnv OPENRIG_HW_ID" /etc/ssh/sshd_config 2>/dev/null; then
    echo "AcceptEnv OPENRIG_HW_ID OPENRIG_DEVICE_NAME" >> /etc/ssh/sshd_config
    echo "PasswordAuthentication no" >> /etc/ssh/sshd_config
fi

ARCH_DEB=$(dpkg --print-architecture) # amd64 or arm64
ARCH_UNAME=$(uname -m)                # x86_64 or aarch64

# 1. Install Trivy (Vulnerability & Container/Repo Scanner)
TRIVY_ARCH=$([ "$ARCH_DEB" = "arm64" ] && echo "ARM64" || echo "64bit")
TRIVY_VER=$(curl -s https://api.github.com/repos/aquasecurity/trivy/releases/latest | jq -r '.tag_name' | sed 's/^v//')
if [ -n "$TRIVY_VER" ] && [ "$TRIVY_VER" != "null" ]; then
    curl -fsSL "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VER}/trivy_${TRIVY_VER}_Linux-${TRIVY_ARCH}.tar.gz" -o /tmp/trivy.tar.gz
    tar -xzf /tmp/trivy.tar.gz -C /usr/local/bin trivy
    rm -f /tmp/trivy.tar.gz
fi

# 2. Install Gitleaks (Git Secret Scanner)
GITLEAKS_ARCH=$([ "$ARCH_DEB" = "arm64" ] && echo "arm64" || echo "x64")
GITLEAKS_VER=$(curl -s https://api.github.com/repos/gitleaks/gitleaks/releases/latest | jq -r '.tag_name' | sed 's/^v//')
if [ -n "$GITLEAKS_VER" ] && [ "$GITLEAKS_VER" != "null" ]; then
    curl -fsSL "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VER}/gitleaks_${GITLEAKS_VER}_linux_${GITLEAKS_ARCH}.tar.gz" -o /tmp/gitleaks.tar.gz
    tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks
    rm -f /tmp/gitleaks.tar.gz
fi

# 3. Install ProjectDiscovery Suite (nuclei, httpx, subfinder) & ffuf
for tool_repo in "projectdiscovery/nuclei" "projectdiscovery/httpx" "projectdiscovery/subfinder"; do
    TOOL_NAME=$(basename "$tool_repo")
    VER=$(curl -s "https://api.github.com/repos/${tool_repo}/releases/latest" | jq -r '.tag_name' | sed 's/^v//')
    if [ -n "$VER" ] && [ "$VER" != "null" ]; then
        curl -fsSL "https://github.com/${tool_repo}/releases/download/v${VER}/${TOOL_NAME}_${VER}_linux_${ARCH_DEB}.zip" -o "/tmp/${TOOL_NAME}.zip" || true
        if [ -f "/tmp/${TOOL_NAME}.zip" ]; then
            unzip -q -o "/tmp/${TOOL_NAME}.zip" "$TOOL_NAME" -d /usr/local/bin/ || true
            chmod +x "/usr/local/bin/${TOOL_NAME}" || true
            rm -f "/tmp/${TOOL_NAME}.zip"
        fi
    fi
done

# 4. Install Semgrep (SAST) & Mitmproxy via uv if available
su - rig -c '
    export PATH="$HOME/.local/bin:$PATH"
    if command -v uv >/dev/null 2>&1; then
        uv tool install semgrep || true
        uv tool install mitmproxy || true
    fi
'

echo "✅ [OpenRig] Security & Pentesting module installed."
