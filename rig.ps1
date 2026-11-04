<#
.SYNOPSIS
OpenRig CLI for Windows (PowerShell & Command Prompt)
Zero-host-pollution modular developer, security & AI workstation.

Author: Luis Fernando Real (LFR-SnowBall) <luisitoreal01@gmail.com>
License: MIT
#>

param(
    [Parameter(Position=0)]
    [string]$Command = "help",
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ArgsRest
)

$ErrorActionPreference = "Continue"
$RigDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile = Join-Path $RigDir ".env"
$WorkspaceDir = Join-Path $RigDir "workspace"
$RigVersion = "1.2.0"
$versionFile = Join-Path $RigDir "VERSION"
if (Test-Path $versionFile) {
    $RigVersion = (Get-Content $versionFile -Raw).Trim()
}

function Show-Version {
    $gitHash = "release"
    if (Test-Path (Join-Path $RigDir ".git")) {
        $gitHash = (git -C $RigDir rev-parse --short HEAD 2>$null)
    }
    Write-Host "⚡ OpenRig v$RigVersion ($gitHash)" -ForegroundColor Cyan
}

function Invoke-Update {
    Write-Host "🔄 Checking for OpenRig updates..." -ForegroundColor Cyan
    if (Test-Path (Join-Path $RigDir ".git")) {
        git -C $RigDir fetch --tags origin 2>$null
        $localHash = (git -C $RigDir rev-parse HEAD 2>$null)
        $remoteHash = (git -C $RigDir rev-parse origin/main 2>$null)
        if ($localHash -and $localHash -eq $remoteHash) {
            Write-Host "✔ OpenRig is already up to date (v$RigVersion)." -ForegroundColor Green
        } else {
            Write-Host "📥 Pulling latest improvements..." -ForegroundColor Cyan
            git -C $RigDir pull --ff-only origin main
            if (Test-Path $versionFile) {
                $RigVersion = (Get-Content $versionFile -Raw).Trim()
            }
            Write-Host "✔ OpenRig updated successfully to v$RigVersion!" -ForegroundColor Green
        }
    } else {
        Write-Host "📥 Downloading latest OpenRig archive..." -ForegroundColor Cyan
        $zipTmp = Join-Path $env:TEMP "openrig-update.zip"
        Invoke-WebRequest -Uri "https://github.com/LFR-SnowBall/OpenRig/archive/refs/heads/main.zip" -OutFile $zipTmp
        Expand-Archive -Path $zipTmp -DestinationPath $env:TEMP -Force
        Copy-Item -Path (Join-Path $env:TEMP "OpenRig-main\*") -Destination $RigDir -Recurse -Force
        Remove-Item $zipTmp -Force
        Remove-Item (Join-Path $env:TEMP "OpenRig-main") -Recurse -Force
        Write-Host "✔ OpenRig updated successfully!" -ForegroundColor Green
    }

    # Refresh pre-warmed image if requested
    $refreshImage = ($ArgsRest.Count -gt 0 -and ($ArgsRest[0] -in "--image", "-i"))
    if ($refreshImage) {
        $role = "fullstack"
        if (Test-Path $EnvFile) {
            $roleLine = Get-Content $EnvFile | Where-Object { $_ -match "^OPENRIG_ROLE=" }
            if ($roleLine) { $role = ($roleLine -split "=")[1].Trim() }
        }
        Write-Host "🐳 Pulling latest image: ghcr.io/lfr-snowball/openrig:$role..." -ForegroundColor Cyan
        docker pull "ghcr.io/lfr-snowball/openrig:$role"
        docker tag "ghcr.io/lfr-snowball/openrig:$role" "openrig:$role"
        Write-Host "✔ Workstation image updated." -ForegroundColor Green
    }
}

function Show-Banner {
    Write-Host @"
╔══════════════════════════════════════════════════════════════════════════╗
║   ⚡ OPENRIG — PORTABLE MODULAR DEV, SEC & AI WORKSTATION (WINDOWS)      ║
║   Created by Luis Fernando Real (@LFR-SnowBall)                          ║
╚══════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
}

function Test-DockerDaemon {
    $null = docker info 2>$null
    if ($LASTEXITCODE -eq 0) { return $true }

    # Try auto-starting Rancher Desktop or Docker Desktop if installed
    $engineExePaths = @(
        "$env:LOCALAPPDATA\Programs\Rancher Desktop\Rancher Desktop.exe",
        "$env:ProgramFiles\Rancher Desktop\Rancher Desktop.exe",
        "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
        "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
        "$env:LOCALAPPDATA\Programs\Docker Desktop\Docker Desktop.exe"
    )
    $foundEngine = $engineExePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($foundEngine) {
        $engineName = if ($foundEngine -like "*Rancher*") { "Rancher Desktop" } else { "Docker Desktop" }
        Write-Host "⏳ Starting $engineName in background..." -ForegroundColor Cyan
        Start-Process -FilePath $foundEngine
        $retries = 0
        while ($retries -lt 25) {
            Start-Sleep -Seconds 2
            $null = docker info 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "✔ $engineName is active." -ForegroundColor Green
                return $true
            }
            $retries++
        }
    }
    Write-Host "❌ Container engine (Docker/Rancher) is not running. Please start your engine and try again." -ForegroundColor Red
    return $false
}

