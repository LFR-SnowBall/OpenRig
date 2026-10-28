# 🛡️ Security Policy & Red-Team Architecture (`OpenRig`)

OpenRig is designed with a **Defense-in-Depth / Zero-Trust** security model covering both **Personal Workstation Mode** (local laptop/PC) and **Enterprise Multi-Tenant Server Mode** (`OpenRig-Server`).

---

## 🔒 1. Personal Workstation Mode Protections

| Threat Vector | Mitigation Implemented | Verification Command |
|---|---|---|
| **Public Wi-Fi / LAN Port Scanning & Debugger RCE** | All exposed development (`3000`, `5173`, `8000`, `8080`) and remote debugger (`5005` JDWP, `5678` debugpy, `9229` Node Inspector, `5432` Postgres, `6379` Redis) ports are strictly bound to **`127.0.0.1`** in `docker-compose.yml`. | `docker port openrig` |
| **Supply-Chain Malware Stealing `~/.ssh` Private Keys** | `${HOME}/.ssh` is **never mounted** inside the container. Only public metadata (`*.pub`, `known_hosts`, `allowed_signers`) is copied at startup; all cryptographic operations happen outside the container via the Host's **1Password SSH Agent** (`/ssh-agent`). | `docker exec openrig ls -la /home/rig/.ssh` |
| **Supply-Chain Malware Escaping via `/var/run/docker.sock` or `sudo`** | The Host-enforced **`rig lock`** command sets `/var/run/docker.sock` to `0600 root:root` and revokes `sudo` inside the container before running untrusted `npm install` or `pip install` scripts. Only the Host OS can restore privileges via **`rig unlock`**. | `./rig lock && docker exec openrig docker ps` |
| **Unnecessary Network Daemons (`sshd`)** | `sshd` is **disabled by default** in Personal Workstation Mode (`OPENRIG_SSH_SERVER=false`). | `docker exec openrig pgrep -a sshd` |

---

## 🏢 2. Multi-Tenant Server Mode Protections (`OpenRig-Server`)

| Threat Vector | Mitigation Implemented |
|---|---|
| **Bypassing `/usr/local/bin/rig-session-guard`** | `sshd_config` sets `AuthorizedKeysFile /etc/openrig/authorized_keys` owned by **`root:root` (`0644`)**. Non-root users inside the container cannot modify or remove the forced command guard. |
| **Stolen SSH Key (`device_ed25519`) Used on Another Machine** | 1. The private key `~/.openrig/device_ed25519` is encrypted at rest using a passphrase derived dynamically from the client's physical Motherboard/SoC UUID (`IOPlatformUUID` / `/etc/machine-id`) via `SSH_ASKPASS`.<br>2. `OPENRIG_HW_ID` is computed dynamically in RAM during `rig connect` (never stored in `~/.ssh/config`) and verified by `rig-session-guard` on the server. |
| **Brute-Force & TOTP Replay Attacks on Gatekeeper (`:7070`)** | 1. **IP Rate-Limiting:** 5 failed enrollment or guest attempts block the source IP for 15 minutes (`HTTP 429`).<br>2. **Anti-Replay TOTP:** Every 6-digit Keychain TOTP code is burned immediately upon first use (`USED_TOTP_CODES`).<br>3. **Strict Input Regex:** `^[a-zA-Z0-9_-]{1,32}$` prevents shell injection. |
| **Multi-Tenant Container Escape & Fork Bombs** | User containers (`openrig-user-<name>`) do **not** mount the server's `/var/run/docker.sock`, run on isolated per-user Docker networks (`openrig-net-<name>`), and enforce strict RAM (`--memory`), CPU (`--cpus`), and process (`--pids-limit 512`) quotas. |

---

## 📬 Reporting a Vulnerability

If you discover a security vulnerability in `OpenRig` or `OpenRig-Server`, please report it privately to:
- **Luis Fernando Real (`LFR-SnowBall`)** — `luisitoreal01@gmail.com`
