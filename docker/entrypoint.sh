#!/usr/bin/env bash
# ==============================================================================
# OpenRig Smart Entrypoint
# - Configures Docker socket permissions for Sibling Containers (DooD)
# - Bridges SSH & Git config (agnostic: 1Password Agent OR standard ~/.ssh keys)
# - Sets up Browser Helper for AWS SSO / Firebase / OAuth CLI logins
# - Initializes Zsh environment for SDKMAN, NVM, Pyenv/uv, Flutter, and Security tools
# ==============================================================================
set -e

RIG_HOME="/home/rig"

# 1. Sibling Containers Support & Named Volume Permissions
if [ -S /var/run/docker.sock ]; then
    sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
fi

# Ensure Docker named volumes mounted inside /home/rig belong to user 'rig'
sudo chown -R rig:rig \
    "${RIG_HOME}/.m2" \
    "${RIG_HOME}/.gradle" \
    "${RIG_HOME}/.cache" \
    "${RIG_HOME}/.npm" \
    "${RIG_HOME}/.local" \
    "${RIG_HOME}/.pub-cache" \
    "${RIG_HOME}/.aws" \
    "${RIG_HOME}/.config" \
    "${RIG_HOME}/.openrig-profiles" 2>/dev/null || true

# 1b. Remote Server Mode: Start OpenSSH Server if OPENRIG_SSH_SERVER=true
if [ "${OPENRIG_SSH_SERVER:-false}" = "true" ]; then
    sudo mkdir -p /run/sshd /etc/openrig
    sudo touch /etc/openrig/authorized_keys
    sudo chown root:root /etc/openrig/authorized_keys
    sudo chmod 644 /etc/openrig/authorized_keys

    if ! grep -q "AuthorizedKeysFile /etc/openrig/authorized_keys" /etc/ssh/sshd_config 2>/dev/null; then
        echo "AcceptEnv OPENRIG_HW_ID OPENRIG_DEVICE_NAME" | sudo tee -a /etc/ssh/sshd_config >/dev/null
        echo "PasswordAuthentication no" | sudo tee -a /etc/ssh/sshd_config >/dev/null
        echo "AuthorizedKeysFile /etc/openrig/authorized_keys" | sudo tee -a /etc/ssh/sshd_config >/dev/null
    fi
    mkdir -p "${RIG_HOME}/.ssh" "${RIG_HOME}/.openrig-profiles"
    chmod 700 "${RIG_HOME}/.ssh"

    # Generate TOTP Keychain Secret for Guest Mode if not present
    if [ ! -f "${RIG_HOME}/.openrig-profiles/keychain.secret" ]; then
        head -c 10 /dev/urandom | base32 | tr -d '=' > "${RIG_HOME}/.openrig-profiles/keychain.secret"
        chmod 600 "${RIG_HOME}/.openrig-profiles/keychain.secret"
    fi

    if [ -n "${AUTHORIZED_SSH_KEY:-}" ]; then
        echo "${AUTHORIZED_SSH_KEY}" | sudo tee -a /etc/openrig/authorized_keys >/dev/null
        sudo sort -u /etc/openrig/authorized_keys -o /etc/openrig/authorized_keys
        sudo chmod 644 /etc/openrig/authorized_keys
    fi
    sudo /usr/sbin/sshd
fi

# 2. Hardened Agnostic SSH Setup (Zero Private Key Exposure when SSH Agent / 1Password is active)
mkdir -p "${RIG_HOME}/.ssh"
chmod 700 "${RIG_HOME}/.ssh"

