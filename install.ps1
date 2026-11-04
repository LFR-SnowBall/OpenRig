<#
.SYNOPSIS
⚡ OpenRig Universal Bootstrapper & Installer for Windows
Single-line installation:
  irm https://raw.githubusercontent.com/LFR-SnowBall/OpenRig/main/install.ps1 | iex

Author: Luis Fernando Real (LFR-SnowBall) <luisitoreal01@gmail.com>
License: MIT
#>

param(
    [string]$Role = "fullstack",
    [string]$Engine = "",
    [string]$InstallDir = (Join-Path $HOME ".openrig"),
    [switch]$NoStart,
    [switch]$Yes
)

$ErrorActionPreference = "Continue"

function Show-Banner {
    Write-Host @"
  ___                    ____  _       
 / _ \ _ __   ___ _ __  |  _ \(_) __ _ 
| | | | '_ \ / _ \ '_ \ | |_) | |/ _` |
| |_| | |_) |  __/ | | ||  _ <| | (_| |
 \___/| .__/ \___|_| |_||_| \_\_|\__, |
      |_|                        |___/ 
 Zero-Footprint Modular Dev, Sec & AI Workstation (Windows)
"@ -ForegroundColor Cyan
}

function Wait-ForDocker {
    Write-Host "⏳ Waiting for container engine daemon to initialize..." -NoNewline -ForegroundColor Yellow
    $retries = 0
    while ($retries -lt 30) {
        Start-Sleep -Seconds 2
        Write-Host "." -NoNewline -ForegroundColor Yellow
        try {
            $null = docker info 2>$null
            if ($LASTEXITCODE -eq 0) {
                Write-Host "`n✔ Container engine is ready!" -ForegroundColor Green
                return $true
            }
        } catch {}
        $retries++
    }
    Write-Host "`n⚠️ Container engine is initializing in background. It will be ready shortly." -ForegroundColor Yellow
    return $false
}

Show-Banner

# 1. Check Windows Subsystem for Linux (WSL2)
Write-Host "`n🐧 Checking Windows Subsystem for Linux (WSL2)..." -ForegroundColor White
$wslNeedsInstall = $false
try {
    $wslCheck = wsl.exe --status 2>&1
    if ($LASTEXITCODE -ne 0 -and $wslCheck -notmatch "Default Version") {
        $wslNeedsInstall = $true
    }
} catch {
    $wslNeedsInstall = $true
}

if ($wslNeedsInstall) {
    Write-Host "⚠️ WSL2 is required by container engines on Windows." -ForegroundColor Yellow
    Write-Host "📦 Installing/Updating WSL2 engine..." -ForegroundColor Cyan
    try {
        Start-Process -FilePath "wsl.exe" -ArgumentList "--install --no-distribution" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        Start-Process -FilePath "wsl.exe" -ArgumentList "--update" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        Start-Process -FilePath "wsl.exe" -ArgumentList "--set-default-version 2" -Wait -NoNewWindow -ErrorAction SilentlyContinue
        Write-Host "✔ WSL2 kernel and components configured." -ForegroundColor Green
    } catch {
        Write-Host "ℹ️ Enabling VirtualMachinePlatform and WSL features via dism..." -ForegroundColor Yellow
        dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart 2>$null | Out-Null
        dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart 2>$null | Out-Null
    }
} else {
    Write-Host "✔ WSL2 is active and available." -ForegroundColor Green
}

# 2. Check Container Engine (Rancher Desktop vs Docker Desktop on Windows)
Write-Host "`n🐳 Checking Container Engine..." -ForegroundColor White
$dockerRunning = $false
try {
    $null = docker info 2>$null
    if ($LASTEXITCODE -eq 0) {
        $dockerRunning = $true
        $serverVersion = (docker version --format '{{.Server.Version}}' 2>$null)
        Write-Host "✔ Active container engine detected: $serverVersion" -ForegroundColor Green
    }
} catch {
    $dockerRunning = $false
}

