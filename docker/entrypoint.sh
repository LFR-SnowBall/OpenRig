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
echo "║ 🌐 [OpenRig Browser Bridge] Autenticación requerida en tu navegador Host:  ║"
echo "╠════════════════════════════════════════════════════════════════════════════╣"
echo "║ Haz Cmd+Click (Mac) o Ctrl+Click (Windows/Linux) en el siguiente enlace:   ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo "👉 $1"
echo ""
EOF
sudo chmod +x /usr/local/bin/rig-browser

# 5. Install Mobile ADB Helper (Wireless & USB Host Bridge)
sudo tee /usr/local/bin/rig-phone >/dev/null << 'EOF'
#!/usr/bin/env bash
set -e
ACTION="${1:-help}"
case "$ACTION" in
    pair)
        echo "📱 Emparejando con celular Android por Wi-Fi Debugging..."
        adb pair "${2:?Uso: rig-phone pair IP:PUERTO}"
        ;;
    connect)
        echo "📱 Conectando con celular Android por Wi-Fi..."
        adb connect "${2:?Uso: rig-phone connect IP:PUERTO}"
        adb devices -l
        ;;
    usb-bridge)
        echo "🔌 Conectando al servidor ADB USB del Host (host.docker.internal:5037)..."
        export ADB_SERVER_SOCKET=tcp:host.docker.internal:5037
        adb devices -l
        ;;
    *)
        echo "📱 OpenRig Mobile Helper (rig-phone):"
        echo "  rig-phone pair <IP:PORT>     -> Empareja celular por Depuración Inalámbrica (Android 11+)"
        echo "  rig-phone connect <IP:PORT>  -> Conecta celular por Wi-Fi para 'flutter run' / debug"
        echo "  rig-phone usb-bridge         -> Usa el cable USB conectado a tu máquina Host"
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/rig-phone

# 6. Install Security Quick-Scanner Helper (rig-sec)
sudo tee /usr/local/bin/rig-sec >/dev/null << 'EOF'
#!/usr/bin/env bash
set -e
TARGET="${1:-.}"
echo "🛡️ [OpenRig Security Suite] Escaneando objetivo: $TARGET"
echo "--------------------------------------------------------"
if command -v gitleaks >/dev/null 2>&1; then
    echo "🔍 [1/3] Gitleaks (Detección de secretos expuestos)..."
    gitleaks detect --source "$TARGET" --no-git || true
fi
if command -v trivy >/dev/null 2>&1; then
    echo "🔍 [2/3] Trivy (Vulnerabilidades SCA/CVEs y misconfigs)..."
    trivy fs --scanners vuln,misconfig "$TARGET" || true
fi
if command -v semgrep >/dev/null 2>&1; then
    echo "🔍 [3/3] Semgrep (Análisis Estático SAST)..."
    semgrep scan --config=auto "$TARGET" || true