function Invoke-Setup {
    Show-Banner
    Write-Host "Select the Role Profile for your OpenRig Workstation:`n" -ForegroundColor White
    Write-Host "  1) 🐍 Backend Python     (pyenv + uv, multi-version Python, Django, Flask, FastAPI)"
    Write-Host "  2) ☕ Backend JVM        (SDKMAN!, Java 21/17, Kotlin, Spring Boot, Maven, Gradle)"
    Write-Host "  3) 🎨 Frontend & Web     (nvm, Node LTS, Vue.js, React, Vite, pnpm, Yarn, Bun)"
    Write-Host "  4) 📱 Mobile & Flutter   (Flutter, FVM, Dart, Android SDK CLI, ADB Wi-Fi/USB)"
    Write-Host "  5) 🛡️  DevSecOps & Pentest(nmap, nuclei, trivy, semgrep, gitleaks, sqlmap, AWS CLI)"
    Write-Host "  6) 🦾 Full-Stack Core    (Python + JVM + Node + Cloud + Security + AI CLIs)"
    Write-Host ""
    $choice = Read-Host "👉 Choose an option [1-6] (default: 6)"
    if ([string]::IsNullOrWhiteSpace($choice)) { $choice = "6" }

    $py = "false"; $jvm = "false"; $node = "false"; $mob = "false"; $sec = "false"; $role = "fullstack"
    switch ($choice) {
        "1" { $role = "backend-python"; $py = "true" }
        "2" { $role = "backend-jvm"; $jvm = "true" }
        "3" { $role = "frontend"; $node = "true" }
        "4" { $role = "mobile"; $jvm = "true"; $node = "true"; $mob = "true" }
        "5" { $role = "sec-devops"; $py = "true"; $sec = "true" }
        default { $role = "fullstack"; $py = "true"; $jvm = "true"; $node = "true"; $sec = "true" }
    }

    if (-not (Test-Path $WorkspaceDir)) {
        New-Item -ItemType Directory -Path $WorkspaceDir -Force | Out-Null
    }

    $wsPath = $WorkspaceDir -replace '\\','/'
    $content = @"
OPENRIG_ROLE=$role
INSTALL_PYTHON=$py
INSTALL_JVM=$jvm
INSTALL_NODE=$node
INSTALL_MOBILE=$mob
INSTALL_SWIFT=false
INSTALL_CLOUD=true
INSTALL_SEC=$sec
INSTALL_AI=true
PYTHON_DEFAULT_VERSION=3.12
NODE_DEFAULT_VERSION=22
JAVA_DEFAULT_VERSION=21.0.5-tem
CONTAINER_NAME=openrig
HOST_WORKSPACE_PATH=$wsPath
OPENRIG_SHELL=ohmyzsh
"@
    Set-Content -Path $EnvFile -Value $content -Encoding UTF8
    Write-Host "✅ Configuration saved to .env (Profile: $role). Run: rig up" -ForegroundColor Green
}

