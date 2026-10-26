# 🤝 Contributing to OpenRig

Thank you for your interest in contributing to **OpenRig** by **Linux Open Source S.A. de C.V.**!

## 🧩 Adding a New Modular Stack
All modular installation scripts live under `docker/scripts/`:
- `docker/scripts/install-base.sh` — Ubuntu 24.04 LTS base packages, shells (`Oh My Zsh`, `Starship`, `Fish`), VPN clients, and `tmux`.
- `docker/scripts/install-python.sh` — `pyenv`, `uv`, FastAPI, Poetry, Ruff, Pytest.
- `docker/scripts/install-jvm.sh` — `SDKMAN!`, Java 21/17, Kotlin, Maven, Gradle, Spring Boot CLI.
- `docker/scripts/install-node.sh` — `NVM`, Node.js 22 LTS, TypeScript, `pnpm`, `yarn`.
- `docker/scripts/install-mobile.sh` — Flutter SDK, Dart, Android SDK Command-Line Tools (`adb`).
- `docker/scripts/install-swift.sh` — Swift Linux Toolchain (`amd64` & `arm64`).
- `docker/scripts/install-cloud.sh` — AWS CLI v2, Google Cloud SDK, Firebase CLI, Terraform, `kubectl`, Helm.
- `docker/scripts/install-sec.sh` — Nmap, Nuclei, Subfinder, httpx, Trivy, Semgrep, Gitleaks, WireGuard, OpenVPN, OpenConnect.
- `docker/scripts/install-ai.sh` — Claude Code CLI, Gemini CLI, OpenAI Codex CLI.

## 🧪 Pre-Submission Checklist
1. Ensure all scripts support both **`linux/amd64`** and **`linux/arm64` (Apple Silicon)** using `dpkg --print-architecture`.
2. Run `./rig sec .` inside OpenRig to verify **0 secrets (`gitleaks`)** and **0 critical vulnerabilities (`trivy` / `semgrep`)**.
3. Sign your commits (`git commit -S -m "feat: ..."`).
