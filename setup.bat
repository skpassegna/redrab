@echo off
:: setup.bat — redrab Windows entry point
:: Invokes setup.ps1 via PowerShell 5+ or PowerShell Core (pwsh)
::
:: Usage:
::   setup.bat              — full setup
::   setup.bat --passwords  — regenerate passwords only
::   setup.bat --dashboards — download Grafana dashboards only
::   setup.bat --validate   — post-setup validation only
::   setup.bat --help       — show help
:: ─────────────────────────────────────────────────────────────────────────────

setlocal

:: Check for PowerShell Core first (pwsh), fall back to Windows PowerShell
where pwsh >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set PS_EXE=pwsh
) else (
    where powershell >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        set PS_EXE=powershell
    ) else (
        echo ERROR: PowerShell not found. Install PowerShell from https://aka.ms/powershell
        exit /b 1
    )
)

:: Run setup.ps1 with execution policy bypass (no system-wide policy change)
%PS_EXE% -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup.ps1" %*

exit /b %ERRORLEVEL%
