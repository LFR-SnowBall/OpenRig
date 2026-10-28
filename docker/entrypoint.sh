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

# 3b. Central Brain Split-Brain Architecture (100% Opt-In — Never auto-created unless user runs 'rig brain init/link/clone')
sudo mkdir -p /var/openrig-vault /etc/openrig
sudo chown root:root /var/openrig-vault /etc/openrig
sudo chmod 755 /var/openrig-vault /etc/openrig

if [ "${OPENRIG_SERVER_TENANT:-false}" = "true" ] || [[ "$(hostname)" == rig-* ]]; then
    mkdir -p /dev/shm/.personal-core
    chmod 700 /dev/shm/.personal-core
    if [ ! -f /etc/openrig/dlp-policy.json ]; then
        sudo tee /etc/openrig/dlp-policy.json >/dev/null << EODLP
{
  "tenant_user": "$(hostname)",
  "dlp_mode": "sanitized",
  "blocked_terms": []
}
EODLP
        sudo chown root:root /etc/openrig/dlp-policy.json
        sudo chmod 644 /etc/openrig/dlp-policy.json
    fi
fi

# Restore Brain symlinks ONLY if the user previously opted in via 'rig brain'
if [ -f "${RIG_HOME}/.openrig-profiles/.brain-enabled" ] && [ -d "${RIG_HOME}/.brain" ]; then
    mkdir -p "${RIG_HOME}/.agents"
    if [ -f "${RIG_HOME}/.brain/AGENTS.md" ]; then
        ln -sfn "${RIG_HOME}/.brain/AGENTS.md" "${RIG_HOME}/.agents/AGENTS.md"
        ln -sfn "${RIG_HOME}/.brain/AGENTS.md" "${RIG_HOME}/CLAUDE.md"
    fi
    for bscript in brain-graph brain-task brain-audit; do
        if [ -f "${RIG_HOME}/.brain/core/scripts/${bscript}.py" ]; then
            sudo ln -sfn "${RIG_HOME}/.brain/core/scripts/${bscript}.py" "/usr/local/bin/${bscript}"
            sudo chmod +x "${RIG_HOME}/.brain/core/scripts/${bscript}.py" 2>/dev/null || true
        fi
    done
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

# 4b. Install Host IDE Bridge inside Container (code / antigravity / cursor)
# Allows running 'code .' or 'antigravity .' inside 'rig shell' to open a new Host IDE window attached to that exact folder inside OpenRig!
# Note: 'agy' is reserved for the Antigravity CLI terminal agent (/home/rig/.local/bin/agy).
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
for ide_cmd in code antigravity cursor; do
    sudo ln -sf /usr/local/bin/rig-open-ide "/usr/local/bin/${ide_cmd}"
done
if [ -x /home/rig/.local/bin/agy ]; then
    sudo ln -sf /home/rig/.local/bin/agy /usr/local/bin/agy
fi

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

