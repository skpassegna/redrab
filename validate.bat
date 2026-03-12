@echo off
:: validate.bat — Windows entry point for validate.ps1
:: Usage: validate.bat [--config | --runtime | --help]

setlocal

where pwsh >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    set PS_EXE=pwsh
) else (
    where powershell >nul 2>&1
    if %ERRORLEVEL% EQU 0 (
        set PS_EXE=powershell
    ) else (
        echo ERROR: PowerShell not found.
        echo Install from: https://aka.ms/powershell
        exit /b 1
    )
)

%PS_EXE% -NoProfile -ExecutionPolicy Bypass -File "%~dp0validate.ps1" %*
exit /b %ERRORLEVEL%
