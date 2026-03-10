#Requires -Version 5.1
<#
.SYNOPSIS
    redrab setup script for Windows (PowerShell)

.DESCRIPTION
    Full setup: generates secure passwords, updates .env and redis/users.acl,
    downloads Grafana dashboards, starts the Docker stack, and validates health.

.PARAMETER Mode
    full        (default) Complete setup
    passwords   Regenerate passwords only
    dashboards  Download/re-download Grafana dashboards only
    validate    Run post-setup health validation only

.EXAMPLE
    .\setup.ps1
    .\setup.ps1 passwords
    .\setup.ps1 dashboards
    .\setup.ps1 validate

.NOTES
    Requirements: Docker Desktop for Windows with Compose v2
#>

param(
    [Parameter(Position=0)]
    [ValidateSet("full", "passwords", "dashboards", "validate", "--help", "-h", "")]
    [string]$Mode = "full"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ── Project root ───────────────────────────────────────────────────────────────
$ProjectRoot = $PSScriptRoot

# ── Console colors ─────────────────────────────────────────────────────────────
function Write-Header {
    Write-Host ""
    Write-Host "======================================================" -ForegroundColor Blue
    Write-Host "  redrab - Setup Script" -ForegroundColor Blue
    Write-Host "  Redis + RabbitMQ Production Stack" -ForegroundColor Blue
    Write-Host "======================================================" -ForegroundColor Blue
    Write-Host ""
}

function Write-Section([string]$Text) {
    Write-Host ""
    Write-Host ">> $Text" -ForegroundColor Cyan
}

function Write-Ok([string]$Text) {
    Write-Host "  [OK]   $Text" -ForegroundColor Green
}

function Write-Warn([string]$Text) {
    Write-Host "  [WARN] $Text" -ForegroundColor Yellow
}

function Write-Info([string]$Text) {
    Write-Host "  [>>]   $Text" -ForegroundColor Gray
}

function Write-Err([string]$Text) {
    Write-Host "  [ERR]  $Text" -ForegroundColor Red
}

function Write-Fatal([string]$Text) {
    Write-Host ""
    Write-Host "FATAL: $Text" -ForegroundColor Red
    Write-Host ""
    exit 1
}

# ── Password generation ────────────────────────────────────────────────────────
# Alphanumeric only [A-Za-z0-9], 10 characters
# Uses RNGCryptoServiceProvider for cryptographically secure output

function New-SecurePassword {
    $chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    $rng   = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $bytes = [byte[]]::new(64)  # oversample to reduce bias
    $rng.GetBytes($bytes)

    $result = [System.Text.StringBuilder]::new()
    foreach ($b in $bytes) {
        if ($result.Length -ge 10) { break }
        $index = $b % $chars.Length
        # Reject bytes that would cause bias (bias zone: 256 % 62 = 6 bytes at top)
        if ($b -lt (256 - (256 % $chars.Length))) {
            [void]$result.Append($chars[$index])
        }
    }

    # Fallback: if we didn't get enough chars (very unlikely), recurse
    if ($result.Length -lt 10) {
        return New-SecurePassword
    }

    return $result.ToString()
}

# ── .env helpers ───────────────────────────────────────────────────────────────

function Set-EnvValue([string]$Key, [string]$Value, [string]$File) {
    $content = Get-Content $File -Raw
    if ($content -match "(?m)^${Key}=") {
        # Replace existing line
        $content = $content -replace "(?m)^${Key}=.*", "${Key}=${Value}"
    } else {
        # Append new line
        $content = $content.TrimEnd() + "`n${Key}=${Value}`n"
    }
    Set-Content -Path $File -Value $content -NoNewline -Encoding UTF8
}

# ── ACL file ───────────────────────────────────────────────────────────────────

function Write-AclFile([string]$File, [string]$PwAdmin, [string]$PwApp, [string]$PwReadonly) {
    $acl = @(
        "user default off",
        "user admin on >${PwAdmin} ~* &* +@all",
        "user appuser on >${PwApp} ~* &* +@read +@write +@string +@hash +@list +@set +@sortedset +@pubsub -@dangerous -@admin",
        "user readonly on >${PwReadonly} ~* &* +@read -@dangerous"
    )
    # Unix line endings — Redis requires LF, not CRLF
    $content = $acl -join "`n"
    [System.IO.File]::WriteAllText($File, $content + "`n", [System.Text.Encoding]::UTF8)
}

# ── Passwords setup ────────────────────────────────────────────────────────────

function Invoke-PasswordSetup {
    Write-Section "Generating and applying passwords"

    $envFile     = Join-Path $ProjectRoot ".env"
    $envExample  = Join-Path $ProjectRoot ".env.example"
    $aclFile     = Join-Path $ProjectRoot "redis\users.acl"

    # Ensure .env exists
    if (-not (Test-Path $envFile)) {
        if (Test-Path $envExample) {
            Copy-Item $envExample $envFile
            Write-Ok ".env created from .env.example"
        } else {
            Write-Fatal ".env.example not found"
        }
    } else {
        $backup = "${envFile}.backup.$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        Copy-Item $envFile $backup
        Write-Ok "Existing .env backed up to: $(Split-Path $backup -Leaf)"
    }

    # Generate passwords
    $PwRedisAdmin    = New-SecurePassword
    $PwRedisApp      = New-SecurePassword
    $PwRedisReadonly = New-SecurePassword
    $PwRabbitMQ      = New-SecurePassword
    $PwGrafana       = New-SecurePassword
    $PwExporter      = $PwRedisApp   # exporter uses appuser credentials

    Write-Ok "All passwords generated (10-char alphanumeric)"

    # Inject into .env
    Set-EnvValue "REDIS_PASSWORD"          $PwRedisAdmin  $envFile
    Set-EnvValue "REDIS_EXPORTER_PASSWORD" $PwExporter    $envFile
    Set-EnvValue "RABBITMQ_PASSWORD"       $PwRabbitMQ    $envFile
    Set-EnvValue "GF_ADMIN_PASSWORD"       $PwGrafana     $envFile
    Write-Ok ".env updated"

    # Rewrite redis/users.acl
    Write-AclFile $aclFile $PwRedisAdmin $PwRedisApp $PwRedisReadonly
    Write-Ok "redis/users.acl updated"

    # Summary
    Write-Host ""
    Write-Host "  Generated credentials" -ForegroundColor White
    Write-Host "  --------------------------------------------------------" -ForegroundColor Cyan
    Write-Host ("  {0,-28} {1}" -f "Redis admin:",    $PwRedisAdmin)
    Write-Host ("  {0,-28} {1}" -f "Redis appuser:",  $PwRedisApp)
    Write-Host ("  {0,-28} {1}" -f "Redis readonly:", $PwRedisReadonly)
    Write-Host ("  {0,-28} {1}" -f "RabbitMQ admin:", $PwRabbitMQ)
    Write-Host ("  {0,-28} {1}" -f "Grafana admin:",  $PwGrafana)
    Write-Host "  --------------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
    Write-Warn "Save these passwords. They are stored in .env and redis/users.acl."
    Write-Warn "Never commit .env to version control."
    Write-Host ""
}

# ── Dashboard download ─────────────────────────────────────────────────────────

function Invoke-DashboardSetup {
    Write-Section "Downloading Grafana dashboards"

    $dashDir = Join-Path $ProjectRoot "grafana\provisioning\dashboards"
    $datasourceUid = "prometheus-ds"

    $dashboards = @(
        @{ Id = 763;   File = "redis.json" },
        @{ Id = 10991; File = "rabbitmq-overview.json" }
    )

    foreach ($d in $dashboards) {
        $url    = "https://grafana.com/api/dashboards/$($d.Id)/revisions/latest/download"
        $output = Join-Path $dashDir $d.File

        Write-Info "Downloading dashboard #$($d.Id) -> $($d.File)"
        try {
            Invoke-WebRequest -Uri $url -OutFile $output -UseBasicParsing -TimeoutSec 30
            # Patch datasource placeholder
            $content = Get-Content $output -Raw
            $content = $content -replace [regex]::Escape('${DS_PROMETHEUS}'), $datasourceUid
            Set-Content -Path $output -Value $content -Encoding UTF8
            Write-Ok "Dashboard #$($d.Id) downloaded and patched"
        } catch {
            Write-Warn "Failed to download dashboard #$($d.Id): $($_.Exception.Message)"
            Write-Info "Download manually: $url"
        }
    }
}

# ── Pre-flight validation ──────────────────────────────────────────────────────

function Invoke-Preflight {
    Write-Section "Pre-flight checks"

    $errors = 0

    # Docker
    try {
        $dockerVersion = & docker --version 2>&1
        Write-Ok "docker found: $dockerVersion"
    } catch {
        Write-Err "docker not found — install Docker Desktop: https://www.docker.com/products/docker-desktop"
        $errors++
    }

    # Docker daemon
    try {
        & docker info 2>&1 | Out-Null
        Write-Ok "Docker daemon is running"
    } catch {
        Write-Err "Docker daemon is not running — start Docker Desktop and retry"
        $errors++
    }

    # Docker Compose v2
    try {
        $composeOut = & docker compose version 2>&1
        if ($composeOut -match '(\d+)\.(\d+)\.(\d+)') {
            $major = [int]$Matches[1]
            if ($major -ge 2) {
                Write-Ok "docker compose found: $($Matches[0])"
            } else {
                Write-Err "Docker Compose v2+ required (found v$($Matches[0]))"
                $errors++
            }
        }
    } catch {
        Write-Err "Docker Compose v2 not found"
        $errors++
    }

    # Required files
    $required = @(
        "docker-compose.yml",
        "docker-compose.monitoring.yml",
        ".env.example",
        "redis\redis.conf",
        "rabbitmq\rabbitmq.conf",
        "rabbitmq\enabled_plugins",
        "prometheus\prometheus.yml",
        "grafana\provisioning\datasources\datasources.yml",
        "grafana\provisioning\dashboards\dashboards.yml"
    )

    $allFound = $true
    foreach ($f in $required) {
        if (-not (Test-Path (Join-Path $ProjectRoot $f))) {
            Write-Err "Missing required file: $f"
            $errors++
            $allFound = $false
        }
    }
    if ($allFound) {
        Write-Ok "All required project files found"
    }

    if ($errors -gt 0) {
        Write-Fatal "$errors pre-flight check(s) failed. Fix the issues above and retry."
    }

    Write-Ok "All pre-flight checks passed"
}

# ── Post-setup validation ──────────────────────────────────────────────────────

function Invoke-PostValidation {
    Write-Section "Post-setup validation"
    Write-Info "Waiting for services to become healthy (up to 90 seconds)..."

    $deadline = (Get-Date).AddSeconds(90)
    $allHealthy = $false

    while ((Get-Date) -lt $deadline) {
        $psOutput = & docker compose `
            -f "$ProjectRoot\docker-compose.yml" `
            -f "$ProjectRoot\docker-compose.monitoring.yml" `
            ps 2>&1 | Out-String

        if ($psOutput -notmatch "unhealthy|starting") {
            $allHealthy = $true
            break
        }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 5
    }
    Write-Host ""

    if (-not $allHealthy) {
        Write-Warn "Some services may still be starting"
        Write-Info "Check: docker compose -f docker-compose.yml -f docker-compose.monitoring.yml ps"
    }

    # Redis
    try {
        $redisResponse = & docker exec redis redis-cli ping 2>&1
        if ($redisResponse -match "PONG|NOAUTH") {
            Write-Ok "Redis is responding (ACL active)"
        } else {
            Write-Warn "Redis response: $redisResponse"
        }
    } catch {
        Write-Warn "Could not reach Redis container"
    }

    # RabbitMQ
    try {
        $rmqResult = & docker exec rabbitmq rabbitmq-diagnostics -q ping 2>&1
        if ($rmqResult -match "succeeded|pong|ok") {
            Write-Ok "RabbitMQ is responding"
        } else {
            Write-Warn "RabbitMQ response: $rmqResult"
        }
    } catch {
        Write-Warn "Could not reach RabbitMQ container"
    }

    # Prometheus
    try {
        $resp = Invoke-WebRequest -Uri "http://localhost:9090/-/ready" `
            -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($resp.StatusCode -eq 200) {
            Write-Ok "Prometheus is ready — http://localhost:9090"
        }
    } catch {
        Write-Warn "Prometheus not yet ready — may still be starting"
    }

    # redis_exporter
    try {
        $metrics = Invoke-WebRequest -Uri "http://localhost:9121/metrics" `
            -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($metrics.Content -match "redis_up 1") {
            Write-Ok "redis_exporter is scraping Redis successfully"
        } else {
            Write-Warn "redis_exporter: redis_up != 1 — check REDIS_EXPORTER_PASSWORD"
        }
    } catch {
        Write-Warn "redis_exporter not reachable"
    }

    Write-Host ""
    Write-Host "  Stack is up - access your services:" -ForegroundColor White
    Write-Host "  --------------------------------------------------------" -ForegroundColor Cyan
    Write-Host ("  {0,-22} {1}" -f "RabbitMQ UI:",   "http://localhost:15672")
    Write-Host ("  {0,-22} {1}" -f "RedisInsight:",   "http://localhost:5540")
    Write-Host ("  {0,-22} {1}" -f "RabbitScout:",    "http://localhost:3001")
    Write-Host ("  {0,-22} {1}" -f "Prometheus:",     "http://localhost:9090")
    Write-Host ("  {0,-22} {1}" -f "Grafana:",        "http://localhost:3002")
    Write-Host "  --------------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
    Write-Info "All credentials are in: .env and redis\users.acl"
    Write-Info "Prometheus targets:     http://localhost:9090/targets"
    Write-Host ""
}

# ── Windows system checks ──────────────────────────────────────────────────────

function Invoke-WindowsChecks {
    Write-Section "Windows / Docker Desktop checks"

    # vm.overcommit_memory and THP are not applicable on Windows —
    # Docker Desktop uses WSL2 or Hyper-V which handle these internally
    Write-Ok "vm.overcommit_memory — managed by Docker Desktop WSL2/Hyper-V (no action needed)"
    Write-Ok "Transparent Huge Pages — managed by Docker Desktop (no action needed)"
    Write-Info "Redis kernel warnings in logs are cosmetic on Docker Desktop — safe to ignore"

    # Check WSL2 is the backend (recommended)
    try {
        $wslOutput = & wsl --status 2>&1 | Out-String
        if ($wslOutput -match "WSL 2") {
            Write-Ok "WSL2 backend detected (recommended)"
        }
    } catch {
        Write-Info "Could not check WSL2 status"
    }
}

# ── Entry point ────────────────────────────────────────────────────────────────

function Show-Help {
    Write-Host @"

Usage:
  .\setup.ps1              Full setup: passwords, dashboards, start stack, validate
  .\setup.ps1 passwords    Regenerate passwords only
  .\setup.ps1 dashboards   Download/re-download Grafana dashboards only
  .\setup.ps1 validate     Run post-setup health validation only
  .\setup.ps1 --help       Show this help

"@
    exit 0
}

Write-Header

switch ($Mode) {
    { $_ -in "--help", "-h" } {
        Show-Help
    }
    "passwords" {
        Invoke-Preflight
        Invoke-PasswordSetup
        Write-Info "Passwords updated. Restart the stack to apply:"
        Write-Info "  docker compose -f docker-compose.yml -f docker-compose.monitoring.yml restart"
        Write-Host ""
    }
    "dashboards" {
        Invoke-DashboardSetup
        Write-Host ""
        Write-Ok "Done. Restart Grafana to reload dashboards:"
        Write-Info "  docker compose restart grafana"
        Write-Host ""
    }
    "validate" {
        Invoke-PostValidation
    }
    default {
        # Full setup
        Invoke-Preflight
        Invoke-WindowsChecks
        Invoke-PasswordSetup
        Invoke-DashboardSetup

        Write-Section "Starting the stack"
        & docker compose `
            -f "$ProjectRoot\docker-compose.yml" `
            -f "$ProjectRoot\docker-compose.monitoring.yml" `
            up -d
        Write-Ok "Stack started"

        Invoke-PostValidation
    }
}