# 2. If Ephemeral Guest Keychain Login, burn the temporary key immediately upon entry & wipe personal RAM projection
if [ "$EXPECTED_HW" = "GUEST_EPHEMERAL" ]; then
    sudo sed -i '/GUEST_EPHEMERAL/d' /etc/openrig/authorized_keys 2>/dev/null || true
    chmod -R u+w /dev/shm/.personal-core 2>/dev/null || true
    rm -rf /dev/shm/.personal-core/* 2>/dev/null || true
    echo "🔑 [OpenRig Guest Keychain] Ephemeral pass verified and destroyed (zero trace left on exit)."
fi

# 3. Execute explicit command if non-interactive, otherwise do Session Takeover via tmux
if [ -n "${SSH_ORIGINAL_COMMAND:-}" ]; then
    exec zsh -ic "$SSH_ORIGINAL_COMMAND"
else
    # Ensure ephemeral RAM projection is bound strictly to this Hardware UUID and wiped on disconnect
    echo "${OPENRIG_HW_ID:-LOCAL}:${DEV_NAME}" > /dev/shm/.personal-core/.session-owner 2>/dev/null || true
    echo "⚡ [OpenRig Session Takeover] Attaching to your isolated session in /workspace (User: $(hostname) | Device: ${DEV_NAME})..."
    tmux new-session -A -D -s openrig -c /workspace "zsh -l"
    # On SSH disconnect: wipe in-RAM personal projection & personal AI vault so zero personal files/tokens remain on server RAM
    chmod -R u+w /dev/shm/.personal-core /dev/shm/.openrig-ai-personal 2>/dev/null || true
    rm -rf /dev/shm/.personal-core/* /dev/shm/.openrig-ai-personal/* 2>/dev/null || true
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

# 6f-bis. Install Split-Brain & Enterprise DLP Firewall Manager (/usr/local/bin/rig-brain)
sudo tee /usr/local/bin/rig-brain >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

DLP_POLICY="/etc/openrig/dlp-policy.json"
RAM_CORE="/dev/shm/.personal-core"
CORP_BRAIN="/workspace/.company-brain"
EXPORT_QUEUE="/workspace/.openrig-brain-export.json"

is_server_tenant() {
    [ "${OPENRIG_SERVER_TENANT:-false}" = "true" ] || [[ "$(hostname)" == rig-* ]]
}

dlp_scan_file() {
    local target_file="$1"
    python3 - "$target_file" "$DLP_POLICY" << 'PY'
import json, os, re, sys

fpath, policy_path = sys.argv[1], sys.argv[2]
if not os.path.isfile(fpath):
    print(f"❌ File not found: {fpath}")
    sys.exit(1)

txt = open(fpath, errors="ignore").read()
lines = txt.splitlines()

blocked_terms = []
if os.path.isfile(policy_path):
    try:
        blocked_terms = json.loads(open(policy_path).read()).get("blocked_terms", [])
    except Exception:
        pass

rules = [
    ("DLP-001 (Credit Card PAN)", re.compile(r"\b(?:4[0-9]{12}(?:[0-9]{3})?|5[1-5][0-9]{14}|3[47][0-9]{13})\b")),
    ("DLP-002 (Live API Key / Token)", re.compile(r"\b(?:AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9_]{36,}|AIza[0-9A-Za-z\-_]{35}|sk-[A-Za-z0-9]{20,})\b")),
    ("DLP-003 (12-Digit AWS Account ID)", re.compile(r"\b\d{12}\b")),
    ("DLP-004 (Private RFC1918 IP Address)", re.compile(r"\b(?:10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(?:1[6-9]|2\d|3[0-1])\.\d{1,3}\.\d{1,3})\b")),
    ("DLP-005 (Internal Corporate Domain)", re.compile(r"\b[a-zA-Z0-9.-]+\.(?:internal|corp|lan|local|intranet)\b", re.I)),
    ("DLP-006 (Plaintext Password Assignment)", re.compile(r"(?i)(?:password|passwd|pwd|secret)\s*[:=]\s*['\"][^'\"\{\[\$]{4,}['\"]")),
]

findings = []
for idx, line in enumerate(lines, 1):
    for rname, pat in rules:
        m = pat.search(line)
        if m and "411111" not in m.group(0):
            findings.append((idx, rname, m.group(0)))
    for term in blocked_terms:
        if term and re.search(rf"\b{re.escape(term)}\b", line, re.I):
            findings.append((idx, f"DLP-CORP (Blocked Enterprise Term: '{term}')", term))

if findings:
    print("🚨 [OpenRig Enterprise DLP & Big-4 Gate] EXPORT BLOCKED — Violations detected:")
    for ln, rname, match in findings:
        print(f"   • Line {ln}: {rname} -> '{match}'")
    print("\n💡 Sanitize all corporate identifiers, IPs, and secrets into generic placeholders before graduating to your Personal Brain.")
    sys.exit(2)

print("✅ [OpenRig Enterprise DLP & Big-4 Gate] 0 violations found (100% generic & sanitized).")
PY
}

activate_brain_symlinks() {
    mkdir -p "$HOME/.openrig-profiles" "$HOME/.agents"
    echo "enabled" > "$HOME/.openrig-profiles/.brain-enabled"
    if [ -f "$HOME/.brain/AGENTS.md" ]; then
        ln -sfn "$HOME/.brain/AGENTS.md" "$HOME/.agents/AGENTS.md"
        ln -sfn "$HOME/.brain/AGENTS.md" "$HOME/CLAUDE.md"
    fi
    for bscript in brain-graph brain-task brain-audit; do
        if [ -f "$HOME/.brain/core/scripts/${bscript}.py" ]; then
            sudo ln -sfn "$HOME/.brain/core/scripts/${bscript}.py" "/usr/local/bin/${bscript}"
            sudo chmod +x "$HOME/.brain/core/scripts/${bscript}.py" 2>/dev/null || true
        fi
    done
}

ACTION="${1:-status}"
shift || true

case "$ACTION" in
    init|create)
        if is_server_tenant; then
            TARGET_DIR="$CORP_BRAIN"
            echo "🏢 [OpenRig Enterprise Brain] Initializing isolated corporate brain in ${TARGET_DIR}..."
        else
            TARGET_DIR="/workspace/.brain"
            echo "🧠 [OpenRig Personal Brain] Initializing new AI Central Brain in ${TARGET_DIR}..."
        fi
        mkdir -p "${TARGET_DIR}/core/steering" "${TARGET_DIR}/core/gotchas" "${TARGET_DIR}/skills/generic" "${TARGET_DIR}/tasks" "${TARGET_DIR}/contexts/personal"
        if [ ! -f "${TARGET_DIR}/AGENTS.md" ]; then
            cat << 'EOA' > "${TARGET_DIR}/AGENTS.md"
# 🧠 AGENTS.md — OpenRig AI Central Brain Directive

1. Always consult `core/steering/` and `core/gotchas/` before proposing architectural changes.
2. Document solved technical gotchas in `core/gotchas/` (100% sanitized — zero secrets, PII, PANs, or internal IPs).
3. Enforce clean tests, linter compliance, and explicit human authorization before `git commit` or `git push`.
EOA
        fi
        if [ ! -f "${TARGET_DIR}/tasks/BOARD.md" ]; then
            echo -e "# 📋 Global AI Task Board\n\n| ID | Status | Task | Agent |\n|---|---|---|---|" > "${TARGET_DIR}/tasks/BOARD.md"
        fi
        (cd "$TARGET_DIR" && [ ! -d .git ] && git init -q || true)
        ln -sfn "$TARGET_DIR" "$HOME/.brain"
        activate_brain_symlinks
        echo "✅ Brain initialized and linked at ~/.brain (-> ${TARGET_DIR})."
        ;;
    clone)
        REPO_URL="${1:?Usage: rig brain clone <git-repo-url>}"
        TARGET_DIR="/workspace/.brain"
        is_server_tenant && TARGET_DIR="$CORP_BRAIN"
        echo "📥 Cloning Brain repository into ${TARGET_DIR}..."
        rm -rf "$TARGET_DIR"
        git clone "$REPO_URL" "$TARGET_DIR"
        ln -sfn "$TARGET_DIR" "$HOME/.brain"
        activate_brain_symlinks
        echo "✅ Brain cloned and activated at ~/.brain (-> ${TARGET_DIR})."
        ;;
    off|disable|unlink)
        rm -f "$HOME/.openrig-profiles/.brain-enabled" "$HOME/.brain" "$HOME/.agents/AGENTS.md" "$HOME/CLAUDE.md" 2>/dev/null || true
        chmod -R u+w "$RAM_CORE" 2>/dev/null || true
        rm -rf "${RAM_CORE:?}"/* 2>/dev/null || true
        echo "⚪ Brain deactivated and unlinked in this container (zero active brain mounts)."
        ;;
    status)
        if [ ! -f "$HOME/.openrig-profiles/.brain-enabled" ] && [ ! -d "$RAM_CORE/core" ]; then
            echo "🧠 [OpenRig Brain Status — OPT-IN (Currently Inactive)]"
            echo "   • Brain is disabled by default so every user decides whether to use one."
            echo "   👉 Create a new Brain from scratch:   rig brain init"
            echo "   👉 Clone an existing Brain repo:      rig brain clone <git-url>"
            echo "   👉 Or link your Host ~/.brain (Host): rig brain link"
            exit 0
        fi
        if is_server_tenant; then
            echo "🧠 [OpenRig Split-Brain Status — Enterprise Server Tenant ($(hostname))]"
            echo "   • Isolation Scope:   Dedicated Container ($(hostname)) + Private RAM IPC (/dev/shm)"
            [ -d "$CORP_BRAIN" ] && echo "   • Corporate Brain:   🟢 ACTIVE at ${CORP_BRAIN} (never leaves server)"
            if [ -d "$RAM_CORE/core" ] || [ -d "$RAM_CORE/skills" ]; then
                OWNER=$(cat "$RAM_CORE/.session-owner" 2>/dev/null || echo "Active SSH Session")
                echo "   • Personal Core RAM: 🟢 ACTIVE in /dev/shm/.personal-core (Read-Only | Bound to: ${OWNER})"
                echo "                        (Zero personal 'contexts/' on server; auto-wiped on SSH disconnect)"
            else
                echo "   • Personal Core RAM: ⚪ Not projected in RAM (use 'rig connect --brain' from your laptop)"
            fi
            if [ -f "$DLP_POLICY" ]; then
                python3 - "$DLP_POLICY" << 'PY'
import json, sys
d = json.loads(open(sys.argv[1]).read())
print(f"   • Admin DLP Policy:  mode={d.get('dlp_mode','sanitized').upper()} | blocked_terms={len(d.get('blocked_terms',[]))} corporate terms")
PY
            fi
        else
            echo "🧠 [OpenRig Brain Status — Personal Workstation ($(hostname))]"
            if [ -d "$HOME/.brain" ] && [ -r "$HOME/.brain" ]; then
                echo "   • Brain Status:      🟢 ACTIVE (/home/rig/.brain -> $(readlink -f "$HOME/.brain"))"
                echo "   • Sandbox Lock:      Inactive (run 'rig lock' to seal Brain during untrusted repo audits)"
                if [ -x "$HOME/.brain/core/scripts/brain-audit.py" ]; then
                    echo "   • Big-4 Audit Tool:  Available ('rig brain audit' / 'brain-audit')"
                fi
            else
                echo "   • Brain Status:      🔒 SEALED (Anti-Malware Sandbox Mode active)"
            fi
        fi
        ;;
    audit)
        TARGET="${1:-}"
        if [ -n "$TARGET" ] && [ -f "$TARGET" ]; then
            dlp_scan_file "$TARGET"
        elif [ -f "$HOME/.brain/core/scripts/brain-audit.py" ]; then
            python3 "$HOME/.brain/core/scripts/brain-audit.py"
        else
            echo "Usage: rig brain audit <file.md>"
        fi
        ;;
    learn|graduate)
        FILE="${1:?Usage: rig brain learn <generic-note.md>}"
        if ! is_server_tenant; then
            dlp_scan_file "$FILE"
            mkdir -p "$HOME/.brain/core/gotchas"
            cp "$FILE" "$HOME/.brain/core/gotchas/$(basename "$FILE")"
            echo "✅ Saved directly to your Personal Brain: ~/.brain/core/gotchas/$(basename "$FILE")"
            exit 0
        fi
        DLP_MODE="sanitized"
        if [ -f "$DLP_POLICY" ]; then
            DLP_MODE=$(python3 -c "import json,sys; print(json.loads(open(sys.argv[1]).read()).get('dlp_mode','sanitized'))" "$DLP_POLICY")
        fi
        if [ "$DLP_MODE" = "airgapped" ]; then
            echo "🚫 [Enterprise DLP Air-Gap Policy] Your Server Administrator has set DLP mode to 'AIRGAPPED'."
            echo "   Exporting learnings to a personal brain is strictly disabled for this workstation."
            exit 1
        fi
        # Mandatory DLP + Big-4 Scan
        dlp_scan_file "$FILE"
        if [ "$DLP_MODE" = "approval" ]; then
            python3 - "$FILE" "$EXPORT_QUEUE" "$(hostname)" << 'PY'
import json, os, sys, time
fpath, qpath, host = sys.argv[1], sys.argv[2], sys.argv[3]
payload = {
    "hostname": host,
    "filename": os.path.basename(fpath),
    "content": open(fpath).read(),
    "status": "PENDING_ADMIN_APPROVAL",
    "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
}
open(qpath, "w").write(json.dumps(payload, indent=2))
PY
            echo "⏳ [Enterprise DLP Approval Gate] File passed automated DLP scan and is queued for Administrator review."
            echo "   Once approved via 'rig-server brain-requests approve', it will sync to your Personal Brain."
        else
            chmod u+w "$RAM_CORE" 2>/dev/null || mkdir -p "$RAM_CORE"
            mkdir -p "$RAM_CORE/.outbox"
            cp "$FILE" "$RAM_CORE/.outbox/$(basename "$FILE")"
            echo "✅ [Enterprise DLP Gate Passed] Note staged in isolated RAM outbox (/dev/shm/.personal-core/.outbox/$(basename "$FILE"))."
            echo "   It will automatically sync to your laptop's ~/.brain/core/gotchas/ when you disconnect or run 'rig brain pull'."
        fi
        ;;
    flush|wipe)
        chmod -R u+w "$RAM_CORE" 2>/dev/null || true
        rm -rf "${RAM_CORE:?}"/* 2>/dev/null || true
        echo "🧹 In-RAM personal brain projection (/dev/shm/.personal-core) wiped clean."
        ;;
    *)
        echo "🧠 OpenRig Opt-In Split-Brain & Enterprise DLP Manager (rig brain):"
        echo "  rig brain init                -> Create a new AI Brain from scratch (100% opt-in)"
        echo "  rig brain clone <git-url>     -> Clone an existing Brain repository into this workstation"
        echo "  rig brain status              -> Show Brain status, RAM projection, and Enterprise DLP mode"
        echo "  rig brain audit [file.md]     -> Run Enterprise DLP & Big-4 Security Audit"
        echo "  rig brain learn <file.md>     -> Sanitize & graduate a generic technical learning through the DLP Gate"
        echo "  rig brain off                 -> Disable & unlink Brain in this container"
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/rig-brain

# 6f-ter. Install Dual-Engine AI Session Switcher & Zero-Key Broker Client (/usr/local/bin/rig-ai)
sudo tee /usr/local/bin/rig-ai >/dev/null << 'EOF'
#!/usr/bin/env bash
set -euo pipefail

CORP_ENV="/etc/openrig/ai-corporate.env"
ACTIVE_AI_ENV="$HOME/.openrig-profiles/.ai-active.env"
CORP_VAULT="$HOME/.openrig-profiles/ai-corporate-vault"
PERS_VAULT="/dev/shm/.openrig-ai-personal"
mkdir -p "$HOME/.openrig-profiles"

link_ai_dirs() {
    local base_dir="$1"
    mkdir -p "${base_dir}/.claude" "${base_dir}/.gemini" "${base_dir}/.codex" "${base_dir}/.kiro"
    for tool_dir in .claude .gemini .codex .kiro; do
        if [ -d "$HOME/${tool_dir}" ] && [ ! -L "$HOME/${tool_dir}" ]; then
            mv "$HOME/${tool_dir}" "${base_dir}/${tool_dir}-backup" 2>/dev/null || rm -rf "$HOME/${tool_dir}"
        fi
        ln -sfn "${base_dir}/${tool_dir}" "$HOME/${tool_dir}"
    done
}

SUB="${1:-status}"
shift || true

case "$SUB" in
    use|switch)
        TARGET="${1:?Usage: rig ai use [corporate | personal]}"
        case "$TARGET" in
            corporate|corp|company)
                if [ ! -f "$CORP_ENV" ]; then
                    echo "❌ No Corporate AI Broker configured on this workstation (/etc/openrig/ai-corporate.env)."
                    echo "   (In OpenRig-Server, the Administrator configures it via: rig-server ai set --provider bedrock)"
                    exit 1
                fi
                source "$CORP_ENV"
                link_ai_dirs "$CORP_VAULT"
                cat << EOA > "$ACTIVE_AI_ENV"
export OPENRIG_AI_ACTIVE_MODE="corporate"
export OPENRIG_AI_PROVIDER="${OPENRIG_AI_PROVIDER:-bedrock}"
EOA
                case "${OPENRIG_AI_PROVIDER:-bedrock}" in
                    bedrock)
                        cat << EOB >> "$ACTIVE_AI_ENV"
export CLAUDE_CODE_USE_BEDROCK=1
export ANTHROPIC_BEDROCK_BASE_URL="${OPENRIG_AI_BROKER_URL}"
export AWS_BEARER_TOKEN_BEDROCK="${OPENRIG_AI_TICKET}"
export ANTHROPIC_AUTH_TOKEN="${OPENRIG_AI_TICKET}"
export AWS_REGION="${AWS_REGION:-us-east-1}"
EOB
                        ;;
                    anthropic)
                        cat << EOB >> "$ACTIVE_AI_ENV"
unset CLAUDE_CODE_USE_BEDROCK
export ANTHROPIC_BASE_URL="${OPENRIG_AI_BROKER_URL}"
export ANTHROPIC_API_KEY="${OPENRIG_AI_TICKET}"
EOB
                        ;;
                    openai|litellm)
                        cat << EOB >> "$ACTIVE_AI_ENV"
unset CLAUDE_CODE_USE_BEDROCK
export OPENAI_BASE_URL="${OPENRIG_AI_BROKER_URL}"
export OPENAI_API_KEY="${OPENRIG_AI_TICKET}"
EOB
                        ;;
                    gemini)
                        cat << EOB >> "$ACTIVE_AI_ENV"
unset CLAUDE_CODE_USE_BEDROCK
export GOOGLE_GEMINI_BASE_URL="${OPENRIG_AI_BROKER_URL}"
export GEMINI_API_KEY="${OPENRIG_AI_TICKET}"
EOB
                        ;;
                esac
                echo "🏢 [OpenRig AI Switcher] Switched to CORPORATE AI (${OPENRIG_AI_PROVIDER^^} via Zero-Key Server Broker)."
                echo "   • Real corporate keys/AWS credentials NEVER enter this container (authenticated via internal broker ticket)."
                echo "   • Session & chat history isolated in ${CORP_VAULT}."
                echo "   💡 Run 'source ~/.zshrc' (or open a new shell) to apply environment variables immediately."
                ;;
            personal|pers|my)
                if [ -f "$CORP_ENV" ]; then
                    source "$CORP_ENV"
                    if [ "${OPENRIG_AI_POLICY:-hybrid}" = "corporate-only" ]; then
                        echo "🚫 [Enterprise AI Policy] Your Server Administrator has enforced 'CORPORATE-ONLY' AI mode."
                        echo "   Switching to personal AI accounts is disabled on this workstation."
                        exit 1
                    fi
                fi
                mkdir -p "$PERS_VAULT"
                chmod 700 "$PERS_VAULT"
                link_ai_dirs "$PERS_VAULT"
                cat << 'EOA' > "$ACTIVE_AI_ENV"
export OPENRIG_AI_ACTIVE_MODE="personal"
unset CLAUDE_CODE_USE_BEDROCK ANTHROPIC_BEDROCK_BASE_URL AWS_BEARER_TOKEN_BEDROCK ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_BASE_URL OPENAI_BASE_URL GOOGLE_GEMINI_BASE_URL
EOA
                echo "👤 [OpenRig AI Switcher] Switched to PERSONAL AI (Isolated RAM Vault: ${PERS_VAULT})."
                echo "   • Zero mixing with corporate AI billing or corporate chat history."
                echo "   • Stored strictly in private RAM (/dev/shm) and automatically wiped when you disconnect from SSH."
                echo "   💡 Run 'source ~/.zshrc' (or open a new shell) and log in with your personal AI CLI."
                ;;
            *)
                echo "Usage: rig ai use [corporate | personal]"
                exit 1
                ;;
        esac
        ;;
    status|*)
        ACTIVE_MODE="personal"
        [ -f "$ACTIVE_AI_ENV" ] && source "$ACTIVE_AI_ENV" && ACTIVE_MODE="${OPENRIG_AI_ACTIVE_MODE:-personal}"
        echo "🤖 [OpenRig Dual-Engine AI Session Status]"
        if [ -f "$CORP_ENV" ]; then
            source "$CORP_ENV"
            echo "   • Server AI Broker:  🟢 AVAILABLE (Provider: ${OPENRIG_AI_PROVIDER^^} | Policy: ${OPENRIG_AI_POLICY^^})"
            echo "   • Key Exposure:      🔒 ZERO (Using container-scoped broker ticket ${OPENRIG_AI_TICKET:0:22}...)"
        else
            echo "   • Server AI Broker:  ⚪ Not configured (Local Personal Workstation)"
        fi
        if [ "$ACTIVE_MODE" = "corporate" ]; then
            echo "   • Active AI Session: 🏢 CORPORATE (${CORP_VAULT})"
        else
            echo "   • Active AI Session: 👤 PERSONAL (Isolated RAM Vault: ${PERS_VAULT})"
        fi
        echo "   👉 Switch engine:    rig ai use corporate  |  rig ai use personal"
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/rig-ai

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
    echo "║   Created by Luis Fernando Real (@LFR-SnowBall)                          ║"
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
    brain)
        rig-brain "$@"
        ;;
    ai)
        rig-ai "$@"
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
        rig-ai status || true
        rig-brain status || true
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
            if [ -d /var/openrig-vault ]; then
                chmod 000 /var/openrig-vault
            fi
            chmod -R u+w /dev/shm/.personal-core /dev/shm/.openrig-ai-personal 2>/dev/null || true
            rm -rf /dev/shm/.personal-core/* /dev/shm/.openrig-ai-personal/* 2>/dev/null || true
            gpasswd -d rig docker >/dev/null 2>&1 || true
            gpasswd -d rig sudo >/dev/null 2>&1 || true
            rm -f /etc/sudoers.d/rig*
            sed -i "/^rig ALL=/d" /etc/sudoers 2>/dev/null || true
        '
        echo -e "${GREEN}✅ Workstation JAILED (Sandbox Mode active):${RESET}"
        echo -e "   • Docker Socket locked (0600 root:root) and sudo privileges revoked."
        echo -e "   • Central Brain Vault (/home/rig/.brain) sealed (000 VFS traversal lock)."
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
        echo "  rig ai [status|use corp|personal] -> Switch between Shared Corporate AI (Bedrock/Broker) & RAM Personal AI"
        echo "  rig brain [status|audit|learn]    -> Manage Split-Brain Vault & Enterprise DLP Graduation Gate"
        echo "  rig profile [create|use|list]     -> Switch Git author & AWS profile per client/company"
        echo "  rig vpn [gp|ovpn|wg|status|down]  -> Connect isolated VPN inside container (zero Host impact)"
        echo "  rig snapshot [save|restore|list]  -> Time Machine: freeze or restore workstation state"
        echo "  rig service [up|down] <name>      -> Start/stop sibling containers (postgres, redis, localstack)"
        echo "  rig sec [path]                    -> Run Security Audit (Gitleaks + Trivy + Semgrep) on [path]"
        echo "  rig share [port]                  -> Expose container port via temporary public HTTPS tunnel"
        echo "  rig phone [pair|connect|usb-bridge]-> Connect physical Android phone over Wi-Fi/USB"
        echo "  rig status                        -> Show live RAM/CPU quota, AI mode, Brain, profile & VPN"
        echo ""
        echo -e "${BOLD}OpenRig-Server Connected Session & Security Commands:${RESET}"
        echo "  rig request <ram> <cpus> [note]   -> Request live RAM/vCPU upgrade from Server Admin (zero restart)"
        echo "  rig request [status|cancel]       -> Check live RAM/vCPU quota & pending upgrade request status"
        echo "  rig device [list|revoke|keychain] -> Manage Hardware-UUID bound devices & 1Password TOTP Keychain"
        echo "  rig lock                          -> Activate Anti-Malware Sandbox Mode (seals Brain & Docker)"
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

# Load Active Dual-Engine AI Session (Corporate Zero-Key Broker vs. Personal RAM Vault)
if [ -f "$HOME/.openrig-profiles/.ai-active.env" ]; then
    source "$HOME/.openrig-profiles/.ai-active.env"
elif [ -f "/etc/openrig/ai-corporate.env" ]; then
    /usr/local/bin/rig-ai use corporate >/dev/null 2>&1 || true
    [ -f "$HOME/.openrig-profiles/.ai-active.env" ] && source "$HOME/.openrig-profiles/.ai-active.env"
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
