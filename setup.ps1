#Requires -Version 5.1
<#
.SYNOPSIS
    redrab configuration setup for Windows

.DESCRIPTION
    Checks .env and config files, generates passwords if needed, downloads dashboards.
    Does NOT start, stop, or restart containers.

.PARAMETER Mode
    (default)    Full setup: passwords + dashboards
    passwords    Passwords and config files only
    dashboards   Grafana dashboards only

.EXAMPLE
    .\setup.ps1
    .\setup.ps1 passwords
    .\setup.ps1 dashboards
#>

param(
    [Parameter(Position=0)]
    [ValidateSet("full","passwords","dashboards","--help","-h","")]
    [string]$Mode = "full"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProjectRoot = $PSScriptRoot
$PlaceholderPattern = "CHANGE_ME"

# ── Console helpers ────────────────────────────────────────────────────────────

function Write-Header([string]$Title) {
    Write-Host ""
    Write-Host "==================================================" -ForegroundColor Blue
    Write-Host "  redrab — $Title" -ForegroundColor Blue
    Write-Host "==================================================" -ForegroundColor Blue
    Write-Host ""
}
function Write-Section([string]$t) { Write-Host ""; Write-Host ">> $t" -ForegroundColor Cyan }
function Write-Ok([string]$t)      { Write-Host "  [OK]  $t" -ForegroundColor Green }
function Write-Warn([string]$t)    { Write-Host "  [!!]  $t" -ForegroundColor Yellow }
function Write-Err([string]$t)     { Write-Host "  [ERR] $t" -ForegroundColor Red }
function Write-Info([string]$t)    { Write-Host "  [>>]  $t" -ForegroundColor Gray }
function Write-Fatal([string]$t)   { Write-Host ""; Write-Host "FATAL: $t" -ForegroundColor Red; Write-Host ""; exit 1 }

# ── Password generation ────────────────────────────────────────────────────────
# Alphanumeric only, 32 chars, cryptographically secure

function New-SecurePassword {
    $chars  = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    $rng    = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $result = [System.Text.StringBuilder]::new()

    # Oversample to avoid modulo bias
    while ($result.Length -lt 32) {
        $batch = [byte[]]::new(64)
        $rng.GetBytes($batch)
        foreach ($b in $batch) {
            if ($result.Length -ge 32) { break }
            # Reject bytes in the bias zone
            if ($b -lt (256 - (256 % $chars.Length))) {
                [void]$result.Append($chars[$b % $chars.Length])
            }
        }
    }
    return $result.ToString()
}

# ── .env helpers ───────────────────────────────────────────────────────────────

function Get-EnvValue([string]$Key, [string]$File) {
    $line = Get-Content $File | Where-Object { $_ -match "^${Key}=" } | Select-Object -First 1
    if ($line) { return ($line -split "=", 2)[1] }
    return ""
}

function Set-EnvValue([string]$Key, [string]$Value, [string]$File) {
    $content = Get-Content $File -Raw
    if ($content -match "(?m)^${Key}=") {
        $content = $content -replace "(?m)^${Key}=.*", "${Key}=${Value}"
    } else {
        $content = $content.TrimEnd() + "`n${Key}=${Value}`n"
    }
    # UTF-8 without BOM, Unix line endings
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($File, $content, $utf8NoBom)
}

function Test-HasPlaceholder([string]$File) {
    $keys = @("REDIS_PASSWORD","REDIS_EXPORTER_PASSWORD","RABBITMQ_PASSWORD","GF_ADMIN_PASSWORD")
    foreach ($key in $keys) {
        $val = Get-EnvValue $key $File
        if ($val -match $PlaceholderPattern) { return $true }
    }
    return $false
}

# ── ACL file ───────────────────────────────────────────────────────────────────
# Written with Unix LF line endings — Redis rejects CRLF and comments

function Write-AclFile([string]$File, [string]$PwAdmin, [string]$PwApp, [string]$PwReadonly) {
    $lines = @(
        "user default off",
        "user admin on >${PwAdmin} ~* &* +@all",
        "user appuser on >${PwApp} ~* &* +@read +@write +@string +@hash +@list +@set +@sortedset +@pubsub -@dangerous -@admin",
        "user readonly on >${PwReadonly} ~* &* +@read -@dangerous"
    )
    $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($File, ($lines -join "`n") + "`n", $utf8NoBom)
}

# ── Pre-flight ─────────────────────────────────────────────────────────────────

function Invoke-Preflight {
    Write-Section "Pre-flight checks"
    $errors = 0

    # docker
    try {
        $v = & docker --version 2>&1
        Write-Ok "docker: $v"
    } catch {
        Write-Err "docker not found — install Docker Desktop"
        $errors++
    }

    # Docker daemon
    try {
        & docker info 2>&1 | Out-Null
        Write-Ok "Docker daemon is running"
    } catch {
        Write-Err "Docker daemon not running — start Docker Desktop"
        $errors++
    }

    # Compose v2
    try {
        $cv = (& docker compose version 2>&1) -match '(\d+\.\d+\.\d+)' | Out-Null
        $cv = [regex]::Match((& docker compose version 2>&1), '(\d+)\.(\d+)\.(\d+)').Value
        if ([int]($cv -split '\.')[0] -ge 2) {
            Write-Ok "docker compose: v$cv"
        } else {
            Write-Err "Docker Compose v2+ required (found v$cv)"
            $errors++
        }
    } catch {
        Write-Err "Docker Compose v2 not found"
        $errors++
    }

    # Required files
    $required = @(
        "docker-compose.yml","docker-compose.monitoring.yml",".env.example",
        "redis\redis.conf","redis\users.acl","rabbitmq\rabbitmq.conf",
        "rabbitmq\enabled_plugins","prometheus\prometheus.yml",
        "grafana\provisioning\datasources\datasources.yml",
        "grafana\provisioning\dashboards\dashboards.yml"
    )
    $missing = 0
    foreach ($f in $required) {
        if (-not (Test-Path (Join-Path $ProjectRoot $f))) {
            Write-Err "Missing: $f"
            $errors++
            $missing++
        }
    }
    if ($missing -eq 0) { Write-Ok "All required project files present" }

    if ($errors -gt 0) { Write-Fatal "$errors pre-flight check(s) failed" }
    Write-Ok "Pre-flight passed"
}

# ── Passwords ──────────────────────────────────────────────────────────────────

function Invoke-PasswordSetup {
    Write-Section "Secrets configuration"

    $envFile    = Join-Path $ProjectRoot ".env"
    $envExample = Join-Path $ProjectRoot ".env.example"
    $aclFile    = Join-Path $ProjectRoot "redis\users.acl"

    # Ensure .env exists
    if (-not (Test-Path $envFile)) {
        if (-not (Test-Path $envExample)) { Write-Fatal ".env.example not found" }
        Copy-Item $envExample $envFile
        Write-Ok ".env created from .env.example"
    } else {
        Write-Ok ".env found"
    }

    # Decide: generate or verify
    if (Test-HasPlaceholder $envFile) {
        Write-Warn "Placeholder passwords detected — generating new passwords"

        $PwAdmin    = New-SecurePassword
        $PwApp      = New-SecurePassword
        $PwReadonly = New-SecurePassword
        $PwRabbitMQ = New-SecurePassword
        $PwGrafana  = New-SecurePassword

        Write-Ok "Passwords generated (32-char alphanumeric)"

        Set-EnvValue "REDIS_PASSWORD"          $PwAdmin    $envFile
        Set-EnvValue "REDIS_EXPORTER_PASSWORD" $PwApp      $envFile
        Set-EnvValue "RABBITMQ_PASSWORD"       $PwRabbitMQ $envFile
        Set-EnvValue "GF_ADMIN_PASSWORD"       $PwGrafana  $envFile
        Write-Ok ".env updated"

        Write-AclFile $aclFile $PwAdmin $PwApp $PwReadonly
        Write-Ok "redis\users.acl updated"

        Write-Host ""
        Write-Host "  Generated credentials" -ForegroundColor White
        Write-Host "  ------------------------------------------------" -ForegroundColor Cyan
        Write-Host ("  {0,-28} {1}" -f "Redis admin:",    $PwAdmin)
        Write-Host ("  {0,-28} {1}" -f "Redis appuser:",  $PwApp)
        Write-Host ("  {0,-28} {1}" -f "Redis readonly:", $PwReadonly)
        Write-Host ("  {0,-28} {1}" -f "RabbitMQ admin:", $PwRabbitMQ)
        Write-Host ("  {0,-28} {1}" -f "Grafana admin:",  $PwGrafana)
        Write-Host "  ------------------------------------------------" -ForegroundColor Cyan
        Write-Host ""
        Write-Warn "These are the only time these passwords are displayed."
        Write-Warn "They are stored in .env and redis\users.acl — never commit .env."
        Write-Host ""
    } else {
        Write-Ok "Passwords already set in .env"

        # Verify ACL sync
        if ((Get-Content $aclFile -Raw) -match $PlaceholderPattern) {
            Write-Warn "redis\users.acl has placeholder passwords — syncing with .env"
            $PwAdmin    = Get-EnvValue "REDIS_PASSWORD"          $envFile
            $PwApp      = Get-EnvValue "REDIS_EXPORTER_PASSWORD" $envFile
            $PwReadonly = New-SecurePassword
            Write-AclFile $aclFile $PwAdmin $PwApp $PwReadonly
            Write-Ok "redis\users.acl synced with .env"
        } else {
            Write-Ok "redis\users.acl appears in sync"
        }
    }
}

# ── Dashboards ─────────────────────────────────────────────────────────────────

function Invoke-DashboardSetup {
    Write-Section "Grafana dashboards"

    $dashDir = Join-Path $ProjectRoot "grafana\provisioning\dashboards"
    $datasourceUid = "prometheus-ds"

    $dashboards = @(
        @{ Id = 763;   File = "redis.json" },
        @{ Id = 10991; File = "rabbitmq-overview.json" }
    )

    foreach ($d in $dashboards) {
        $output = Join-Path $dashDir $d.File

        if (Test-Path $output) {
            Write-Ok "Dashboard #$($d.Id) already present ($($d.File))"
            continue
        }

        $url = "https://grafana.com/api/dashboards/$($d.Id)/revisions/latest/download"
        Write-Info "Downloading dashboard #$($d.Id) -> $($d.File)"
        try {
            Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing -TimeoutSec 30
            $content = Get-Content $output -Raw
            $content = $content -replace [regex]::Escape('${DS_PROMETHEUS}'), $datasourceUid
            $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
            [System.IO.File]::WriteAllText($output, $content, $utf8NoBom)
            Write-Ok "Dashboard #$($d.Id) downloaded and patched"
        } catch {
            Write-Warn "Failed to download dashboard #$($d.Id): $($_.Exception.Message)"
            Write-Info "Download manually: $url"
        }
    }
}

# ── OS notes (informational only) ─────────────────────────────────────────────

function Write-OsNotes {
    Write-Section "Windows / Docker Desktop"
    Write-Ok "vm.overcommit_memory — managed by Docker Desktop WSL2/Hyper-V (no action needed)"
    Write-Ok "Transparent Huge Pages — managed by Docker Desktop (no action needed)"
    Write-Info "Redis kernel warnings in logs are cosmetic on Docker Desktop — safe to ignore"
}

# ── Help ───────────────────────────────────────────────────────────────────────

function Show-Help {
    Write-Host @"

Usage:
  .\setup.ps1              Full setup: passwords + dashboards
  .\setup.ps1 passwords    Passwords and config files only
  .\setup.ps1 dashboards   Grafana dashboards only
  .\setup.ps1 --help       Show this help

To start the stack:
  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d

To check the running stack:
  .\validate.ps1

"@
    exit 0
}

# ── Entry point ────────────────────────────────────────────────────────────────

if ($Mode -in "--help", "-h") { Show-Help }

Write-Header "Setup"

switch ($Mode) {
    "passwords" {
        Invoke-Preflight
        Write-OsNotes
        Invoke-PasswordSetup
        Write-Host ""
        Write-Info "Next: start or restart the stack to apply changes"
        Write-Info "  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d"
        Write-Host ""
    }
    "dashboards" {
        Invoke-DashboardSetup
        Write-Host ""
        Write-Info "If Grafana is running, restart it to reload:"
        Write-Info "  docker compose restart grafana"
        Write-Host ""
    }
    default {
        Invoke-Preflight
        Write-OsNotes
        Invoke-PasswordSetup
        Invoke-DashboardSetup
        Write-Host ""
        Write-Ok "Setup complete"
        Write-Info "Start the stack with:"
        Write-Info "  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d"
        Write-Info "Then check the stack:"
        Write-Info "  .\validate.ps1"
        Write-Host ""
    }
}
