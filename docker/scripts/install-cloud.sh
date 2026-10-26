#!/usr/bin/env bash
# ==============================================================================
# OpenRig Module: Cloud & DevOps (AWS CLI v2 SSO-ready + Terraform + kubectl + DB clients)
# ==============================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
echo "☁️ [OpenRig] Installing Cloud & DevOps Module (AWS CLI v2, Postgres/Redis clients, GitHub CLI)..."

apt-get update && apt-get install -y --no-install-recommends \
    postgresql-client \
    redis-tools \
    sqlite3 \
    gh
apt-get clean && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2 (Multi-arch: aarch64 for Apple Silicon M1/M2/M3, x86_64 for Intel/AMD)
ARCH=$(uname -m)
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-${ARCH}.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp
/tmp/aws/install --update
rm -rf /tmp/aws /tmp/awscliv2.zip

# Install kubectl (Multi-arch)
KUBE_ARCH=$(dpkg --print-architecture)
KUBE_VER=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -fsSL "https://dl.k8s.io/release/${KUBE_VER}/bin/linux/${KUBE_ARCH}/kubectl" -o /usr/local/bin/kubectl
chmod +x /usr/local/bin/kubectl

# Install cloudflared (for 'rig share <port>' instant HTTPS tunnels)
curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${KUBE_ARCH}" -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared

echo "✅ [OpenRig] Cloud & DevOps module installed."