if [ -d /tmp/host-ssh ]; then
    # Always copy safe public files & configs (*.pub, config, known_hosts, allowed_signers)
    for safe_item in /tmp/host-ssh/*.pub /tmp/host-ssh/config /tmp/host-ssh/known_hosts /tmp/host-ssh/allowed_signers; do
        [ -e "$safe_item" ] && cp -rn "$safe_item" "${RIG_HOME}/.ssh/" 2>/dev/null || true
    done
    # Only copy private keys if no Host SSH Agent (1Password / ssh-agent) socket is mounted AND explicitly allowed
    if [ ! -S /ssh-agent ] && [ "${OPENRIG_ALLOW_DISK_KEYS:-false}" = "true" ]; then
        cp -rn /tmp/host-ssh/id_* "${RIG_HOME}/.ssh/" 2>/dev/null || true
    fi
    # Strip host-specific IdentityAgent paths (e.g. macOS /Users/.../1password/agent.sock) from container ssh config
    if [ -f "${RIG_HOME}/.ssh/config" ]; then
        sed -i '/IdentityAgent/d' "${RIG_HOME}/.ssh/config" 2>/dev/null || true
        sed -i '/Include ~\/.ssh\/1Password\/config/d' "${RIG_HOME}/.ssh/config" 2>/dev/null || true
    fi
    chmod 600 "${RIG_HOME}/.ssh/"* 2>/dev/null || true
    # Seal /tmp/host-ssh with an unreadable root-only tmpfs so npm/pip postinstall malware can never read host ~/.ssh
    sudo mount -t tmpfs -o size=4k,mode=000 tmpfs /tmp/host-ssh 2>/dev/null || true
fi

# 3. Git Configuration (Copy from host mount /tmp/host-gitconfig so commits work cleanly)
if [ -f /tmp/host-gitconfig ] && [ ! -f "${RIG_HOME}/.gitconfig" ]; then
    cp /tmp/host-gitconfig "${RIG_HOME}/.gitconfig"
    # If host uses macOS op-ssh-sign binary path, disable gpgsign inside Linux container unless agent signing is configured
    if grep -q "/Applications/1Password.app" "${RIG_HOME}/.gitconfig" 2>/dev/null; then
        git config --global --unset gpg.ssh.program || true
        git config --global commit.gpgsign false || true
    fi
fi

# 4. Install Browser Bridge for OAuth / AWS SSO / Firebase Login inside Container
sudo tee /usr/local/bin/rig-browser >/dev/null << 'EOF'
#!/usr/bin/env bash
echo ""
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║ 🌐 [OpenRig Browser Bridge] Authentication required in your Host Browser:  ║"
echo "╠════════════════════════════════════════════════════════════════════════════╣"
echo "║ Cmd+Click (Mac) or Ctrl+Click (Windows/Linux) on the following URL:        ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo "👉 $1"
echo ""
EOF
sudo chmod +x /usr/local/bin/rig-browser

# 4b. Install Host IDE Bridge inside Container (code / agy / antigravity / cursor)
# Allows running 'code .' or 'agy .' inside 'rig shell' to open a new Host IDE window attached to that exact folder inside OpenRig!
sudo tee /usr/local/bin/rig-open-ide >/dev/null << 'EOF'
#!/usr/bin/env bash
set -e
TARGET_ARG="${1:-.}"
TARGET_PATH=$(realpath "$TARGET_ARG" 2>/dev/null || pwd)

# 1. If running inside an active Antigravity / VS Code Remote-SSH terminal, use its native IPC hook if available
if [ -n "${VSCODE_IPC_HOOK_CLI:-}" ]; then
    REMOTE_CLI=$(find "$HOME/.antigravity-server" "$HOME/.vscode-server" -path "*/remote-cli/*" -type f -executable 2>/dev/null | head -n 1 || true)
    if [ -n "$REMOTE_CLI" ]; then
        "$REMOTE_CLI" --new-window "$TARGET_PATH" && exit 0
    fi
fi

# 2. Trigger the Host OS IDE Watcher via /workspace/.openrig-ide-trigger
echo "$TARGET_PATH" > /workspace/.openrig-ide-trigger
echo "🚀 [OpenRig IDE Bridge] Opening new Antigravity IDE / VS Code window attached to 'openrig:${TARGET_PATH}'..."
EOF
sudo chmod +x /usr/local/bin/rig-open-ide
for ide_cmd in code agy antigravity cursor; do
    sudo ln -sf /usr/local/bin/rig-open-ide "/usr/local/bin/${ide_cmd}"
done

# 5. Install Mobile ADB Helper (Wireless & USB Host Bridge)
sudo tee /usr/local/bin/rig-phone >/dev/null << 'EOF'
#!/usr/bin/env bash
set -e
ACTION="${1:-help}"
case "$ACTION" in
    pair)
        echo "📱 Pairing with Android phone via Wireless Debugging..."
        adb pair "${2:?Usage: rig-phone pair IP:PORT}"
        ;;
    connect)
        echo "📱 Connecting to Android phone over Wi-Fi..."
        adb connect "${2:?Usage: rig-phone connect IP:PORT}"
        adb devices -l
        ;;
    usb-bridge)
        echo "🔌 Connecting to Host USB ADB Server (host.docker.internal:5037)..."
        export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037
        adb devices -l
        ;;
    *)
        echo "📱 OpenRig Mobile Helper (rig-phone):"
        echo "  rig-phone pair <IP:PORT>     -> Pair Android phone via Wireless Debugging (Android 11+)"
        echo "  rig-phone connect <IP:PORT>  -> Connect Android phone over Wi-Fi for 'flutter run' / debug"
        echo "  rig-phone usb-bridge         -> Bridge to a USB phone connected to your Host OS"
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/rig-phone

# 6. Install Security Quick-Scanner Helper (rig-sec)
sudo tee /usr/local/bin/rig-sec >/dev/null << 'EOF'
#!/usr/bin/env bash
set -e
TARGET="${1:-.}"
echo "🛡️ [OpenRig Security Suite] Scanning target: $TARGET"
echo "--------------------------------------------------------"
if command -v gitleaks >/dev/null 2>&1; then
    echo "🔍 [1/3] Gitleaks (Exposed secrets detection)..."
    gitleaks detect --source "$TARGET" --no-git || true
fi
if command -v trivy >/dev/null 2>&1; then
    echo "🔍 [2/3] Trivy (SCA vulnerabilities / CVEs & IaC misconfigs)..."
    trivy fs --scanners vuln,misconfig "$TARGET" || true
fi
if command -v semgrep >/dev/null 2>&1; then
    echo "🔍 [3/3] Semgrep (Static Application Security Testing - SAST)..."
    semgrep scan --config=auto "$TARGET" || true
fi
echo "✅ Security audit completed."
EOF
sudo chmod +x /usr/local/bin/rig-sec

# 6b. Install Multi-VPN Helper (GlobalProtect + HIP Report, OpenVPN, WireGuard, AnyConnect, Fortinet)
sudo tee /usr/local/bin/rig-vpn >/dev/null << 'EOF'
#!/usr/bin/env bash
set -e
ACTION="${1:-help}"
shift || true

HIP_SCRIPT="/usr/libexec/openconnect/hipreport.sh"
[ ! -f "$HIP_SCRIPT" ] && HIP_SCRIPT="/usr/share/vpnc-scripts/hipreport.sh"

case "$ACTION" in
    gp|globalprotect)
        PORTAL="${1:?Usage: rig vpn gp <portal.company.com>}"
        shift || true
        echo "🛡️ [OpenRig VPN] Connecting to Palo Alto GlobalProtect ($PORTAL)..."
        if [ -f "$HIP_SCRIPT" ]; then
            sudo openconnect --protocol=gp --csd-wrapper="$HIP_SCRIPT" --background "$PORTAL" "$@"
        else
            sudo openconnect --protocol=gp --background "$PORTAL" "$@"
        fi
        echo "✅ GlobalProtect tunnel active inside OpenRig (your Host OS network remains untouched)."
        ;;
    ovpn|openvpn)
        OVPN_FILE="${1:?Usage: rig vpn ovpn <profile.ovpn>}"
        echo "🛡️ [OpenRig VPN] Connecting OpenVPN with $OVPN_FILE..."
        sudo openvpn --config "$OVPN_FILE" --daemon
        sleep 2
        ip -brief addr show | grep -E "tun|tap" || true
        ;;
    wg|wireguard)
        WG_CONF="${1:?Usage: rig vpn wg <profile.conf>}"
        echo "🛡️ [OpenRig VPN] Bringing up WireGuard tunnel ($WG_CONF)..."
        sudo wg-quick up "$WG_CONF"
        ;;
    anyconnect|cisco)
        SERVER="${1:?Usage: rig vpn anyconnect <vpn.company.com>}"
        shift || true
        echo "🛡️ [OpenRig VPN] Connecting to Cisco AnyConnect ($SERVER)..."
        sudo openconnect --protocol=anyconnect --background "$SERVER" "$@"
        ;;
    fortinet|forti)
        SERVER="${1:?Usage: rig vpn fortinet <vpn.company.com:port>}"
        shift || true
        echo "🛡️ [OpenRig VPN] Connecting to Fortinet SSL VPN ($SERVER)..."
        sudo openfortivpn "$SERVER" "$@" &
        ;;
    status)
        echo "🔒 [OpenRig VPN Status] Active tunnel interfaces inside OpenRig:"
        ip -brief addr show | grep -E "tun|tap|wg|ppp" || echo "  (No active VPN tunnels at the moment)"
        ;;
    down|stop)
        echo "🛑 Closing VPN tunnels inside OpenRig..."
        sudo killall openconnect openvpn openfortivpn 2>/dev/null || true
        echo "✅ VPN disconnected."
        ;;
    *)
        echo "🔒 OpenRig Multi-VPN Manager (Isolated from Host OS):"
        echo "  rig vpn gp <portal.com>        -> Palo Alto GlobalProtect (with HIP Report emulation)"
        echo "  rig vpn ovpn <profile.ovpn>    -> OpenVPN (.ovpn in background)"
        echo "  rig vpn wg <profile.conf>      -> WireGuard (.conf)"
        echo "  rig vpn anyconnect <host>      -> Cisco AnyConnect"
        echo "  rig vpn fortinet <host:port>   -> Fortinet SSL VPN"
        echo "  rig vpn status                 -> Show active VPN interfaces and IPs"
        echo "  rig vpn down                   -> Disconnect all active VPNs"
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/rig-vpn

# 6c. Install Multi-Client Profile Manager (rig-profile)
sudo tee /usr/local/bin/rig-profile >/dev/null << 'EOF'
#!/usr/bin/env bash
set -e
PROFILES_DIR="$HOME/.openrig-profiles"
ACTIVE_FILE="$PROFILES_DIR/.active"
mkdir -p "$PROFILES_DIR"

ACTION="${1:-list}"
shift || true

case "$ACTION" in
    create|add)
        NAME="${1:?Usage: rig profile create <alias> <git_name> <git_email> [aws_profile]}"
        GIT_NAME="${2:?Missing git_name}"
        GIT_EMAIL="${3:?Missing git_email}"
        AWS_PROF="${4:-default}"
        PDIR="$PROFILES_DIR/$NAME"
        mkdir -p "$PDIR"
        cat << EOP > "$PDIR/profile.env"
PROFILE_NAME="$NAME"
GIT_AUTHOR_NAME="$GIT_NAME"
GIT_COMMITTER_NAME="$GIT_NAME"
GIT_AUTHOR_EMAIL="$GIT_EMAIL"
GIT_COMMITTER_EMAIL="$GIT_EMAIL"
AWS_PROFILE="$AWS_PROF"
EOP
        echo "✅ Client profile '$NAME' ($GIT_NAME <$GIT_EMAIL> | AWS: $AWS_PROF) created."
        ;;
    use|switch)
        NAME="${1:?Usage: rig profile use <alias>}"
        PDIR="$PROFILES_DIR/$NAME"
        if [ ! -f "$PDIR/profile.env" ]; then
            echo "❌ Profile '$NAME' does not exist. Create it with: rig profile create $NAME \"Name\" \"email@domain.com\""
            exit 1
        fi
        source "$PDIR/profile.env"
        git config --global user.name "$GIT_AUTHOR_NAME"
        git config --global user.email "$GIT_AUTHOR_EMAIL"
        echo "$NAME" > "$ACTIVE_FILE"
        echo "🎭 Active profile switched to: $NAME ($GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL> | AWS_PROFILE=$AWS_PROFILE)"
        ;;
    current)
        if [ -f "$ACTIVE_FILE" ]; then
            CUR=$(cat "$ACTIVE_FILE")
            echo "🎭 Active profile: $CUR ($(git config --global user.name) <$(git config --global user.email)>)"
        else
            echo "🎭 Active profile: host-default ($(git config --global user.name 2>/dev/null || echo 'unconfigured') <$(git config --global user.email 2>/dev/null || echo '')>)"
        fi
        ;;
    list|ls)
        echo "🎭 Client / Identity Profiles in OpenRig:"
        CUR=$(cat "$ACTIVE_FILE" 2>/dev/null || echo "")
        for p in "$PROFILES_DIR"/*/profile.env; do
            [ -f "$p" ] || continue
            source "$p"
            MARK="  "
            [ "$PROFILE_NAME" = "$CUR" ] && MARK="👉"
            echo "  $MARK $PROFILE_NAME -> $GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL> (AWS: $AWS_PROFILE)"
        done
        ;;
    *)
        echo "Multi-Client Profile Manager (rig profile):"
        echo "  rig profile create <alias> \"<Name>\" \"<Email>\" [aws_profile]"
        echo "  rig profile use <alias>"
        echo "  rig profile list"
        echo "  rig profile current"
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/rig-profile