$rancherPaths = @(
    "$env:LOCALAPPDATA\Programs\Rancher Desktop\Rancher Desktop.exe",
    "$env:ProgramFiles\Rancher Desktop\Rancher Desktop.exe"
)
$dockerDesktopPaths = @(
    "$env:ProgramFiles\Docker\Docker\Docker Desktop.exe",
    "${env:ProgramFiles(x86)}\Docker\Docker\Docker Desktop.exe",
    "$env:LOCALAPPDATA\Programs\Docker Desktop\Docker Desktop.exe"
)

if (-not $dockerRunning) {
    $foundRancher = $rancherPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    $foundDocker = $dockerDesktopPaths | Where-Object { Test-Path $_ } | Select-Object -First 1

    if ($foundRancher) {
        Write-Host "⏳ Rancher Desktop is installed but stopped. Starting Rancher Desktop..." -ForegroundColor Cyan
        Start-Process -FilePath $foundRancher
        Wait-ForDocker
    } elseif ($foundDocker) {
        Write-Host "⏳ Docker Desktop is installed but stopped. Starting Docker Desktop..." -ForegroundColor Cyan
        Start-Process -FilePath $foundDocker
        Wait-ForDocker
    } else {
        Write-Host "⚠️ No active container engine is currently running." -ForegroundColor Yellow
        $chosenEngine = $Engine
        if ([string]::IsNullOrWhiteSpace($chosenEngine)) {
            Write-Host "`n🎯 Choose your Windows Container Engine:" -ForegroundColor White
            Write-Host "  [1] Rancher Desktop (Recommended: 100% Open-Source, Moby/WSL2, Low RAM, No Lic Lock-in) [Default]"
            Write-Host "  [2] Docker Desktop  (Standard official engine from Docker Inc.)"
            $choice = if ($Yes) { "1" } else { Read-Host "Enter choice [1-2] (default: 1)" }
            if ($choice -eq "2") { $chosenEngine = "docker" } else { $chosenEngine = "rancher" }
        }

        if (Get-Command winget -ErrorAction SilentlyContinue) {
            if ($chosenEngine -eq "rancher") {
                Write-Host "📦 Installing Rancher Desktop via winget..." -ForegroundColor Cyan
                winget install SUSE.RancherDesktop --accept-source-agreements --accept-package-agreements
                $foundRancher = $rancherPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
                if ($foundRancher) {
                    Write-Host "🚀 Launching Rancher Desktop..." -ForegroundColor Cyan
                    Start-Process -FilePath $foundRancher
                    Wait-ForDocker
                }
            } else {
                Write-Host "📦 Installing Docker Desktop via winget..." -ForegroundColor Cyan
                winget install Docker.DockerDesktop --accept-source-agreements --accept-package-agreements
                $foundDocker = $dockerDesktopPaths | Where-Object { Test-Path $_ } | Select-Object -First 1
                if ($foundDocker) {
                    Write-Host "🚀 Launching Docker Desktop..." -ForegroundColor Cyan
                    Start-Process -FilePath $foundDocker
                    Wait-ForDocker
                }
            }
        } else {
            Write-Host "Please install Rancher Desktop (https://rancherdesktop.io/) or Docker Desktop (https://docker.com) and re-run." -ForegroundColor Red
            return
        }
    }
}

# 3. Clone or Update OpenRig Repository
Write-Host "`n📂 Deploying OpenRig into: $InstallDir" -ForegroundColor White
if (Test-Path (Join-Path $InstallDir ".git")) {
    Write-Host "ℹ️ Updating existing OpenRig installation..." -ForegroundColor Yellow
    git -C $InstallDir pull --ff-only
} elseif (Test-Path $InstallDir) {
    Write-Host "ℹ️ Directory $InstallDir exists. Ready." -ForegroundColor Yellow
} else {
    New-Item -ItemType Directory -Path (Split-Path $InstallDir -Parent) -Force | Out-Null
    if (Get-Command git -ErrorAction SilentlyContinue) {
        git clone "https://github.com/LFR-SnowBall/OpenRig.git" $InstallDir
    } else {
        Write-Host "📥 Downloading OpenRig ZIP archive..." -ForegroundColor Cyan
        $zipTmp = Join-Path $env:TEMP "openrig.zip"
        Invoke-WebRequest -Uri "https://github.com/LFR-SnowBall/OpenRig/archive/refs/heads/main.zip" -OutFile $zipTmp
        Expand-Archive -Path $zipTmp -DestinationPath $env:TEMP -Force
        Move-Item (Join-Path $env:TEMP "OpenRig-main") $InstallDir -Force
        Remove-Item $zipTmp -Force
    }
}