function Invoke-Up {
    if (-not (Test-Path $EnvFile)) { Invoke-Setup }
    if (-not (Test-DockerDaemon)) { return }

    if (-not (Test-Path $WorkspaceDir)) {
        New-Item -ItemType Directory -Path $WorkspaceDir -Force | Out-Null
    }

    # Ensure host .gitconfig exists to prevent Docker from creating it as a directory
    $gitConfig = Join-Path $HOME ".gitconfig"
    if (-not (Test-Path $gitConfig)) {
        New-Item -ItemType File -Path $gitConfig -Force | Out-Null
    }

    Write-Host "🚀 Launching OpenRig workstation containers..." -ForegroundColor Cyan
    docker compose -f "$RigDir\docker-compose.yml" --env-file "$EnvFile" up -d $ArgsRest

    if ($LASTEXITCODE -ne 0) {
        Write-Host "❌ Failed to start OpenRig containers." -ForegroundColor Red
        return
    }

    # Configure zero-popup Local IDE SSH Bridge
    $openrigHome = Join-Path $HOME ".openrig"
    $sshHome = Join-Path $HOME ".ssh"
    if (-not (Test-Path $openrigHome)) { New-Item -ItemType Directory -Path $openrigHome -Force | Out-Null }
    if (-not (Test-Path $sshHome)) { New-Item -ItemType Directory -Path $sshHome -Force | Out-Null }

    $ideKey = Join-Path $openrigHome "local_ide_ed25519"
    if (-not (Test-Path $ideKey)) {
        ssh-keygen -t ed25519 -f $ideKey -N '""' -C "openrig-local-ide" 2>$null | Out-Null
    }

    if (Test-Path "$ideKey.pub") {
        $idePub = (Get-Content "$ideKey.pub" -Raw).Trim()
        docker exec -u root openrig bash -c "mkdir -p /etc/openrig /home/rig/.ssh /run/sshd && echo '$idePub' > /etc/openrig/authorized_keys && echo '$idePub' > /home/rig/.ssh/authorized_keys && chown root:root /etc/openrig/authorized_keys && chmod 644 /etc/openrig/authorized_keys && chown -R rig:rig /home/rig/.ssh && chmod 700 /home/rig/.ssh && chmod 600 /home/rig/.ssh/authorized_keys && (pgrep -x sshd >/dev/null || /usr/sbin/sshd)" 2>$null | Out-Null
    }

    # Register 'Host openrig' in ~/.ssh/config
    $sshConfigFile = Join-Path $sshHome "config"
    $sshConfigContent = if (Test-Path $sshConfigFile) { Get-Content $sshConfigFile -Raw } else { "" }
    if ($sshConfigContent -notmatch "Host\s+openrig\b") {
        $ideKeyPosix = $ideKey -replace '\\','/'
        $openrigBlock = @"

Host openrig
    HostName 127.0.0.1
    Port 2222
    User rig
    IdentityFile $ideKeyPosix
    IdentitiesOnly yes
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
    LogLevel ERROR
"@
        Add-Content -Path $sshConfigFile -Value $openrigBlock
    }

    Write-Host "`n✅ OpenRig is running!" -ForegroundColor Green
    Write-Host "  👉 Terminal access:   rig shell" -ForegroundColor White
    Write-Host "  👉 Open in IDE:       rig ide ." -ForegroundColor White
    Write-Host "  👉 Encrypted backup:  rig backup create" -ForegroundColor White
    Write-Host "  👉 Stop and free RAM: rig down`n" -ForegroundColor White
}

function Get-ActiveContext {
    $ctxFile = Join-Path $HOME ".openrig\context"
    if (Test-Path $ctxFile) {
        return (Get-Content $ctxFile -Raw).Trim()
    }
    return "local"
}

function Invoke-Context {
    $sub = if ($ArgsRest.Count -gt 0) { $ArgsRest[0] } else { "show" }
    $ctxFile = Join-Path $HOME ".openrig\context"
    $openrigDir = Join-Path $HOME ".openrig"
    if (-not (Test-Path $openrigDir)) { New-Item -ItemType Directory -Path $openrigDir -Force | Out-Null }

    switch ($sub.ToLower()) {
        { $_ -in "show", "status", "current" } {
            $curr = Get-ActiveContext
            if ($curr -eq "local") {
                Write-Host "🎯 Active context: local (Local container on this PC)" -ForegroundColor Green
            } else {
                $target = $curr -replace '^server:', ''
                Write-Host "🎯 Active context: server ($target)" -ForegroundColor Cyan
                Write-Host "   Commands like 'rig shell' and 'rig ide' currently target this remote server." -ForegroundColor Gray
            }
        }
        "use" {
            $targetType = if ($ArgsRest.Count -gt 1) { $ArgsRest[1] } else { "local" }
            if ($targetType -eq "local") {
                Set-Content -Path $ctxFile -Value "local" -Encoding UTF8
                Write-Host "✔ Context switched to: local ('rig shell' and 'rig ide' now target your local container)." -ForegroundColor Green
            } else {
                $srv = if ($targetType -in "server", "remote") {
                    if ($ArgsRest.Count -gt 2) { $ArgsRest[2] } else { "" }
                } else {
                    $targetType
                }
                if ([string]::IsNullOrWhiteSpace($srv)) {
                    Write-Host "Usage: rig context use server <ip[:port]> [username]" -ForegroundColor Red
                    return
                }
                $srvUser = if ($ArgsRest.Count -gt 3) { $ArgsRest[3] } else { "rig" }
                $parts = $srv -split ":"
                $hostIp = $parts[0]
                $port = if ($parts.Count -gt 1) { $parts[1] } else { "2201" }

                Set-Content -Path $ctxFile -Value "server:$hostIp:$port:$srvUser" -Encoding UTF8
                Write-Host "✔ Context switched to: server ($hostIp`:$port, user: $srvUser)" -ForegroundColor Green
                Write-Host "   👉 'rig shell' will now connect to this server." -ForegroundColor White
                Write-Host "   👉 'rig ide .' will open your remote workspace." -ForegroundColor White
                Write-Host "   👉 Return to local anytime with: rig context use local" -ForegroundColor Cyan
            }
        }
        { $_ -in "list", "ls" } {
            $curr = Get-ActiveContext
            Write-Host "Available OpenRig Contexts:" -ForegroundColor White
            if ($curr -eq "local") {
                Write-Host "  * local       (Active: Local container on this PC)" -ForegroundColor Green
            } else {
                Write-Host "    local       (Local container on this PC)" -ForegroundColor Gray
            }
            if ($curr -like "server:*") {
                $target = $curr -replace '^server:', ''
                Write-Host "  * server      (Active: $target)" -ForegroundColor Cyan
            }
        }
        default {
            Write-Host "🎯 OpenRig Context Switcher:" -ForegroundColor Cyan
            Write-Host "  rig context                             -> Show currently active context (local vs server)"
            Write-Host "  rig context use local                   -> Target your local container workstation"
            Write-Host "  rig context use server <ip:port> [user] -> Target remote OpenRig-Server on your network"
            Write-Host "  rig context list                        -> List configured contexts"
        }
    }
}

