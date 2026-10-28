#!/usr/bin/env bash
# ==============================================================================
# OpenRig Module: AI Coding CLIs (Antigravity CLI, Claude Code, Gemini CLI, Codex, Aider)
# Runs inside the OpenRig sandbox with full access to container compilers
# ==============================================================================
set -euo pipefail

echo "🤖 [OpenRig] Installing AI Coding Assistants Module (Antigravity CLI, Claude Code, Gemini CLI, Codex, Aider)..."

su - rig -c '
    set -euo pipefail
    export NVM_DIR="$HOME/.nvm"
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        source "$NVM_DIR/nvm.sh"
        npm install -g \
            @anthropic-ai/claude-code \
            @google/gemini-cli \
            @openai/codex || true
    fi

    export PATH="$HOME/.local/bin:$PATH"
    if command -v uv >/dev/null 2>&1; then
        uv tool install aider-chat || true
    fi

    # Install Antigravity CLI (agy) native Linux binary
    curl -fsSL https://antigravity.google/cli/install.sh | bash -s -- --dir "$HOME/.local/bin" || true
'

if [ -x /home/rig/.local/bin/agy ]; then
    ln -sf /home/rig/.local/bin/agy /usr/local/bin/agy
fi

echo "✅ [OpenRig] AI Coding Assistants module installed."
