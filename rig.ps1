<#
.SYNOPSIS
OpenRig CLI for Windows PowerShell (GLADOS Gaming Rig & Windows Workstations)
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
    Write-Host "║   By Linux Open Source S.A. de C.V.                                      ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
}

function Invoke-Setup {
    Show-Banner
    Write-Host "Selecciona el Rol para configurar tu máquina OpenRig:`n" -ForegroundColor White
    Write-Host "  1) 🐍 Backend Python     (pyenv + uv, Python multi-versión, Django, Flask, FastAPI)"
    Write-Host "  2) ☕ Backend JVM        (SDKMAN!, Java 21/17, Kotlin, Spring Boot, Maven, Gradle)"
    Write-Host "  3) 🎨 Frontend & Web     (nvm, Node LTS, Vue.js, React, Vite, pnpm, Yarn, Bun)"
    Write-Host "  4) 📱 Mobile & Flutter   (Flutter, FVM, Dart, Android SDK CLI, ADB Wi-Fi/USB)"
    Write-Host "  5) 🛡️  DevSecOps & Pentest(nmap, nuclei, trivy, semgrep, gitleaks, sqlmap, AWS CLI)"
    Write-Host "  6) 🦾 Full-Stack Core    (Python + JVM + Node + Cloud + Security + AI CLIs)"
    Write-Host ""
    $choice = Read-Host "👉 Elige una opción [1-6] (default: 6)"
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
    Write-Host "✅ Configuración guardada en .env (Perfil: $role). Ejecuta: .\rig.ps1 up" -ForegroundColor Green
}

switch ($Command) {
    { $_ -in "setup", "init" } { Invoke-Setup }
    { $_ -in "up", "start" } {
        if (-not (Test-Path $EnvFile)) { Invoke-Setup }
        Write-Progress -Activity "OpenRig Workstation" -Status "15% - Verificando motor Docker..." -PercentComplete 15
        Write-Host "🚀 [15%] Verificando imagen y módulos de OpenRig..." -ForegroundColor Cyan
        Write-Progress -Activity "OpenRig Workstation" -Status "55% - Construyendo / Verificando capas de imagen..." -PercentComplete 55
        docker compose -f "$RigDir\docker-compose.yml" --env-file "$EnvFile" up -d --build @ArgsRest
        Write-Progress -Activity "OpenRig Workstation" -Status "100% - ¡OpenRig Activo!" -PercentComplete 100 -Completed
        Write-Host "✅ [100%] OpenRig activo. Entra con: .\rig.ps1 shell" -ForegroundColor Green
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
            "save"    { docker commit openrig "openrig-snapshot:$tag" | Out-Null; Write-Host "✅ Snapshot openrig-snapshot:$tag guardado." -ForegroundColor Green }
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
        Write-Host "🛑 Apagando OpenRig y liberando recursos para Gaming/Host..." -ForegroundColor Yellow
        docker compose -f "$RigDir\docker-compose.yml" --profile services down
    }
    "status" {
        Show-Banner
        docker ps --filter "network=openrig-net"
    }
    default {
        Show-Banner
        Write-Host "Comandos:"
        Write-Host "  .\rig.ps1 setup   -> Configura el rol de tu estación"
        Write-Host "  .\rig.ps1 up      -> Construye y levanta OpenRig"
        Write-Host "  .\rig.ps1 shell   -> Abre terminal Zsh dentro de OpenRig"
        Write-Host "  .\rig.ps1 down    -> Apaga contenedores y libera 100% RAM/CPU"
    }
}