function Invoke-Ide {
    $remotePath = if ($ArgsRest.Count -gt 0) { $ArgsRest[0] } else { "/workspace" }
    if ($remotePath -eq ".") { $remotePath = "/workspace" }
    if (-not $remotePath.StartsWith("/")) { $remotePath = "/workspace/$remotePath" }

    $curr = Get-ActiveContext
    if ($curr -like "server:*") {
        $target = $curr -replace '^server:', ''
        $parts = $target -split ":"
        $hostIp = $parts[0]
        $port = if ($parts.Count -gt 1) { $parts[1] } else { "2201" }
        $user = if ($parts.Count -gt 2) { $parts[2] } else { "rig" }
        Write-Host "📡 Active context is SERVER ($hostIp`:$port). Opening remote workspace..." -ForegroundColor Cyan

        $aliasName = "openrig-$user"
        $sshHome = Join-Path $HOME ".ssh"
        if (-not (Test-Path $sshHome)) { New-Item -ItemType Directory -Path $sshHome -Force | Out-Null }
        $sshConfigFile = Join-Path $sshHome "config"
        $sshConfigContent = if (Test-Path $sshConfigFile) { Get-Content $sshConfigFile -Raw } else { "" }
        if ($sshConfigContent -notmatch "Host\s+$aliasName\b") {
            $aliasBlock = @"

Host $aliasName
    HostName $hostIp
    Port $port
    User $user
    ForwardAgent yes
    LocalForward 3000 127.0.0.1:3000
    LocalForward 5173 127.0.0.1:5173
    LocalForward 8000 127.0.0.1:8000
    LocalForward 8080 127.0.0.1:8080
"@
            Add-Content -Path $sshConfigFile -Value $aliasBlock
        }

        $folderUri = "vscode-remote://ssh-remote+$aliasName$remotePath"
        $codePaths = @(
            "antigravity-ide",
            "cursor",
            "code",
            "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
            "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
            "$env:LOCALAPPDATA\Programs\Antigravity IDE\bin\antigravity-ide.cmd"
        )
        $ideExecutable = $null
        foreach ($cand in $codePaths) {
            if (Get-Command $cand -ErrorAction SilentlyContinue) { $ideExecutable = $cand; break }
            if (Test-Path $cand) { $ideExecutable = $cand; break }
        }
        if ($ideExecutable) {
            Write-Host "🚀 Launching IDE ($ideExecutable) connected to '$aliasName`:$remotePath'..." -ForegroundColor Cyan
            Start-Process -FilePath $ideExecutable -ArgumentList "--folder-uri `"$folderUri`""
        } else {
            Write-Host "ℹ️ Connect your IDE via Remote-SSH to '$aliasName' and open '$remotePath'." -ForegroundColor Yellow
        }
        return
    }

    # Check if openrig container is running
    $running = docker ps --filter "name=^openrig$" --format "{{.Names}}" 2>$null
    if (-not $running) { Invoke-Up }

    # Detect installed IDEs on Windows
    $codePaths = @(
        "antigravity-ide",
        "cursor",
        "code",
        "$env:LOCALAPPDATA\Programs\Microsoft VS Code\bin\code.cmd",
        "$env:LOCALAPPDATA\Programs\cursor\Cursor.exe",
        "$env:LOCALAPPDATA\Programs\Antigravity IDE\bin\antigravity-ide.cmd"
    )

    $ideExecutable = $null
    foreach ($cand in $codePaths) {
        if (Get-Command $cand -ErrorAction SilentlyContinue) {
            $ideExecutable = $cand
            break
        }
        if (Test-Path $cand) {
            $ideExecutable = $cand
            break
        }
    }

    $folderUri = "vscode-remote://ssh-remote+openrig$remotePath"
    if ($ideExecutable) {
        Write-Host "🚀 Launching IDE ($ideExecutable) connected to 'openrig:$remotePath'..." -ForegroundColor Cyan
        Start-Process -FilePath $ideExecutable -ArgumentList "--folder-uri `"$folderUri`""
    } else {
        Write-Host "ℹ️ Connect your IDE via Remote-SSH extension to 'openrig' and open '$remotePath'." -ForegroundColor Yellow
        Write-Host "   URI: $folderUri" -ForegroundColor White
    }
}

function Invoke-Backup {
    $sub = if ($ArgsRest.Count -gt 0) { $ArgsRest[0] } else { "help" }
    switch ($sub) {
        { $_ -in "create", "export" } {
            $outFile = if ($ArgsRest.Count -gt 1) { $ArgsRest[1] } else { "" }
            if ([string]::IsNullOrWhiteSpace($outFile)) {
                $ts = Get-Date -Format "yyyyMMdd_HHmmss"
                $outFile = Join-Path $RigDir "openrig-backup-$ts.rigpack"
            }

            Write-Host "🔐 Setting up AES-256 Military Grade Encryption for this backup:" -ForegroundColor Cyan
            $pass1 = Read-Host "Enter backup encryption password" -AsSecureString
            $pass2 = Read-Host "Confirm backup encryption password" -AsSecureString
            $bstr1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass1)
            $bstr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass2)
            $plain1 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr1)
            $plain2 = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr2)

            if ($plain1 -ne $plain2 -or [string]::IsNullOrWhiteSpace($plain1)) {
                Write-Host "❌ Passwords do not match or are empty. Backup aborted." -ForegroundColor Red
                return
            }

            Write-Host "📦 Creating encrypted workstation bundle: $outFile..." -ForegroundColor Cyan
            $tempDir = Join-Path $env:TEMP ("openrig-backup-" + [Guid]::NewGuid().ToString().Substring(0,8))
            $payloadDir = Join-Path $tempDir "payload"
            New-Item -ItemType Directory -Path (Join-Path $payloadDir "workspace") -Force | Out-Null

            if (Test-Path $EnvFile) { Copy-Item $EnvFile (Join-Path $payloadDir ".env") }
            if (Test-Path $WorkspaceDir) {
                # Copy workspace excluding large cache directories
                robocopy $WorkspaceDir (Join-Path $payloadDir "workspace") /E /XD node_modules target .gradle .cache dist build .venv venv __pycache__ /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
            }

            $profilesDir = Join-Path $HOME ".openrig-profiles"
            if (Test-Path $profilesDir) {
                robocopy $profilesDir (Join-Path $payloadDir ".openrig-profiles") /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
            }

            $tarExe = "tar.exe"
            $opensslExe = (Get-Command openssl -ErrorAction SilentlyContinue).Source
            if (-not $opensslExe -and (Test-Path "C:\Program Files\Git\usr\bin\openssl.exe")) {
                $opensslExe = "C:\Program Files\Git\usr\bin\openssl.exe"
            }

            if ($opensslExe) {
                & $tarExe -czf - -C $payloadDir . | & $opensslExe enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -out "$outFile" -pass "pass:$plain1"
            } else {
                # Use container's OpenSSL if host lacks native OpenSSL
                $wsOut = "/workspace/" + (Split-Path $outFile -Leaf)
                docker run --rm -v "${payloadDir}:/stage:ro" -v "${WorkspaceDir}:/workspace" ubuntu:24.04 bash -c "apt-get update -qq && apt-get install -y -qq openssl tar >/dev/null 2>&1 && tar -czf - -C /stage . | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -out '$wsOut' -pass 'pass:$plain1'"
                $createdInWs = Join-Path $WorkspaceDir (Split-Path $outFile -Leaf)
                if (Test-Path $createdInWs -and $outFile -ne $createdInWs) {
                    Move-Item $createdInWs $outFile -Force
                }
            }

            Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "✅ Encrypted backup created successfully: $outFile" -ForegroundColor Green
            Write-Host "   • Cipher: AES-256-CBC with PBKDF2 (100,000 iterations)" -ForegroundColor White
            Write-Host "   • To restore on any machine: rig backup restore `"$outFile`"" -ForegroundColor Cyan
        }

        { $_ -in "restore", "import" } {
            $inFile = if ($ArgsRest.Count -gt 1) { $ArgsRest[1] } else { "" }
            if ([string]::IsNullOrWhiteSpace($inFile) -or -not (Test-Path $inFile)) {
                Write-Host "Usage: rig backup restore <path\to\file.rigpack>" -ForegroundColor Red
                return
            }

            $pass = Read-Host "🔐 Enter AES-256 password to decrypt $inFile" -AsSecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)

            Write-Host "🔓 Verifying integrity and decrypting workstation bundle..." -ForegroundColor Cyan
            $restoreTmp = Join-Path $env:TEMP ("openrig-restore-" + [Guid]::NewGuid().ToString().Substring(0,8))
            New-Item -ItemType Directory -Path $restoreTmp -Force | Out-Null

            $opensslExe = (Get-Command openssl -ErrorAction SilentlyContinue).Source
            if (-not $opensslExe -and (Test-Path "C:\Program Files\Git\usr\bin\openssl.exe")) {
                $opensslExe = "C:\Program Files\Git\usr\bin\openssl.exe"
            }

            if ($opensslExe) {
                & $opensslExe enc -d -aes-256-cbc -pbkdf2 -iter 100000 -in "$inFile" -pass "pass:$plain" | & tar.exe -xzf - -C $restoreTmp
            } else {
                $fileLeaf = Split-Path $inFile -Leaf
                Copy-Item $inFile (Join-Path $WorkspaceDir $fileLeaf) -Force
                docker run --rm -v "${restoreTmp}:/restore" -v "${WorkspaceDir}:/workspace" ubuntu:24.04 bash -c "apt-get update -qq && apt-get install -y -qq openssl tar >/dev/null 2>&1 && openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -in '/workspace/$fileLeaf' -pass 'pass:$plain' | tar -xzf - -C /restore"
                Remove-Item (Join-Path $WorkspaceDir $fileLeaf) -Force -ErrorAction SilentlyContinue
            }

            # Copy restored files
            $restoredEnv = Join-Path $restoreTmp ".env"
            if (Test-Path $restoredEnv) {
                Copy-Item $restoredEnv $EnvFile -Force
                Write-Host "  ✔ Restored environment profile (.env)" -ForegroundColor Green
            }

            $restoredWs = Join-Path $restoreTmp "workspace"
            if (Test-Path $restoredWs) {
                robocopy $restoredWs $WorkspaceDir /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
                Write-Host "  ✔ Restored projects and repositories to .\workspace" -ForegroundColor Green
            }

            $restoredProf = Join-Path $restoreTmp ".openrig-profiles"
            if (Test-Path $restoredProf) {
                $targetProf = Join-Path $HOME ".openrig-profiles"
                robocopy $restoredProf $targetProf /E /NFL /NDL /NJH /NJS /nc /ns /np | Out-Null
                Write-Host "  ✔ Restored multi-client identities and Git profiles" -ForegroundColor Green
            }

            Remove-Item $restoreTmp -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "🎉 Workstation restored successfully! Launch with: rig up" -ForegroundColor Green
        }

        default {
            Write-Host "📦 OpenRig Secure Encrypted Backup & Restore (AES-256-CBC PBKDF2):" -ForegroundColor Cyan
            Write-Host "  rig backup create [file.rigpack]"
            Write-Host "  rig backup restore <file.rigpack>"
        }
    }
}

function Invoke-Migrate {
    $sub = if ($ArgsRest.Count -gt 0) { $ArgsRest[0] } else { "help" }
    switch ($sub) {
        "push" {
            $target = if ($ArgsRest.Count -gt 1) { $ArgsRest[1] } else { "" }
            if ([string]::IsNullOrWhiteSpace($target)) {
                Write-Host "Usage: rig migrate push <server_ip[:port]> [username]" -ForegroundColor Red
                return
            }
            $user = if ($ArgsRest.Count -gt 2) { $ArgsRest[2] } else { "rig" }
            $parts = $target -split ":"
            $hostIp = $parts[0]
            $port = if ($parts.Count -gt 1) { $parts[1] } else { "2201" }

            Write-Host "🚀 Migrating local OpenRig workspace to remote server ($hostIp`:$port)..." -ForegroundColor Cyan
            $pass = Read-Host "🔐 Set AES-256 encryption password for network stream" -AsSecureString
            $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass)
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr)

            $remoteCmd = "mkdir -p /workspace && openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 -pass 'pass:$plain' | tar -xzf - -C /workspace"

            $opensslExe = (Get-Command openssl -ErrorAction SilentlyContinue).Source
            if (-not $opensslExe -and (Test-Path "C:\Program Files\Git\usr\bin\openssl.exe")) {
                $opensslExe = "C:\Program Files\Git\usr\bin\openssl.exe"
            }

            if ($opensslExe) {
                & tar.exe -czf - -C $WorkspaceDir --exclude="node_modules" --exclude="target" --exclude=".gradle" --exclude=".cache" --exclude="dist" --exclude="build" --exclude=".venv" . | & $opensslExe enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -pass "pass:$plain" | ssh -p $port "$user@$hostIp" "$remoteCmd"
            } else {
                docker exec openrig bash -c "tar -czf - -C /workspace --exclude='node_modules' --exclude='target' --exclude='.gradle' --exclude='.cache' --exclude='dist' --exclude='build' --exclude='.venv' . | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 -salt -pass 'pass:$plain'" | ssh -p $port "$user@$hostIp" "$remoteCmd"
            }

            if ($LASTEXITCODE -eq 0) {
                Write-Host "🎉 Migration complete! Workspace successfully transferred to $hostIp." -ForegroundColor Green
                Write-Host "👉 Connect anytime with: rig connect $hostIp`:$port $user" -ForegroundColor Cyan
            } else {
                Write-Host "❌ Migration failed. Verify network connection and SSH credentials." -ForegroundColor Red
            }
        }
        default {
            Write-Host "📡 OpenRig Live Network Migration:" -ForegroundColor Cyan
            Write-Host "  rig migrate push <server_ip[:port]> [username]"
        }
    }
}