fi
echo "✅ Escaneo de seguridad finalizado."
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
        PORTAL="${1:?Uso: rig vpn gp <portal.empresa.com>}"
        shift || true
        echo "🛡️ [OpenRig VPN] Conectando a Palo Alto GlobalProtect ($PORTAL)..."
        if [ -f "$HIP_SCRIPT" ]; then
            sudo openconnect --protocol=gp --csd-wrapper="$HIP_SCRIPT" --background "$PORTAL" "$@"
        else
            sudo openconnect --protocol=gp --background "$PORTAL" "$@"
        fi
        echo "✅ Túnel GlobalProtect activo dentro de OpenRig (tu Host sigue libre)."
        ;;
    ovpn|openvpn)
        OVPN_FILE="${1:?Uso: rig vpn ovpn <archivo.ovpn>}"
        echo "🛡️ [OpenRig VPN] Conectando OpenVPN con $OVPN_FILE..."
        sudo openvpn --config "$OVPN_FILE" --daemon
        sleep 2
        ip -brief addr show | grep -E "tun|tap" || true
        ;;
    wg|wireguard)
        WG_CONF="${1:?Uso: rig vpn wg <archivo.conf>}"
        echo "🛡️ [OpenRig VPN] Levantando túnel WireGuard ($WG_CONF)..."
        sudo wg-quick up "$WG_CONF"
        ;;
    anyconnect|cisco)
        SERVER="${1:?Uso: rig vpn anyconnect <vpn.empresa.com>}"
        shift || true
        echo "🛡️ [OpenRig VPN] Conectando a Cisco AnyConnect ($SERVER)..."
        sudo openconnect --protocol=anyconnect --background "$SERVER" "$@"
        ;;
    fortinet|forti)
        SERVER="${1:?Uso: rig vpn fortinet <vpn.empresa.com:puerto>}"
        shift || true
        echo "🛡️ [OpenRig VPN] Conectando a Fortinet SSL VPN ($SERVER)..."
        sudo openfortivpn "$SERVER" "$@" &
        ;;
    status)
        echo "🔒 [OpenRig VPN Status] Interfaces de túnel activas dentro de OpenRig:"
        ip -brief addr show | grep -E "tun|tap|wg|ppp" || echo "  (Ninguna VPN activa en este momento)"
        ;;
    down|stop)
        echo "🛑 Cerrando túneles VPN dentro de OpenRig..."
        sudo killall openconnect openvpn openfortivpn 2>/dev/null || true
        echo "✅ VPN desconectada."
        ;;
    *)
        echo "🔒 OpenRig Multi-VPN Manager (Aislada del Host OS):"
        echo "  rig vpn gp <portal.com>        -> Palo Alto GlobalProtect (con HIP Report emulation)"
        echo "  rig vpn ovpn <archivo.ovpn>    -> OpenVPN (.ovpn en segundo plano)"
        echo "  rig vpn wg <archivo.conf>      -> WireGuard (.conf)"
        echo "  rig vpn anyconnect <host>      -> Cisco AnyConnect"
        echo "  rig vpn fortinet <host:port>   -> Fortinet SSL VPN"
        echo "  rig vpn status                 -> Muestra IPs e interfaces de VPN activas"
        echo "  rig vpn down                   -> Desconecta cualquier VPN activa"
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
        NAME="${1:?Uso: rig profile create <alias> <git_name> <git_email> [aws_profile]}"
        GIT_NAME="${2:?Falta git_name}"
        GIT_EMAIL="${3:?Falta git_email}"
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
        echo "✅ Perfil de cliente '$NAME' ($GIT_NAME <$GIT_EMAIL> | AWS: $AWS_PROF) creado."
        ;;
    use|switch)
        NAME="${1:?Uso: rig profile use <alias>}"
        PDIR="$PROFILES_DIR/$NAME"
        if [ ! -f "$PDIR/profile.env" ]; then
            echo "❌ El perfil '$NAME' no existe. Créalo con: rig profile create $NAME \"Nombre\" \"email@dominio.com\""
            exit 1
        fi
        source "$PDIR/profile.env"
        git config --global user.name "$GIT_AUTHOR_NAME"
        git config --global user.email "$GIT_AUTHOR_EMAIL"
        echo "$NAME" > "$ACTIVE_FILE"
        echo "🎭 Perfil activo cambiado a: $NAME ($GIT_AUTHOR_NAME <$GIT_AUTHOR_EMAIL> | AWS_PROFILE=$AWS_PROFILE)"
        ;;
    current)
        if [ -f "$ACTIVE_FILE" ]; then
            CUR=$(cat "$ACTIVE_FILE")
            echo "🎭 Perfil activo: $CUR ($(git config --global user.name) <$(git config --global user.email)>)"
        else
            echo "🎭 Perfil activo: host-default ($(git config --global user.name 2>/dev/null || echo 'sin configurar') <$(git config --global user.email 2>/dev/null || echo '')>)"
        fi
        ;;
    list|ls)
        echo "🎭 Perfiles de Cliente / Identidad en OpenRig:"
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
        echo "Uso de Perfiles por Cliente (rig profile):"
        echo "  rig profile create <alias> \"<Nombre>\" \"<Email>\" [aws_profile]"
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
echo "🌐 [OpenRig Share] Creando túnel HTTPS público temporal hacia http://localhost:${PORT}..."
echo "   (Presiona Ctrl+C para cerrar el túnel cuando termines la demo)"
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
        echo "║ 🚨 ALERTA DE SEGURIDAD [OpenRig Zero-Trust Hardware Lock]                  ║"
        echo "╠════════════════════════════════════════════════════════════════════════════╣"
        echo "║ Esta llave SSH está casada exclusivamente con el equipo: '$DEV_NAME'       ║"
        echo "║ El Hardware UUID de tu computadora actual NO coincide. Acceso bloqueado.   ║"
        echo "╚════════════════════════════════════════════════════════════════════════════╝"
        echo ""
        exit 1
    fi
fi

