@echo off
rem ==============================================================================
rem 🚀 OpenRig Windows Command Shim
rem Allows running 'rig' seamlessly from PowerShell, CMD, or Windows Terminal
rem Bypasses execution policy restrictions without modifying machine-wide settings
rem Author: Luis Fernando Real (LFR-SnowBall) <luisitoreal01@gmail.com>
rem ==============================================================================
setlocal
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% equ 0 (
    pwsh.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0rig.ps1" %*
) else (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0rig.ps1" %*
)
endlocal