function Invoke-Lock {
    Write-Host "🔒 Activating Anti-Malware Sandbox Mode inside 'openrig'..." -ForegroundColor Cyan
    docker exec -u root openrig bash -c '
        if [ -S /var/run/docker.sock ]; then chmod 600 /var/run/docker.sock; fi
        if [ -d /var/openrig-vault ]; then chmod 000 /var/openrig-vault; fi
        deluser rig sudo 2>/dev/null || gpasswd -d rig sudo 2>/dev/null || true
        rm -f /etc/sudoers.d/rig
    '
    Write-Host "✅ Workstation JAILED (Sandbox Mode active):" -ForegroundColor Green
    Write-Host "   • Docker Socket locked (0600 root:root)."
    Write-Host "   • Sudo privileges revoked inside the container."
    Write-Host "   👉 To restore privileges from Windows host run: rig unlock" -ForegroundColor White
}

function Invoke-Unlock {
    Write-Host "🔓 Restoring workstation privileges in 'openrig' from Windows Host..." -ForegroundColor Cyan
    docker exec -u root openrig bash -c '
        if [ -S /var/run/docker.sock ]; then chmod 666 /var/run/docker.sock; fi
        if [ -d /var/openrig-vault ]; then chmod 755 /var/openrig-vault; fi
        usermod -aG sudo rig 2>/dev/null || true
        echo "rig ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/rig
        chmod 440 /etc/sudoers.d/rig
    '
    Write-Host "✅ Docker and sudo privileges restored in 'openrig'." -ForegroundColor Green
}