# 6d. Install Instant HTTPS Demo & Webhook Tunnel (rig-share)
sudo tee /usr/local/bin/rig-share >/dev/null << 'EOF'
#!/usr/bin/env bash
set -e
PORT="${1:-8000}"
echo "🌐 [OpenRig Share] Creating temporary public HTTPS tunnel to http://localhost:${PORT}..."
echo "   (Press Ctrl+C to close the tunnel when your demo is finished)"
cloudflared tunnel --url "http://localhost:${PORT}"
EOF
sudo chmod +x /usr/local/bin/rig-share

# 6e. Install Hardware-Bound SSH Session Guard & Session Takeover (tmux)
sudo tee /usr/local/bin/rig-session-guard >/dev/null << 'EOF'
#!/usr/bin/env bash
EXPECTED_HW="${1:-ANY}"
DEV_NAME="${2:-unknown}"

# 1. Verify Hardware Fingerprint Binding (Anti-Key-Theft)
if [ "$EXPECTED_HW" != "ANY" ] && [ "$EXPECTED_HW" != "GUEST_EPHEMERAL" ]; then
    if [ "${OPENRIG_HW_ID:-}" != "$EXPECTED_HW" ]; then
        echo ""
        echo "╔════════════════════════════════════════════════════════════════════════════╗"
        echo "║ 🚨 SECURITY ALERT [OpenRig Zero-Trust Hardware Lock]                       ║"
        echo "╠════════════════════════════════════════════════════════════════════════════╣"
        echo "║ This SSH key is exclusively bound to hardware device: '$DEV_NAME'          ║"
        echo "║ Your current machine's Hardware UUID DOES NOT MATCH. Access denied.        ║"
        echo "╚════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        exit 1
    fi
