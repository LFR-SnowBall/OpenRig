<#
.SYNOPSIS
OpenRig CLI for Windows PowerShell (Gaming Rigs & Windows Workstations)
Zero-host-pollution modular developer, security & AI workstation.
#>

param(
    [Parameter(Position=0)]
    [string]$Command = "help",
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$ArgsRest
)

$ErrorActionPreference = "Stop"
$RigDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$EnvFile = Join-Path $RigDir ".env"

function Show-Banner {
    Write-Host "╔══════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║   ⚡ OPENRIG — PORTABLE MODULAR DEV, SEC & AI WORKSTATION (WINDOWS)      ║" -ForegroundColor Cyan
    Write-Host "║   Created by Luis Fernando Real (@LFR-SnowBall)                          ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
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

    $wsPath = (Join-Path $RigDir "workspace") -replace '\\','/'
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
"@
    Set-Content -Path $EnvFile -Value $content -Encoding UTF8
    Write-Host "✅ Configuration saved to .env (Profile: $role). Run: .\rig.ps1 up" -ForegroundColor Green
}

switch ($Command) {
    { $_ -in "setup", "init" } { Invoke-Setup }
    { $_ -in "up", "start" } {
        if (-not (Test-Path $EnvFile)) { Invoke-Setup }
        Write-Progress -Activity "OpenRig Workstation" -Status "15% - Checking Docker engine..." -PercentComplete 15
        Write-Host "🚀 [15%] Checking OpenRig image and modules..." -ForegroundColor Cyan
        Write-Progress -Activity "OpenRig Workstation" -Status "55% - Building / Verifying image layers..." -PercentComplete 55
        docker compose -f "$RigDir\docker-compose.yml" --env-file "$EnvFile" up -d --build @ArgsRest
        Write-Progress -Activity "OpenRig Workstation" -Status "100% - OpenRig Ready!" -PercentComplete 100 -Completed
        Write-Host "✅ [100%] OpenRig is running. Enter with: .\rig.ps1 shell" -ForegroundColor Green
    }
    { $_ -in "shell", "enter" } {
        docker exec -it openrig zsh -l
    }
    "vpn" {
        docker exec -it openrig rig-vpn @ArgsRest
    }
    { $_ -in "profile", "prof" } {
        docker exec -it openrig rig-profile @ArgsRest
    }
    { $_ -in "share", "tunnel" } {
        docker exec -it openrig rig-share @ArgsRest
    }
    { $_ -in "snapshot", "snap" } {
        $sub = if ($ArgsRest.Count -gt 0) { $ArgsRest[0] } else { "list" }
        $tag = if ($ArgsRest.Count -gt 1) { $ArgsRest[1] } else { "latest" }
        switch ($sub) {
            "save"    { docker commit openrig "openrig-snapshot:$tag" | Out-Null; Write-Host "✅ Snapshot openrig-snapshot:$tag saved." -ForegroundColor Green }
            "restore" { docker tag "openrig-snapshot:$tag" "openrig:fullstack"; docker compose -f "$RigDir\docker-compose.yml" --env-file "$EnvFile" up -d --force-recreate }
            default   { docker images "openrig-snapshot" }
        }
    }
    { $_ -in "connect", "remote" } {
        $target = $ArgsRest[0]
        $parts = $target -split ":"
        $hostIp = $parts[0]
        $port = if ($parts.Count -gt 1) { $parts[1] } else { "2201" }
        ssh -A -p $port -L 3000:127.0.0.1:3000 -L 5173:127.0.0.1:5173 -L 8000:127.0.0.1:8000 -L 8080:127.0.0.1:8080 "rig@$hostIp"
    }
    { $_ -in "down", "stop" } {
        Write-Host "🛑 Stopping OpenRig and freeing resources for Gaming/Host..." -ForegroundColor Yellow
        docker compose -f "$RigDir\docker-compose.yml" --profile services down
    }
    "status" {
        Show-Banner
        docker ps --filter "network=openrig-net"
    }
    default {
        Show-Banner
        Write-Host "Commands:"
        Write-Host "  .\rig.ps1 setup   -> Configure your workstation role"
        Write-Host "  .\rig.ps1 up      -> Build and start OpenRig"
        Write-Host "  .\rig.ps1 shell   -> Open Zsh terminal inside OpenRig"
        Write-Host "  .\rig.ps1 down    -> Stop containers and free 100% RAM/CPU"
    }
}
