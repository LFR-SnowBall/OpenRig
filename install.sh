#!/usr/bin/env bash
# ==============================================================================
# ⚡ OpenRig Universal Bootstrapper & Installer
# Single-line installation:
#   curl -fsSL https://raw.githubusercontent.com/LFR-SnowBall/OpenRig/main/install.sh | bash
#
# Author: Luis Fernando Real (LFR-SnowBall) <luisitoreal01@gmail.com>
# License: MIT
# ==============================================================================
set -euo pipefail

# Ensure standard binaries and OrbStack / Homebrew are in PATH
export PATH="${HOME}/.orbstack/bin:/Applications/OrbStack.app/Contents/MacOS/xbin:/opt/homebrew/bin:/usr/local/bin:$PATH"

# Styling & Colors
CYAN="\033[96m"
GREEN="\033[92m"
YELLOW="\033[93m"
RED="\033[91m"
BOLD="\033[1m"
RESET="\033[0m"

# Default Parameters
REPO_URL="https://github.com/LFR-SnowBall/OpenRig.git"
INSTALL_DIR="${HOME}/.openrig"
CLI_TARGET="/usr/local/bin/rig"
FALLBACK_CLI_TARGET="${HOME}/.local/bin/rig"
AUTO_YES=false
START_CONTAINER=true
CHOSEN_ROLE=""
CHOSEN_ENGINE=""

