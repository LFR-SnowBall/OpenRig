#!/usr/bin/env bash
# ==============================================================================
# OpenRig Module: Python (pyenv + uv + multi-version + Django, Flask, FastAPI, Debugpy)
# ==============================================================================
set -euo pipefail

PYTHON_DEFAULT_VERSION="${1:-3.12}"
echo "🐍 [OpenRig] Installing Python Module (uv + pyenv + Python ${PYTHON_DEFAULT_VERSION})..."

su - rig -c "
    set -euo pipefail
    # 1. Install Astral uv (ultra-fast Python & package manager)
    curl -LsSf https://astral.sh/uv/install.sh | sh
    export PATH=\"\$HOME/.local/bin:\$PATH\"

    # 2. Install pyenv for classic version management compatibility
    if [ ! -d \"\$HOME/.pyenv\" ]; then
        curl -fsSL https://pyenv.run | bash
    fi

    # 3. Install default Python version via uv and create global tools
    uv python install ${PYTHON_DEFAULT_VERSION}
    uv tool install poetry
    uv tool install ruff
    uv tool install pytest
    uv tool install httpie
    uv tool install django --with djangorestframework
    uv tool install flask
    uv tool install "fastapi[standard]"
"

echo "✅ [OpenRig] Python module installed."
