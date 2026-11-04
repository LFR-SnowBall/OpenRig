# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.1.0] - 2026-11-03

### Added
- **Military-Grade Encrypted Backup (`rig backup create / restore`):**
  - Encrypts entire workstation state (source code, git branches, uncommitted work, `.env`, and client profiles) using **AES-256-CBC with PBKDF2** (100,000 iterations).
  - Produces portable, password-protected `.rigpack` packages.
  - Automatically excludes bulky transient build caches (`node_modules`, `target`, `.gradle`, `.cache`, `venv`, `__pycache__`) while preserving complete Git metadata.
  - Verifies cryptographic integrity on restore; rejects incorrect passwords or tampered archives.
- **Live Encrypted Workstation Migration (`rig migrate push`):**
  - Streams encrypted workspace deltas directly over LAN/SSH into another machine or an `OpenRig-Server`.
  - Enables seamless workstation migration (e.g., from a low-RAM laptop to a high-RAM desktop server) with zero manual file packaging or archive extraction.
- **One-Line Interactive Bootstrappers:**
  - Added `install.sh` for macOS & Linux (`curl -fsSL ... | bash`).
  - Added `install.ps1` for Windows PowerShell (`irm ... | iex`).
  - Interactive container engine wizard (OrbStack vs. Docker Desktop auto-detection and installation).
- **Native Antigravity CLI (`agy`) Support:**
  - Installed native Linux ARM64/AMD64 `agy` binary inside the container (`/usr/local/bin/agy -> /home/rig/.local/bin/agy`).
  - Resolved symlink collision with GUI IDE launcher (`rig ide .` / `code .` now opens the host GUI IDE, while `agy` opens the interactive terminal agent).
  - Added persistent named volume `openrig-gemini-config` for credentials and settings.
- **Dual-Engine AI Switcher & Opt-In Split-Brain DLP:**
  - Added `rig ai [status|use corporate|personal]` to switch between shared corporate broker and ephemeral RAM vault.
  - Added `rig brain [init|link|status|learn]` with DLP scanning and redaction.
- **In-Container Unified CLI (`/usr/local/bin/rig`):**
  - Context-aware command dispatching with live cgroup v2 RAM and CPU quota reporting.

### Changed
- Standardized all repository branding, documentation, and author attribution to open-source personal author: `Luis Fernando Real (LFR-SnowBall) <luisitoreal01@gmail.com>`.
- Replaced sample client profile domains with generic RFC 2606 placeholders (`alice@example.com`).

---

## [1.0.0] - 2026-10-23

### Added
- Initial public release of **OpenRig Workstation**.
- Red-Team hardened container environment (ports bound exclusively to `127.0.0.1`, zero private key mounts, 1Password SSH Agent bridge).
- Modular stacks for Python (uv/pyenv), JVM (SDKMAN Java 21/Kotlin), Node.js (Node 22/pnpm/Vite), Mobile (Flutter/Android CLI/ADB), Cloud (AWS CLI v2/kubectl), and Security (Trivy, Semgrep, Nuclei, Nmap, Gitleaks).
- Time Machine snapshots (`rig snapshot save/restore/list/export/import`).
- Isolated multi-VPN manager (`rig vpn` supporting GlobalProtect + HIP, OpenVPN, WireGuard, AnyConnect).
- Multi-client identity profiles (`rig profile create/use/list`).
- Public HTTPS instant tunnels (`rig share`).
- Anti-malware sandbox switch (`rig lock` / `rig unlock`).
- Zero-popup localhost Remote-SSH bridge (`Host openrig` on `127.0.0.1:2222`) for Antigravity IDE, VS Code, and Cursor.
