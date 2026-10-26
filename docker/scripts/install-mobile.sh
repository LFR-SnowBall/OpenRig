#!/usr/bin/env bash
# ==============================================================================
# OpenRig Module: Mobile (Flutter + Dart + FVM + Android SDK CLI + ADB Wireless/Bridge)
# ==============================================================================
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive
echo "📱 [OpenRig] Installing Mobile Module (Flutter + Android SDK CLI + ADB)..."

apt-get update && apt-get install -y --no-install-recommends \
    android-tools-adb \
    clang \
    cmake \
    ninja-build \
    pkg-config \
    libgtk-3-dev \
    liblzma-dev \
    libstdc++-12-dev
apt-get clean && rm -rf /var/lib/apt/lists/*

su - rig -c '
    set -euo pipefail
    # 1. Install Flutter SDK (stable branch, works on both x86_64 and arm64 Linux)
    if [ ! -d "$HOME/flutter" ]; then
        git clone --depth 1 -b stable https://github.com/flutter/flutter.git "$HOME/flutter"
    fi
    export PATH="$HOME/flutter/bin:$HOME/flutter/bin/cache/dart-sdk/bin:$PATH"
    flutter config --no-analytics
    flutter config --enable-web

    # 2. Install FVM (Flutter Version Manager)
    dart pub global activate fvm || true

    # 3. Install Android Command-Line Tools if Java is available
    ANDROID_HOME="$HOME/Android/Sdk"
    mkdir -p "$ANDROID_HOME/cmdline-tools"
    if [ ! -d "$ANDROID_HOME/cmdline-tools/latest" ]; then
        curl -fsSL https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -o /tmp/cmdtools.zip
        unzip -q /tmp/cmdtools.zip -d "$ANDROID_HOME/cmdline-tools"
        mv "$ANDROID_HOME/cmdline-tools/cmdline-tools" "$ANDROID_HOME/cmdline-tools/latest"
        rm -f /tmp/cmdtools.zip
    fi
'

echo "✅ [OpenRig] Mobile module installed."
