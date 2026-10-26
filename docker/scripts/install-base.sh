#!/usr/bin/env bash
# ==============================================================================
# OpenRig Module: Base System (Ubuntu 24.04 + Zsh + Oh My Zsh + Docker CLI + Core Tools)
# ==============================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

echo "🧱 [OpenRig] Installing Base Workstation packages..."
apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    wget \
    git \
    gnupg \
    lsb-release \
    sudo \
    zsh \
    fish \
    tmux \
    neovim \
    jq \
    ripgrep \
    fd-find \
    fzf \
    bat \
    htop \
    unzip \
    zip \
    tar \
    xz-utils \
    openssh-client \
    socat \
    iproute2 \
    iputils-ping \
    netcat-openbsd \
    dnsutils \
    whois \
    build-essential \
    pkg-config \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncursesw5-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libffi-dev \
    liblzma-dev \
    locales

locale-gen en_US.UTF-8
update-locale LANG=en_US.UTF-8

# Install Official Docker CLI & Docker Compose plugin (for Sibling Containers via /var/run/docker.sock)
echo "🐳 [OpenRig] Installing Docker CLI & Compose plugin (Sibling Container support)..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update && apt-get install -y --no-install-recommends \
    docker-ce-cli \
    docker-buildx-plugin \
    docker-compose-plugin

# Create non-root developer user 'rig' (or reuse UID 1000)
if ! id -u rig >/dev/null 2>&1; then
    if getent passwd 1000 >/dev/null 2>&1; then
        EXISTING_USER=$(getent passwd 1000 | cut -d: -f1)
        usermod -l rig -d /home/rig -m "$EXISTING_USER" || true
        groupmod -n rig "$EXISTING_USER" || true
    else
        useradd -m -s /bin/zsh -u 1000 rig
    fi
fi
usermod -aG sudo rig
echo "rig ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/rig
chmod 0440 /etc/sudoers.d/rig

# Install Oh My Zsh + useful plugins (zsh-autosuggestions, zsh-syntax-highlighting) for user 'rig'
su - rig -c '
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
        git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions || true
        git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting || true
        sed -i "s/plugins=(git)/plugins=(git docker docker-compose zsh-autosuggestions zsh-syntax-highlighting)/" "$HOME/.zshrc" || true
    fi
'

# Install Starship prompt (for users who choose starship/bash/fish)
curl -sS https://starship.rs/install.sh | sh -s -- -y >/dev/null 2>&1 || true

# Clean up apt cache
apt-get clean && rm -rf /var/lib/apt/lists/*
echo "✅ [OpenRig] Base system ready."
