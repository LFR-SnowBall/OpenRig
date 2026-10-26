#!/usr/bin/env bash
# ==============================================================================
# OpenRig Module: Node.js & Frontend (nvm + Node LTS + Vue.js + React + Vite + pnpm + Yarn + Bun)
# ==============================================================================
set -euo pipefail

NODE_DEFAULT_VERSION="${1:-22}"
echo "🎨 [OpenRig] Installing Node & Frontend Module via nvm (Node ${NODE_DEFAULT_VERSION}, Vue, React, Vite)..."

su - rig -c "
    set -eo pipefail
    export NVM_DIR=\"\$HOME/.nvm\"
    mkdir -p \"\$NVM_DIR\"
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
    source \"\$NVM_DIR/nvm.sh\"

    nvm install ${NODE_DEFAULT_VERSION}
    nvm alias default ${NODE_DEFAULT_VERSION}
    nvm use default

    # Package managers & Frontend toolchains (Vue.js, React, Vite, TypeScript)
    npm install -g \
        pnpm \
        yarn \
        typescript \
        ts-node \
        vite \
        @vue/cli \
        create-vue \
        create-vite \
        eslint \
        prettier \
        firebase-tools

    # Install Bun runtime
    curl -fsSL https://bun.sh/install | bash || true
"

echo "✅ [OpenRig] Node & Frontend module installed."