show_banner() {
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
  ___                    ____  _       
 / _ \ _ __   ___ _ __  |  _ \(_) __ _ 
| | | | '_ \ / _ \ '_ \ | |_) | |/ _` |
| |_| | |_) |  __/ | | ||  _ <| | (_| |
 \___/| .__/ \___|_| |_||_| \_\_|\__, |
      |_|                        |___/ 
 Zero-Footprint Modular Dev, Sec & AI Workstation
EOF
    echo -e "${RESET}"
}

show_help() {
    cat << EOF
OpenRig Universal Installer

Usage:
  curl -fsSL https://raw.githubusercontent.com/LFR-SnowBall/OpenRig/main/install.sh | bash
  # Or with local execution:
  ./install.sh [options]

Options:
  -y, --yes              Non-interactive mode (accept all recommended defaults)
  --role <role>          Target profile: fullstack | backend-jvm | frontend-mobile |
                         security-pentest | ai-coding | minimal
  --engine <engine>      Container engine preference: orbstack | docker
  --dir <path>           Custom installation directory (default: ~/.openrig)
  --no-start             Install files and CLI without launching 'rig up'
  -h, --help             Show this help menu
EOF
}

# Parse Command-Line Arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--yes)
            AUTO_YES=true
            shift
            ;;
        --role)
            CHOSEN_ROLE="$2"
            shift 2
            ;;
        --engine)
            CHOSEN_ENGINE="$2"
            shift 2
            ;;
        --dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --no-start)
            START_CONTAINER=false
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${RESET}"
            show_help
            exit 1
            ;;
    esac
done

# Safe interactive prompt reader (supports piped 'curl ... | bash')
ask_prompt() {
    local prompt_msg="$1"
    local default_val="$2"
    local response=""

    if [ "$AUTO_YES" = "true" ]; then
        echo "$default_val"
        return 0
    fi

    if [ -t 0 ]; then
        read -r -p "$prompt_msg" response
    elif [ -e /dev/tty ]; then
        read -r -p "$prompt_msg" response < /dev/tty
    else
        response=""
    fi

    if [ -z "$response" ]; then
        echo "$default_val"
    else
        echo "$response"
    fi
}

main() {
    show_banner

    # 1. System & Architecture Detection
    local os_type
    os_type="$(uname -s)"
    local arch_type
    arch_type="$(uname -m)"

    echo -e "${BOLD}🔍 Detecting Environment:${RESET} OS=${GREEN}${os_type}${RESET}, Arch=${GREEN}${arch_type}${RESET}"

    if [[ "$os_type" != "Darwin" && "$os_type" != "Linux" ]]; then
        echo -e "${RED}❌ Unsupported Operating System: ${os_type}. OpenRig currently supports macOS and Linux (Windows via WSL / install.ps1).${RESET}"
        exit 1
    fi

    # 2. Check & Setup Container Engine (OrbStack vs Docker)
    echo -e "\n${BOLD}🐳 Checking Container Engine (Docker / OrbStack)...${RESET}"
    local engine_ready=false

    if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
        local server_version
        server_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "active")
        echo -e "${GREEN}✔ Active container engine detected:${RESET} Docker ${server_version}"
        engine_ready=true
    else
        if [ "$os_type" = "Darwin" ]; then
            # macOS: Offer OrbStack (Recommended) vs Docker Desktop
            local selected_eng="$CHOSEN_ENGINE"
            if [ -z "$selected_eng" ]; then
                echo -e "\n${YELLOW}No active container engine is currently running.${RESET}"
                echo -e "Choose which container engine you would like to use:"
                echo -e "  ${BOLD}[1] OrbStack${RESET} ${GREEN}(Recommended: 10x lighter, instant boot, 2x faster disk I/O, battery friendly)${RESET}"
                echo -e "  ${BOLD}[2] Docker Desktop${RESET} (Standard)"
                
                local choice
                choice=$(ask_prompt "Enter choice [1-2] (default: 1): " "1")
                case "$choice" in
                    2) selected_eng="docker" ;;
                    *) selected_eng="orbstack" ;;
                esac
            fi

            if [ "$selected_eng" = "orbstack" ]; then
                if [ -d "/Applications/OrbStack.app" ]; then
                    echo -e "${CYAN}⚡ Launching existing OrbStack application...${RESET}"
                    open -a OrbStack || true
                elif command -v brew >/dev/null 2>&1; then
                    echo -e "${CYAN}📦 Installing OrbStack via Homebrew...${RESET}"
                    brew install --cask orbstack
                    open -a OrbStack || true
                else
                    echo -e "${YELLOW}Downloading OrbStack installer...${RESET}"
                    local orb_dmg="/tmp/OrbStack.dmg"
                    curl -fsSL -o "$orb_dmg" "https://cdn-fastly.orbstack.dev/x86_64/OrbStack_v1.10.2_19472_x86_64.dmg" 2>/dev/null || true
                    if [[ "$arch_type" == "arm64" || "$arch_type" == "aarch64" ]]; then
                        curl -fsSL -o "$orb_dmg" "https://cdn-fastly.orbstack.dev/arm64/OrbStack_v1.10.2_19472_arm64.dmg"
                    fi
                    hdiutil attach "$orb_dmg" -nobrowse -quiet
                    cp -R "/Volumes/OrbStack/OrbStack.app" /Applications/
                    hdiutil detach "/Volumes/OrbStack" -quiet
                    rm -f "$orb_dmg"
                    open -a OrbStack
                fi
            else
                if [ -d "/Applications/Docker.app" ]; then
                    echo -e "${CYAN}⚡ Launching Docker Desktop application...${RESET}"
                    open -a Docker || true
                elif command -v brew >/dev/null 2>&1; then
                    echo -e "${CYAN}📦 Installing Docker Desktop via Homebrew...${RESET}"
                    brew install --cask docker
                    open -a Docker || true
                else
                    echo -e "${RED}Please install Docker Desktop from https://docs.docker.com/desktop/setup/install/mac-install/ and run this installer again.${RESET}"
                    exit 1
                fi
            fi

            echo -n "⏳ Waiting for container engine daemon to initialize..."
            local waited=0
            while ! docker info >/dev/null 2>&1; do
                sleep 2
                waited=$((waited + 2))
                echo -n "."
                if [ $waited -ge 60 ]; then
                    echo -e "\n${RED}⚠️ Container engine took too long to start. Please finish opening it and re-run this script.${RESET}"
                    exit 1
                fi
            done
            echo -e " ${GREEN}Ready!${RESET}"
            engine_ready=true

        elif [ "$os_type" = "Linux" ]; then
            echo -e "\n${YELLOW}Docker is not installed or running on this Linux machine.${RESET}"
            local do_install
            do_install=$(ask_prompt "Would you like to install Docker automatically via the official script? [y/N]: " "y")
            if [[ "$do_install" =~ ^[Yy] ]]; then
                echo -e "${CYAN}📦 Running official Docker convenience script...${RESET}"
                curl -fsSL https://get.docker.com | sh
                sudo usermod -aG docker "$USER" 2>/dev/null || true
                sudo systemctl enable --now docker 2>/dev/null || sudo service docker start 2>/dev/null || true
                echo -e "${GREEN}✔ Docker installed! (You may need to log out and log back in for docker group permissions to take effect).${RESET}"
                engine_ready=true
            else
                echo -e "${RED}Please install Docker and Docker Compose v2, then re-run this installer.${RESET}"
                exit 1
            fi
        fi
    fi

    # 3. Clone or Update OpenRig Repository
    echo -e "\n${BOLD}📂 Deploying OpenRig into: ${CYAN}${INSTALL_DIR}${RESET}"
    if [ -d "$INSTALL_DIR/.git" ]; then
        echo -e "${YELLOW}ℹ️ Existing OpenRig installation found. Updating to latest version...${RESET}"
        git -C "$INSTALL_DIR" pull --ff-only || true
    elif [ -d "$INSTALL_DIR" ]; then
        echo -e "${YELLOW}ℹ️ Directory ${INSTALL_DIR} exists. Syncing...${RESET}"
    else
        mkdir -p "$(dirname "$INSTALL_DIR")"
        if command -v git >/dev/null 2>&1; then
            git clone "$REPO_URL" "$INSTALL_DIR"
        else
            echo -e "${CYAN}📥 Downloading OpenRig archive...${RESET}"
            local tar_tmp="/tmp/openrig.tar.gz"
            curl -fsSL -o "$tar_tmp" "https://github.com/LFR-SnowBall/OpenRig/archive/refs/heads/main.tar.gz"
            mkdir -p "$INSTALL_DIR"
            tar -xzf "$tar_tmp" -C "$INSTALL_DIR" --strip-components=1
            rm -f "$tar_tmp"
        fi
    fi

    # 4. Configure Global CLI Link (/usr/local/bin/rig)
    echo -e "\n${BOLD}🔗 Installing global 'rig' CLI executable...${RESET}"
    chmod +x "${INSTALL_DIR}/rig"

    local installed_symlink=false
    if mkdir -p "/usr/local/bin" 2>/dev/null && [ -w "/usr/local/bin" ]; then
        ln -sf "${INSTALL_DIR}/rig" "$CLI_TARGET"
        installed_symlink=true
    elif sudo -n true 2>/dev/null || command -v sudo >/dev/null 2>&1; then
        echo -e "Elevating privileges to link '${INSTALL_DIR}/rig' -> '${CLI_TARGET}'..."
        if sudo mkdir -p "/usr/local/bin" && sudo ln -sf "${INSTALL_DIR}/rig" "$CLI_TARGET"; then
            installed_symlink=true
        fi
    fi

    if [ "$installed_symlink" = "false" ]; then
        mkdir -p "$(dirname "$FALLBACK_CLI_TARGET")"
        ln -sf "${INSTALL_DIR}/rig" "$FALLBACK_CLI_TARGET"
        CLI_TARGET="$FALLBACK_CLI_TARGET"
        echo -e "${YELLOW}Linked to user local binary: ${CLI_TARGET}${RESET}"
        if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
            echo -e "${YELLOW}Notice: Please ensure '~/.local/bin' is in your PATH profile (${HOME}/.zshrc or ${HOME}/.bashrc).${RESET}"
        fi
    else
        echo -e "${GREEN}✔ Global CLI installed at: ${BOLD}${CLI_TARGET}${RESET}"
    fi

    # 5. Role Selection (Workstation Profile)
    if [ -z "$CHOSEN_ROLE" ]; then
        echo -e "\n${BOLD}🎯 Select your Development & Security Profile:${RESET}"
        echo -e "  ${BOLD}[1] Full Stack Developer${RESET} ${GREEN}(Node 22, Python 3.12, Java 21, Docker, AWS, Sec, AI) [Default]${RESET}"
        echo -e "  ${BOLD}[2] Backend JVM${RESET} (Java 21 LTS, Kotlin, Spring Boot, Maven, Gradle, Postgres/Redis)"
        echo -e "  ${BOLD}[3] Frontend & Mobile${RESET} (Node.js, React, Vue.js, Flutter, Android SDK CLI, ADB)"
        echo -e "  ${BOLD}[4] Security & Pentesting${RESET} (Trivy, Semgrep, Nuclei, Nmap, Gitleaks, WireGuard/OpenVPN)"
        echo -e "  ${BOLD}[5] AI Coding Agents${RESET} (Antigravity CLI, Claude Code, Gemini CLI, Codex, Aider)"
        echo -e "  ${BOLD}[6] Minimal Core${RESET} (Ubuntu 24.04 LTS + Oh My Zsh + Docker CLI)"

        local role_choice
        role_choice=$(ask_prompt "Enter profile number [1-6] (default: 1): " "1")
        case "$role_choice" in
            2) CHOSEN_ROLE="backend-jvm" ;;
            3) CHOSEN_ROLE="frontend-mobile" ;;
            4) CHOSEN_ROLE="security-pentest" ;;
            5) CHOSEN_ROLE="ai-coding" ;;
            6) CHOSEN_ROLE="minimal" ;;
            *) CHOSEN_ROLE="fullstack" ;;
        esac
    fi

    echo -e "${CYAN}Selected profile:${RESET} ${BOLD}${CHOSEN_ROLE}${RESET}"

    # Configure .env file
    if [ ! -f "${INSTALL_DIR}/.env" ]; then
        cp "${INSTALL_DIR}/.env.example" "${INSTALL_DIR}/.env" 2>/dev/null || touch "${INSTALL_DIR}/.env"
    fi

    # Update or add OPENRIG_ROLE in .env
    if grep -q "^OPENRIG_ROLE=" "${INSTALL_DIR}/.env"; then
        sed -i.bak -e "s/^OPENRIG_ROLE=.*/OPENRIG_ROLE=${CHOSEN_ROLE}/" "${INSTALL_DIR}/.env" && rm -f "${INSTALL_DIR}/.env.bak"
    else
        echo "OPENRIG_ROLE=${CHOSEN_ROLE}" >> "${INSTALL_DIR}/.env"
    fi

    # 6. Pre-warmed Image Download (0 Local Build Wait Time)
    local prewarmed_img="ghcr.io/lfr-snowball/openrig:${CHOSEN_ROLE}"
    echo -e "\n${BOLD}⚡ Checking pre-warmed image from GitHub Container Registry...${RESET}"
    echo -e "Pulling ${CYAN}${prewarmed_img}${RESET}..."
    if docker pull "$prewarmed_img"; then
        docker tag "$prewarmed_img" "openrig:${CHOSEN_ROLE}"
        echo -e "${GREEN}✔ Instant setup ready! Downloaded pre-compiled multi-arch image.${RESET}"
    else
        echo -e "${YELLOW}Notice: Pre-warmed image not available yet for '${CHOSEN_ROLE}'. OpenRig will build it locally on first launch.${RESET}"
    fi

    # 7. Start OpenRig Workstation
    if [ "$START_CONTAINER" = "true" ]; then
        echo -e "\n${BOLD}🚀 Starting OpenRig Workstation...${RESET}"
        "${INSTALL_DIR}/rig" up
    else
        echo -e "\n${GREEN}✔ Installation complete!${RESET}"
        echo -e "Launch your workstation whenever you are ready with: ${BOLD}rig up${RESET}"
    fi

    echo -e "\n${CYAN}══════════════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}🎉 OpenRig is fully installed and ready!${RESET}"
    echo -e "  👉 Open Terminal:      ${BOLD}rig shell${RESET}"
    echo -e "  👉 Open GUI IDE:       ${BOLD}rig ide .${RESET} (or run '${BOLD}code .${RESET}' / '${BOLD}antigravity .${RESET}' inside rig)"
    echo -e "  👉 Terminal AI Agents: Run '${BOLD}agy${RESET}', '${BOLD}claude${RESET}' or '${BOLD}gemini${RESET}' inside rig"
    echo -e "  👉 Multi-Cloud Profile:${BOLD}rig profile create work \"Alice\" \"alice@example.com\"${RESET}"
    echo -e "  👉 Stop Workstation:   ${BOLD}rig down${RESET} (reclaims 100% of RAM/CPU)"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════════${RESET}\n"
}

main "$@"