fi

# 2. If Ephemeral Guest Keychain Login, burn the temporary key immediately upon entry
if [ "$EXPECTED_HW" = "GUEST_EPHEMERAL" ]; then
    sudo sed -i '/GUEST_EPHEMERAL/d' /etc/openrig/authorized_keys 2>/dev/null || true
    echo "🔑 [OpenRig Guest Keychain] Ephemeral pass verified and destroyed (zero trace left on exit)."
fi

# 3. Execute explicit command if non-interactive, otherwise do Session Takeover via tmux
if [ -n "${SSH_ORIGINAL_COMMAND:-}" ]; then
    exec zsh -ic "$SSH_ORIGINAL_COMMAND"
else
    echo "⚡ [OpenRig Session Takeover] Attaching to your live session in /workspace (detaching previous screens)..."
    exec tmux new-session -A -D -s openrig -c /workspace "zsh -l"
fi
EOF
sudo chmod +x /usr/local/bin/rig-session-guard

# 6f. Install Device, Keychain & Resource Request Manager inside Container (rig-device & rig-request)
sudo tee /usr/local/bin/rig-request >/dev/null << 'EOF'
#!/usr/bin/env bash
set -e
REQ_FILE="/workspace/.openrig-hardware-request.json"

get_live_hw() {
    python3 - << 'PY'
import os, subprocess
mem_max = "Dynamic (Host Shared)"
try:
    m = open("/sys/fs/cgroup/memory.max").read().strip()
    if m != "max":
        mem_max = f"{int(m)/(1024**3):.1f} GB"
except Exception:
    pass
cpu_max = "Dynamic (Host Shared)"
try:
    c = open("/sys/fs/cgroup/cpu.max").read().strip().split()
    if c[0] != "max":
        cpu_max = f"{int(c[0])/int(c[1]):.1f} vCPUs"
    else:
        nproc = subprocess.check_output(["nproc"]).decode().strip()
        cpu_max = f"{nproc} vCPUs (Unthrottled)"
except Exception:
    pass
print(f"{mem_max} RAM | {cpu_max}")
PY
}