# 2. If Ephemeral Guest Keychain Login, burn the temporary key immediately upon entry
if [ "$EXPECTED_HW" = "GUEST_EPHEMERAL" ]; then
    sudo sed -i '/GUEST_EPHEMERAL/d' /etc/openrig/authorized_keys 2>/dev/null || true
    echo "🔑 [OpenRig Guest Keychain] Pase efímero validado y destruido (no quedará rastro al salir)."
fi

# 3. Execute explicit command if non-interactive, otherwise do Session Takeover via tmux
if [ -n "${SSH_ORIGINAL_COMMAND:-}" ]; then
    exec zsh -ic "$SSH_ORIGINAL_COMMAND"
else
    echo "⚡ [OpenRig Session Takeover] Conectando a tu sesión viva en /workspace (desconectando pantallas previas)..."
    exec tmux new-session -A -D -s openrig -c /workspace "zsh -l"
fi
EOF
sudo chmod +x /usr/local/bin/rig-session-guard

# 6f. Install Device, Keychain & Resource Request Manager inside Container (rig-device & rig-request)
sudo tee /usr/local/bin/rig-request >/dev/null << 'EOF'
#!/usr/bin/env bash
set -e
REQ_FILE="/workspace/.openrig-hardware-request.json"
RAM="${1:?Uso: rig-request <nueva-ram-ej-8g> <nuevos-cpus-ej-4> [motivo]}"
CPUS="${2:?Uso: rig-request <nueva-ram-ej-8g> <nuevos-cpus-ej-4> [motivo]}"
shift 2 || true
REASON="${*:-Proyecto requiere mayor capacidad de compilacion}"

cat << EOR > "$REQ_FILE"
{
  "hostname": "$(hostname)",
  "requested_ram": "$RAM",
  "requested_cpus": "$CPUS",
  "reason": "$REASON",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOR
echo "📨 Solicitud de ampliación de hardware virtual enviada al Administrador del Servidor:"
echo "   • RAM solicitada:  $RAM"
echo "   • CPUs solicitados: $CPUS"
echo "   • Motivo:          $REASON"
echo "   (El Administrador puede aplicarla en caliente sin reiniciar tu sesión con: rig-server scale <usuario> --ram $RAM --cpus $CPUS)"
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
        echo "💻 Equipos casados por Hardware UUID a esta estación OpenRig:"
        echo "----------------------------------------------------------------------------"
        if [ ! -s "$AUTH_KEYS" ]; then
            echo "  (Ningún equipo vinculado todavía)"
        else
            grep -E "rig-session-guard" "$AUTH_KEYS" | while read -r line; do
                HW=$(echo "$line" | sed -n 's/.*rig-session-guard \([^ ]*\) \([^"]*\).*/\1/p')
                DEV=$(echo "$line" | sed -n 's/.*rig-session-guard \([^ ]*\) \([^"]*\).*/\2/p')
                echo "  🔒 Equipo: $DEV   | Hardware ID: ${HW:0:16}..."
            done
        fi
        ;;
    revoke|remove)
        TARGET_DEV="${1:?Uso: rig device revoke <nombre-equipo>}"
        sudo sed -i "/rig-session-guard [^ ]* ${TARGET_DEV}\"/d" "$AUTH_KEYS"
        echo "🗑️  Equipo '$TARGET_DEV' desvinculado y revocado inmediatamente."
        ;;
    keychain)
        if [ ! -f "$KEYCHAIN_FILE" ]; then
            head -c 10 /dev/urandom | base32 | tr -d '=' > "$KEYCHAIN_FILE"
            chmod 600 "$KEYCHAIN_FILE"
        fi
        SECRET=$(cat "$KEYCHAIN_FILE")
        URI="otpauth://totp/OpenRig:$(hostname)?secret=${SECRET}&issuer=OpenRig"
        echo "🔐 [OpenRig Guest Keychain] Agrega este Llavero a tu 1Password / Authenticator:"
        echo "   Secreto Base32 (TOTP): $SECRET"
        echo "   URI OTPAuth:           $URI"
        if command -v oathtool >/dev/null 2>&1; then
            echo "   Código actual (6 dígitos): $(oathtool --totp -b "$SECRET")"
        fi
        if command -v qrencode >/dev/null 2>&1; then
            qrencode -t ANSIUTF8 "$URI" || true
        fi
        ;;
    *)
        echo "Uso: rig device [list | revoke <equipo> | keychain]"
        ;;
esac
EOF
sudo chmod +x /usr/local/bin/rig-device

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
