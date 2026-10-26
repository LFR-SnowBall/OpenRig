#!/usr/bin/env bash
# ==============================================================================
# OpenRig Module: Swift (Official Swift Linux Toolchain via swiftly)
# ==============================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
echo "🍎 [OpenRig] Installing Swift Linux Toolchain..."

apt-get update && apt-get install -y --no-install-recommends \
    binutils \
    gnupg2 \
    libc6-dev \
    libcurl4-openssl-dev \
    libedit2 \
    libgcc-13-dev \
    libpython3-dev \
    libsqlite3-0 \
    libstdc++-13-dev \
    libxml2-dev \
    libz3-dev \
    pkg-config \
    tzdata \
    zlib1g-dev
apt-get clean && rm -rf /var/lib/apt/lists/*

su - rig -c '
    set -euo pipefail
    ARCH=$(uname -m)
    curl -fsSL "https://download.swift.org/swiftly/linux/swiftly-${ARCH}.tar.gz" -o /tmp/swiftly.tar.gz
    mkdir -p "$HOME/.local/bin"
    tar -xzf /tmp/swiftly.tar.gz -C "$HOME/.local/bin"
    rm -f /tmp/swiftly.tar.gz
    "$HOME/.local/bin/swiftly" init --quiet-shell-followup -y || true
'

echo "✅ [OpenRig] Swift module installed."