# 4. Add to User PATH & Configure ExecutionPolicy
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$InstallDir*") {
    Write-Host "`n🔗 Adding '$InstallDir' to user PATH..." -ForegroundColor Cyan
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$InstallDir", "User")
    $env:Path += ";$InstallDir"
    Write-Host "✔ Added to User PATH. You can now run 'rig' directly from any terminal." -ForegroundColor Green
}

# Ensure CurrentUser execution policy allows local scripts without warning
try {
    $policy = Get-ExecutionPolicy -Scope CurrentUser
    if ($policy -in "Restricted", "Undefined") {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction SilentlyContinue
    }
} catch {}

# 5. Profile / Role Selection
if (-not $Yes) {
    Write-Host "`n🎯 Select your Workstation Profile:" -ForegroundColor White
    Write-Host "  [1] Full Stack Developer (Node, Python, Java, Docker, AWS, Sec, AI) [Default]"
    Write-Host "  [2] Backend JVM (Java 21, Kotlin, Spring Boot, Maven, Gradle)"
    Write-Host "  [3] Frontend & Mobile (Node 22, React, Vue, Flutter, Android SDK)"
    Write-Host "  [4] Security & Pentesting (Trivy, Semgrep, Nuclei, Nmap, Gitleaks)"
    Write-Host "  [5] AI Coding Assistants (Antigravity CLI, Claude Code, Gemini CLI, Codex, Aider)"
    Write-Host "  [6] Minimal Core (Ubuntu 24.04 LTS + Oh My Zsh + Docker CLI)"
    $choice = Read-Host "Enter profile number [1-6] (default: 1)"
    switch ($choice) {
        "2" { $Role = "backend-jvm" }
        "3" { $Role = "frontend-mobile" }
        "4" { $Role = "security-pentest" }
        "5" { $Role = "ai-coding" }
        "6" { $Role = "minimal" }
        default { $Role = "fullstack" }
    }
}

Write-Host "Selected profile: $Role" -ForegroundColor Cyan

# 6. Pre-warmed Image Pull from GHCR
$prewarmed = "ghcr.io/lfr-snowball/openrig:$Role"
Write-Host "`n⚡ Pulling pre-warmed image '$prewarmed' from GHCR..." -ForegroundColor White
docker pull $prewarmed
if ($LASTEXITCODE -eq 0) {
    docker tag $prewarmed "openrig:$Role"
    Write-Host "✔ Downloaded pre-compiled multi-arch image!" -ForegroundColor Green
}

# 7. Start Workstation
if (-not $NoStart) {
    Write-Host "`n🚀 Launching OpenRig Workstation..." -ForegroundColor White
    & (Join-Path $InstallDir "rig.cmd") up
}

Write-Host "`n==========================================================================" -ForegroundColor Cyan
Write-Host "🎉 OpenRig is installed and ready for Windows!" -ForegroundColor Green
Write-Host "  👉 Run anywhere:    rig" -ForegroundColor White
Write-Host "  👉 Shell access:    rig shell" -ForegroundColor White
Write-Host "  👉 IDE connection:  rig ide ." -ForegroundColor White
Write-Host "  👉 Encrypted backup:rig backup create" -ForegroundColor White
Write-Host "  👉 Live migration:  rig migrate push <server_ip>" -ForegroundColor White
Write-Host "  👉 Stop & free RAM: rig down" -ForegroundColor White
Write-Host "==========================================================================`n" -ForegroundColor Cyan
