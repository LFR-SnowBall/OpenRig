<#
.SYNOPSIS
⚡ OpenRig Universal Bootstrapper & Installer for Windows PowerShell
Single-line installation:
  irm https://raw.githubusercontent.com/LFR-SnowBall/OpenRig/main/install.ps1 | iex

Author: Luis Fernando Real (LFR-SnowBall) <luisitoreal01@gmail.com>
License: MIT
#>

param(
    [string]$Role = "fullstack",
    [string]$InstallDir = (Join-Path $HOME ".openrig"),
    [switch]$NoStart,
    [switch]$Yes
)

$ErrorActionPreference = "Stop"

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

Show-Banner

# 1. Check Container Engine (Docker Desktop on Windows)
Write-Host "`n🐳 Checking Container Engine (Docker Desktop / WSL2)..." -ForegroundColor White
$dockerRunning = $false
try {
    $null = docker info 2>$null
    if ($LASTEXITCODE -eq 0) {
        $dockerRunning = $true
        Write-Host "✔ Docker Desktop is active and running." -ForegroundColor Green
    }
} catch {
    $dockerRunning = $false
}

if (-not $dockerRunning) {
    Write-Host "⚠️ Docker Desktop is not running or not installed." -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        $installChoice = "y"
        if (-not $Yes) {
            $installChoice = Read-Host "Would you like to install Docker Desktop via winget? [Y/n]"
        }
        if ($installChoice -ne "n" -and $installChoice -ne "N") {
            Write-Host "📦 Installing Docker Desktop via winget..." -ForegroundColor Cyan
            winget install Docker.DockerDesktop --accept-source-agreements --accept-package-agreements
            Write-Host "Please start Docker Desktop and re-run this script." -ForegroundColor Yellow
            return
        }
    } else {
        Write-Host "Please install Docker Desktop from https://docs.docker.com/desktop/setup/install/windows-install/ and re-run." -ForegroundColor Red
        return
    }
}

# 2. Clone or Update OpenRig Repository
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

# 3. Add to User PATH if not present
$userPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($userPath -notlike "*$InstallDir*") {
    Write-Host "`n🔗 Adding '$InstallDir' to user PATH..." -ForegroundColor Cyan
    [Environment]::SetEnvironmentVariable("Path", "$userPath;$InstallDir", "User")
    $env:Path += ";$InstallDir"
    Write-Host "✔ Added to User PATH. You can run 'rig.ps1' from any PowerShell session." -ForegroundColor Green
}

# 4. Profile / Role Selection
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

# 5. Pre-warmed Image Pull from GHCR
$prewarmed = "ghcr.io/lfr-snowball/openrig:$Role"
Write-Host "`n⚡ Pulling pre-warmed image '$prewarmed' from GHCR..." -ForegroundColor White
docker pull $prewarmed
if ($LASTEXITCODE -eq 0) {
    docker tag $prewarmed "openrig:$Role"
    Write-Host "✔ Downloaded pre-compiled multi-arch image!" -ForegroundColor Green
}

# 6. Start Workstation
if (-not $NoStart) {
    Write-Host "`n🚀 Launching OpenRig Workstation..." -ForegroundColor White
    & (Join-Path $InstallDir "rig.ps1") up
}

Write-Host "`n==========================================================================" -ForegroundColor Cyan
Write-Host "🎉 OpenRig is installed and ready!" -ForegroundColor Green
Write-Host "  👉 Shell access:    rig.ps1 shell" -ForegroundColor White
Write-Host "  👉 IDE connection:  rig.ps1 ide ." -ForegroundColor White
Write-Host "  👉 Stop & free RAM: rig.ps1 down" -ForegroundColor White
Write-Host "==========================================================================`n" -ForegroundColor Cyan