SUB="${1:-status}"
case "$SUB" in
    status|list)
        echo "🧠 Live Workstation Virtual Hardware ($(hostname)): $(get_live_hw)"
        if [ -f "$REQ_FILE" ]; then
            python3 - "$REQ_FILE" << 'PY'
import json, sys
d = json.loads(open(sys.argv[1]).read())
print(f"⏳ Pending Upgrade Request: {d.get('requested_ram')} RAM | {d.get('requested_cpus')} vCPUs")
print(f"   • Reason:    {d.get('reason')}")
print(f"   • Submitted: {d.get('timestamp')}")
PY
        else
            echo "✅ Pending Upgrade Requests: None (current hardware quota is active)."
        fi
        ;;
    cancel|clear)
        rm -f "$REQ_FILE"
        echo "🗑️  Pending hardware upgrade request cancelled."
        ;;
    help|-h|--help)
        echo "Usage (Inside Connected Container):"
        echo "  rig request <ram> <cpus> [reason] -> Request live RAM/vCPU upgrade from Server Manager (e.g. rig request 8g 4 \"Android build\")"
        echo "  rig request status                -> Check live allocated RAM/vCPUs and pending request status"
        echo "  rig request cancel                -> Cancel a pending upgrade request"
        ;;
    *)
        RAM="${1:?Usage: rig request <new-ram-e.g.-8g> <new-cpus-e.g.-4> [reason]}"
        CPUS="${2:?Usage: rig request <new-ram-e.g.-8g> <new-cpus-e.g.-4> [reason]}"
        shift 2 || true
        REASON="${*:-Project requires higher compilation resources}"
        cat << EOR > "$REQ_FILE"
{
  "hostname": "$(hostname)",
  "requested_ram": "$RAM",
  "requested_cpus": "$CPUS",
  "reason": "$REASON",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOR
        echo "📨 Virtual hardware upgrade request sent to the OpenRig-Server Administrator:"
        echo "   • Current Live Hardware: $(get_live_hw)"
        echo "   • Requested Upgrade:     $RAM RAM | $CPUS vCPUs"
        echo "   • Reason:                $REASON"
        echo "   💡 Once approved by the Administrator ('rig-server scale'), your container scales LIVE with zero restart."
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/rig-request

sudo tee /usr/local/bin/rig-device >/dev/null << 'EOF'
#!/usr/bin/env bash
set -e
AUTH_KEYS="/etc/openrig/authorized_keys"
[ ! -f "$AUTH_KEYS" ] && AUTH_KEYS="$HOME/.ssh/authorized_keys"
KEYCHAIN_FILE="$HOME/.openrig-profiles/keychain.secret"
mkdir -p "$HOME/.openrig-profiles"

ACTION="${1:-list}"
shift || true

case "$ACTION" in
    list|ls)
        echo "💻 Devices bound by Hardware UUID to this OpenRig workstation:"
        echo "----------------------------------------------------------------------------"
        if [ ! -s "$AUTH_KEYS" ]; then
            echo "  (No devices bound yet)"
        else
            grep -E "rig-session-guard" "$AUTH_KEYS" | while read -r line; do
                HW=$(echo "$line" | sed -n 's/.*rig-session-guard \([^ ]*\) \([^"]*\).*/\1/p')
                DEV=$(echo "$line" | sed -n 's/.*rig-session-guard \([^ ]*\) \([^"]*\).*/\2/p')
                echo "  🔒 Device: $DEV   | Hardware ID: ${HW:0:16}..."
            done
        fi
        ;;
    revoke|remove)
        TARGET_DEV="${1:?Usage: rig device revoke <device-name>}"
        sudo sed -i "/rig-session-guard [^ ]* ${TARGET_DEV}\"/d" "$AUTH_KEYS"
        echo "🗑️  Device '$TARGET_DEV' unlinked and revoked immediately."
        ;;
    keychain)
        if [ ! -f "$KEYCHAIN_FILE" ]; then
            head -c 10 /dev/urandom | base32 | tr -d '=' > "$KEYCHAIN_FILE"
            chmod 600 "$KEYCHAIN_FILE"
        fi
        SECRET=$(cat "$KEYCHAIN_FILE")
        URI="otpauth://totp/OpenRig:$(hostname)?secret=${SECRET}&issuer=OpenRig"
        echo "🔐 [OpenRig Guest Keychain] Add this Keychain to your 1Password / Authenticator:"
        echo "   Base32 Secret (TOTP): $SECRET"
        echo "   OTPAuth URI:          $URI"
        if command -v oathtool >/dev/null 2>&1; then
            echo "   Current 6-digit code: $(oathtool --totp -b "$SECRET")"
        fi
        if command -v qrencode >/dev/null 2>&1; then
            qrencode -t ANSIUTF8 "$URI" || true
        fi
        ;;
    *)
        echo "Usage: rig device [list | revoke <device> | keychain]"
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/rig-device