# CLI Action Dispatcher
switch ($Command.ToLower()) {
    { $_ -in "setup", "init" }       { Invoke-Setup }
    { $_ -in "up", "start" }         { Invoke-Up }
    { $_ -in "shell", "enter" }      {
        $curr = Get-ActiveContext
        if ($curr -like "server:*") {
            $target = $curr -replace '^server:', ''
            $parts = $target -split ":"
            $hostIp = $parts[0]
            $port = if ($parts.Count -gt 1) { $parts[1] } else { "2201" }
            $user = if ($parts.Count -gt 2) { $parts[2] } else { "rig" }
            Write-Host "📡 Active context is SERVER ($hostIp`:$port). Connecting..." -ForegroundColor Cyan
            ssh -A -p $port -L 3000:127.0.0.1:3000 -L 5173:127.0.0.1:5173 -L 8000:127.0.0.1:8000 -L 8080:127.0.0.1:8080 "$user@$hostIp"
            return
        }
        $running = docker ps --filter "name=^openrig$" --format "{{.Names}}" 2>$null
        if (-not $running) { Invoke-Up }
        docker exec -it openrig zsh -l
    }
    { $_ -in "context", "ctx" }      { Invoke-Context }
    { $_ -in "ide", "code", "agy" }  { Invoke-Ide }
    { $_ -in "backup" }              { Invoke-Backup }
    { $_ -in "migrate" }             { Invoke-Migrate }
    { $_ -in "lock", "sandbox" }     { Invoke-Lock }
    { $_ -in "unlock" }              { Invoke-Unlock }
    { $_ -in "service", "svc" }      {
        $sub = if ($ArgsRest.Count -gt 0) { $ArgsRest[0] } else { "help" }
        $svcArgs = if ($ArgsRest.Count -gt 1) { $ArgsRest[1..($ArgsRest.Count-1)] } else { @() }
        switch ($sub) {
            "up"   { docker compose -f "$RigDir\docker-compose.yml" --env-file "$EnvFile" up -d $svcArgs }
            "down" { docker compose -f "$RigDir\docker-compose.yml" --env-file "$EnvFile" stop $svcArgs }
            default {
                Write-Host "Usage: rig service up [postgres|redis|localstack]"
                Write-Host "       rig service down [postgres|redis|localstack]"
            }
        }
    }
    { $_ -in "phone", "adb" }        { docker exec -it openrig rig-phone $ArgsRest }
    { $_ -in "sec", "audit" }        { docker exec -it openrig rig-sec $ArgsRest }
    { $_ -in "vpn" }                 { docker exec -it openrig rig-vpn $ArgsRest }
    { $_ -in "profile", "prof" }     { docker exec -it openrig rig-profile $ArgsRest }
    { $_ -in "share", "tunnel" }     { docker exec -it openrig rig-share $ArgsRest }
    { $_ -in "device", "dev" }       { docker exec -it openrig rig-device $ArgsRest }
    { $_ -in "request", "req" }      { docker exec -it openrig rig-request $ArgsRest }
    { $_ -in "brain" }               { docker exec -it openrig rig-brain $ArgsRest }
    { $_ -in "ai" }                  { docker exec -it openrig rig-ai $ArgsRest }
    { $_ -in "join", "enroll" }      { docker exec -it openrig rig-join $ArgsRest }
    { $_ -in "guest" }               { docker exec -it openrig rig-guest $ArgsRest }
    { $_ -in "connect", "remote" }   {
        $target = $ArgsRest[0]
        $parts = $target -split ":"
        $hostIp = $parts[0]
        $port = if ($parts.Count -gt 1) { $parts[1] } else { "2201" }
        ssh -A -p $port -L 3000:127.0.0.1:3000 -L 5173:127.0.0.1:5173 -L 8000:127.0.0.1:8000 -L 8080:127.0.0.1:8080 "rig@$hostIp"
    }
    { $_ -in "snapshot", "snap" }    {
        $sub = if ($ArgsRest.Count -gt 0) { $ArgsRest[0] } else { "list" }
        $tag = if ($ArgsRest.Count -gt 1) { $ArgsRest[1] } else { "latest" }
        switch ($sub) {
            "save"    { docker commit openrig "openrig-snapshot:$tag" | Out-Null; Write-Host "✅ Snapshot openrig-snapshot:$tag saved." -ForegroundColor Green }
            "restore" { docker tag "openrig-snapshot:$tag" "openrig:fullstack"; docker compose -f "$RigDir\docker-compose.yml" --env-file "$EnvFile" up -d --force-recreate }
            default   { docker images "openrig-snapshot" }
        }
    }
    { $_ -in "down", "stop" }        {
        Write-Host "🛑 Stopping OpenRig and freeing 100% of RAM/CPU..." -ForegroundColor Yellow
        docker compose -f "$RigDir\docker-compose.yml" --profile services down
        Write-Host "✅ System resources freed." -ForegroundColor Green
    }
    { $_ -in "uninstall", "nuke" }   {
        Write-Host "🗑️ Uninstalling OpenRig containers and image..." -ForegroundColor Yellow
        docker compose -f "$RigDir\docker-compose.yml" --profile services down --rmi all -v 2>$null
        docker builder prune -f 2>$null | Out-Null
        Write-Host "✅ OpenRig uninstalled (your projects in .\workspace remain untouched)." -ForegroundColor Green
    }
    { $_ -in "status", "ps" }        {
        Show-Banner
        docker ps --filter "network=openrig-net"
    }
    { $_ -in "update", "upgrade" }   { Invoke-Update }
    { $_ -in "version", "-v", "--version" } { Show-Version }
    default {
        Show-Banner
        Write-Host "Commands:" -ForegroundColor Cyan
        Write-Host "  rig setup                         -> Configure Role Profile and modules"
        Write-Host "  rig up                            -> Build and start OpenRig"
        Write-Host "  rig shell                         -> Open interactive terminal inside OpenRig"
        Write-Host "  rig ide [path]                    -> Launch Antigravity IDE / VS Code attached to OpenRig"
        Write-Host "  rig backup create [file.rigpack]  -> Encrypted AES-256 backup of workspace & profiles"
        Write-Host "  rig backup restore <file.rigpack> -> Decrypt and restore backup onto this machine"
        Write-Host "  rig migrate push <server:port>    -> Live stream encrypted workspace to OpenRig-Server"
        Write-Host "  rig context [show|use|list]       -> Switch active target (local vs remote server)"
        Write-Host "  rig update [--image]              -> Update OpenRig to the latest version from GitHub"
        Write-Host "  rig version                       -> Print current OpenRig version and commit hash"
        Write-Host "  rig lock / rig unlock             -> Toggle Anti-Malware Sandbox Mode"
        Write-Host "  rig service up/down <svc>         -> Run sibling containers (postgres, redis, localstack)"
        Write-Host "  rig status                        -> View running OpenRig containers"
        Write-Host "  rig down                          -> Stop containers and free 100% of RAM/CPU"
    }
}