# 6g. Install Unified In-Container 'rig' CLI (/usr/local/bin/rig)
sudo tee /usr/local/bin/rig >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

CYAN="\033[96m"
GREEN="\033[92m"
YELLOW="\033[93m"
RED="\033[91m"
BOLD="\033[1m"
RESET="\033[0m"

banner() {
    echo -e "${CYAN}${BOLD}"
    echo "╔══════════════════════════════════════════════════════════════════════════╗"
    echo "║   ⚡ OPENRIG — PORTABLE MODULAR DEV, SEC & AI WORKSTATION                ║"
    echo "║   By Linux Open Source S.A. de C.V.                                      ║"
    echo "╚══════════════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

run_host_bridge() {
    local cmd_str="$1"
    local cmd_file="/workspace/.openrig-host-cmd"
    local out_file="/workspace/.openrig-host-cmd.out"
    rm -f "$out_file"
    echo "$cmd_str" > "$cmd_file"
    for _ in {1..20}; do
        if [ -f "$out_file" ]; then
            cat "$out_file"
            rm -f "$out_file"
            return 0
        fi
        sleep 0.4
    done
    echo -e "${YELLOW}ℹ️ Command dispatched to Host daemon (${cmd_str}).${RESET}"
}

ACTION="${1:-help}"
shift || true

case "$ACTION" in
    ide|code|agy)
        rig-open-ide "${1:-.}"
        ;;
    profile|prof)
        rig-profile "$@"
        ;;
    vpn)
        rig-vpn "$@"
        ;;
    sec|audit)
        rig-sec "${1:-.}"
        ;;
    share|tunnel)
        rig-share "${1:-8000}"
        ;;
    phone|adb)
        rig-phone "$@"
        ;;
    device|dev)
        rig-device "$@"
        ;;
    request|req)
        rig-request "$@"
        ;;
    snapshot|snap)
        SUB="${1:-list}"
        shift || true
        case "$SUB" in
            save|create)
                TAG="${1:?Usage: rig snapshot save <snapshot-name>}"
                echo -e "${CYAN}📸 Saving workstation snapshot as 'openrig-snapshot:${TAG}'...${RESET}"
                docker commit "$(hostname)" "openrig-snapshot:${TAG}" >/dev/null
                echo -e "${GREEN}✅ Snapshot 'openrig-snapshot:${TAG}' saved successfully.${RESET}"
                ;;
            list|ls)
                echo -e "${CYAN}📸 Available Snapshots (Time Machine):${RESET}"
                docker images "openrig-snapshot" --format "table {{.Repository}}:{{.Tag}}\t{{.CreatedSince}}\t{{.Size}}"
                ;;
            export)
                TAG="${1:?Usage: rig snapshot export <snapshot-name> [output.tar.gz]}"
                OUT="${2:-openrig-${TAG}.tar.gz}"
                echo -e "${CYAN}📦 Exporting snapshot '${TAG}' to ${OUT}...${RESET}"
                docker save "openrig-snapshot:${TAG}" | gzip > "$OUT"
                echo -e "${GREEN}✅ Exported to: ${OUT}${RESET}"
                ;;
            import)
                FILE="${1:?Usage: rig snapshot import <file.tar.gz>}"
                echo -e "${CYAN}📥 Importing snapshot from ${FILE}...${RESET}"
                gunzip -c "$FILE" | docker load
                echo -e "${GREEN}✅ Snapshot imported.${RESET}"
                ;;
            restore)
                TAG="${1:?Usage: rig snapshot restore <snapshot-name>}"
                echo -e "${YELLOW}⏪ Requesting Host daemon to restore workstation to 'openrig-snapshot:${TAG}'...${RESET}"
                run_host_bridge "snapshot restore ${TAG}"
                ;;
            *)
                echo "📸 OpenRig Time Machine (Inside Container):"
                echo "  rig snapshot save <tag>              -> Freeze current workstation state"
                echo "  rig snapshot list                    -> List saved snapshots"
                echo "  rig snapshot restore <tag>           -> Roll back workstation to a snapshot"
                echo "  rig snapshot export <tag> [file.tgz] -> Export snapshot to portable .tar.gz"
                echo "  rig snapshot import <file.tgz>       -> Import a portable snapshot"
                ;;
        esac
        ;;
    service|svc)
        SUB="${1:-help}"
        shift || true
        case "$SUB" in
            up)
                SVCS="${*:?Usage: rig service up [postgres|redis|localstack]}"
                echo -e "${CYAN}🐳 Starting sibling containers on 'openrig-net': ${SVCS}${RESET}"
                run_host_bridge "service up ${SVCS}"
                docker ps --filter "network=openrig-net" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
                ;;
            down|stop)
                SVCS="${*:?Usage: rig service down [postgres|redis|localstack]}"
                echo -e "${YELLOW}🛑 Stopping sibling containers: ${SVCS}${RESET}"
                run_host_bridge "service down ${SVCS}"
                ;;
            *)
                echo "Usage: rig service up [postgres|redis|localstack]"
                echo "       rig service down [postgres|redis|localstack]"
                ;;
        esac
        ;;
    status|ps)
        banner
        echo -e "${CYAN}${BOLD}📍 Workstation Status (Inside Container '$(hostname)'):${RESET}"
        rig-request status || true
        rig-profile current || true
        rig-vpn status || true
        echo ""
        if [ -S /var/run/docker.sock ] && docker ps >/dev/null 2>&1; then
            echo -e "${CYAN}🐳 Active Containers on 'openrig-net':${RESET}"
            docker ps --filter "network=openrig-net" --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"
        elif [ "${OPENRIG_SERVER_TENANT:-false}" = "true" ] || [[ "$(hostname)" == rig-* ]]; then
            echo -e "${GREEN}🏢 Mode: OpenRig-Server Isolated Tenant Workstation (Multi-Tenant Zero-Trust)${RESET}"
        else
            echo -e "${YELLOW}🔒 Docker Socket is currently LOCKED (Anti-Malware Sandbox Mode active).${RESET}"
        fi
        ;;
    lock|sandbox)
        echo -e "${YELLOW}🔒 Activating Anti-Malware Sandbox Mode from inside OpenRig...${RESET}"
        sudo bash -c '
            if [ -S /var/run/docker.sock ]; then
                chown root:root /var/run/docker.sock
                chmod 600 /var/run/docker.sock
            fi
            gpasswd -d rig docker >/dev/null 2>&1 || true
            gpasswd -d rig sudo >/dev/null 2>&1 || true
            rm -f /etc/sudoers.d/rig*
            sed -i "/^rig ALL=/d" /etc/sudoers 2>/dev/null || true
        '
        echo -e "${GREEN}✅ Workstation JAILED (Sandbox Mode active):${RESET}"
        echo -e "   • Docker Socket locked (0600 root:root) and sudo privileges revoked."
        echo -e "   • To restore privileges, run ${BOLD}rig unlock${RESET} from your Host OS terminal."
        ;;
    unlock)
        echo -e "${RED}🔒 Security Boundary: 'rig unlock' CANNOT be executed from inside the container.${RESET}"
        echo -e "👉 Run ${BOLD}rig unlock${RESET} from your Host OS terminal (macOS/Windows/Linux) to restore privileges."
        exit 1
        ;;
    up|down|setup|uninstall|shell|join|connect|guest)
        echo -e "${YELLOW}ℹ️ You are already inside the OpenRig container ($(hostname):/workspace)!${RESET}"
        echo -e "   Host/Client command (${BOLD}rig ${ACTION}${RESET}) is executed from your external Host OS terminal."
        echo -e "   Run ${BOLD}rig -h${RESET} to see all commands available inside this container."
        ;;
    help|-h|--help|*)
        banner
        echo -e "${GREEN}${BOLD}📍 Context: INSIDE CONTAINER ($(hostname):$(pwd))${RESET}"
        rig-request status 2>/dev/null | head -n 1 || true
        echo ""
        echo -e "${BOLD}In-Container Workstation Commands:${RESET}"
        echo "  rig ide [path]                    -> Open a new Host Antigravity IDE / VS Code window at [path]"
        echo "  rig profile [create|use|list]     -> Switch Git author & AWS profile per client/company"
        echo "  rig vpn [gp|ovpn|wg|status|down]  -> Connect isolated VPN inside container (zero Host impact)"
        echo "  rig snapshot [save|restore|list]  -> Time Machine: freeze or restore workstation state"
        echo "  rig service [up|down] <name>      -> Start/stop sibling containers (postgres, redis, localstack)"
        echo "  rig sec [path]                    -> Run Security Audit (Gitleaks + Trivy + Semgrep) on [path]"
        echo "  rig share [port]                  -> Expose container port via temporary public HTTPS tunnel"
        echo "  rig phone [pair|connect|usb-bridge]-> Connect physical Android phone over Wi-Fi/USB"
        echo "  rig status                        -> Show live RAM/CPU quota, profile, VPN & sibling containers"
        echo ""
        echo -e "${BOLD}OpenRig-Server Connected Session & Security Commands:${RESET}"
        echo "  rig request <ram> <cpus> [note]   -> Request live RAM/vCPU upgrade from Server Admin (zero restart)"
        echo "  rig request [status|cancel]       -> Check live RAM/vCPU quota & pending upgrade request status"
        echo "  rig device [list|revoke|keychain] -> Manage Hardware-UUID bound devices & 1Password TOTP Keychain"
        echo "  rig lock                          -> Activate Anti-Malware Sandbox Mode (unlock is Host-only!)"
        echo "  rig -h | rig --help               -> Show this in-container command reference"
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/rig

# 7. Ensure Zsh loads all installed Version Managers & OpenRig helpers
cat << 'EOF' > "${RIG_HOME}/.zshrc.openrig"
# --- OpenRig Environment Loader ---
export LANG=en_US.UTF-8
export BROWSER=/usr/local/bin/rig-browser
export PATH="$HOME/.local/bin:$HOME/.pub-cache/bin:$HOME/flutter/bin:$HOME/Android/Sdk/cmdline-tools/latest/bin:$HOME/Android/Sdk/platform-tools:$PATH"

# Pyenv
if [ -d "$HOME/.pyenv" ]; then
    export PYENV_ROOT="$HOME/.pyenv"
    export PATH="$PYENV_ROOT/bin:$PATH"
    eval "$(pyenv init -)" 2>/dev/null || true
fi

# NVM (Node.js)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Bun
if [ -d "$HOME/.bun" ]; then
    export BUN_INSTALL="$HOME/.bun"
    export PATH="$BUN_INSTALL/bin:$PATH"
fi

# SDKMAN! (Java, Kotlin, Spring Boot, Maven, Gradle)
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"

# Swiftly
[[ -s "$HOME/.local/share/swiftly/env.sh" ]] && source "$HOME/.local/share/swiftly/env.sh"

# Load Active Client Profile if set
if [ -f "$HOME/.openrig-profiles/.active" ]; then
    ACTIVE_PROF=$(cat "$HOME/.openrig-profiles/.active")
    [ -f "$HOME/.openrig-profiles/$ACTIVE_PROF/profile.env" ] && source "$HOME/.openrig-profiles/$ACTIVE_PROF/profile.env"
    export AWS_PROFILE GIT_AUTHOR_NAME GIT_COMMITTER_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_EMAIL
fi

# Useful Aliases
alias aws-sso="aws sso login --use-device-code"
alias ll="ls -la --color=auto"
EOF

if ! grep -q ".zshrc.openrig" "${RIG_HOME}/.zshrc" 2>/dev/null; then
    echo 'source "$HOME/.zshrc.openrig"' >> "${RIG_HOME}/.zshrc"
fi

if ! grep -q ".zshrc.openrig" "${RIG_HOME}/.bashrc" 2>/dev/null; then
    echo 'source "$HOME/.zshrc.openrig"' >> "${RIG_HOME}/.bashrc"
fi

# Optional Starship activation if user selected SHELL_STYLE=starship
if [ "${OPENRIG_SHELL:-ohmyzsh}" = "starship" ] && command -v starship >/dev/null 2>&1; then
    if ! grep -q "starship init zsh" "${RIG_HOME}/.zshrc" 2>/dev/null; then
        echo 'eval "$(starship init zsh)"' >> "${RIG_HOME}/.zshrc"
    fi
fi

exec "$@"
