#Requires -Version 5.1
<#
.SYNOPSIS
    redrab stack validation for Windows

.DESCRIPTION
    Checks configuration files and running service health.
    Does NOT modify any file or start/stop any container.

.PARAMETER Mode
    (default)  Config check + runtime service health
    config     Config files only (stack doesn't need to be running)
    runtime    Running services only
#>

param(
    [Parameter(Position=0)]
    [ValidateSet("full","config","runtime","--help","-h","")]
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

# ── Config validation ──────────────────────────────────────────────────────────

function Invoke-ConfigValidation {
    Write-Section "Configuration validation"

    $envFile = Join-Path $ProjectRoot ".env"
    $aclFile = Join-Path $ProjectRoot "redis\users.acl"

    # .env
    if (-not (Test-Path $envFile)) {
        Write-Err ".env not found — run .\setup.ps1 first"
        return
    }
    Write-Ok ".env present"

    # Placeholders in .env
    $content = Get-Content $envFile -Raw
    if ($content -match $PlaceholderPattern) {
        Write-Warn "Placeholder passwords still in .env — run .\setup.ps1"
    } else {
        Write-Ok "No placeholder passwords in .env"
    }

    # users.acl
    if (-not (Test-Path $aclFile)) {
        Write-Err "redis\users.acl not found"
    } else {
        $aclContent = Get-Content $aclFile -Raw
        if ($aclContent -match $PlaceholderPattern) {
            Write-Warn "redis\users.acl has placeholder passwords — run .\setup.ps1"
        } else {
            Write-Ok "redis\users.acl has no placeholders"
        }
        if ($aclContent -match "user default off") {
            Write-Ok "redis\users.acl: default user is disabled (correct)"
        } else {
            Write-Warn "redis\users.acl: 'user default off' not found"
        }
    }

    # Grafana dashboards
    $dashDir = Join-Path $ProjectRoot "grafana\provisioning\dashboards"
    foreach ($f in @("redis.json","rabbitmq-overview.json")) {
        if (Test-Path (Join-Path $dashDir $f)) {
            Write-Ok "Grafana dashboard present: $f"
        } else {
            Write-Warn "Grafana dashboard missing: $f — run .\setup.ps1 dashboards"
        }
    }
}

# ── Runtime validation ─────────────────────────────────────────────────────────

function Invoke-RuntimeValidation {
    Write-Section "Runtime validation"

    # Container status
    try {
        $ps = & docker compose `
            -f "$ProjectRoot\docker-compose.yml" `
            -f "$ProjectRoot\docker-compose.monitoring.yml" `
            ps 2>&1 | Out-String
    } catch {
        Write-Err "Could not read container status — is the stack running?"
        Write-Info "Start with: docker compose -f docker-compose.yml -f docker-compose.monitoring.yml up -d"
        return
    }

    $services = @("redis","rabbitmq","redis-exporter","redisinsight","rabbitscout","prometheus","grafana")
    foreach ($svc in $services) {
        if ($ps -match $svc) {
            if ($ps -match "$svc.*Up|$svc.*running|$svc.*healthy") {
                Write-Ok "${svc}: running"
            } elseif ($ps -match "$svc.*unhealthy") {
                Write-Warn "${svc}: unhealthy — docker compose logs $svc"
            } else {
                Write-Warn "${svc}: status unknown"
            }
        } else {
            Write-Err "${svc}: not found"
        }
    }

    Write-Section "Service health"

    # Redis
    try {
        $r = & docker exec redis redis-cli ping 2>&1
        if ($r -match "PONG|NOAUTH") {
            Write-Ok "Redis: responding ($r)"
        } else {
            Write-Warn "Redis: unexpected response: $r"
        }
    } catch { Write-Warn "Redis: container not reachable" }

    # RabbitMQ
    try {
        $r = & docker exec rabbitmq rabbitmq-diagnostics -q ping 2>&1
        if ($r -match "succeeded|pong") {
            Write-Ok "RabbitMQ: responding"
        } else {
            Write-Warn "RabbitMQ: unexpected response: $r"
        }
    } catch { Write-Warn "RabbitMQ: container not reachable" }

    # Prometheus
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:9090/-/ready" `
             -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { Write-Ok "Prometheus: ready" }
    } catch { Write-Warn "Prometheus: not reachable (may still be starting)" }

    # redis_exporter
    try {
        $m = (Invoke-WebRequest -Uri "http://localhost:9121/metrics" `
              -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop).Content
        if ($m -match "redis_up 1") {
            Write-Ok "redis_exporter: redis_up=1"
        } else {
            Write-Warn "redis_exporter: redis_up != 1 — check REDIS_EXPORTER_PASSWORD"
        }
    } catch { Write-Warn "redis_exporter: not reachable" }

    # RabbitMQ Prometheus endpoint
    try {
        $r = Invoke-WebRequest -Uri "http://localhost:15692/metrics" `
             -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
        if ($r.StatusCode -eq 200) { Write-Ok "RabbitMQ Prometheus endpoint: reachable" }
    } catch { Write-Warn "RabbitMQ Prometheus endpoint: not reachable" }

    # Access summary
    Write-Host ""
    Write-Host "  Web interfaces" -ForegroundColor White
    Write-Host "  ------------------------------------------------" -ForegroundColor Cyan
    Write-Host ("  {0,-22} {1}" -f "RabbitMQ UI:",  "http://localhost:15672")
    Write-Host ("  {0,-22} {1}" -f "RedisInsight:", "http://localhost:5540")
    Write-Host ("  {0,-22} {1}" -f "RabbitScout:",  "http://localhost:3001")
    Write-Host ("  {0,-22} {1}" -f "Prometheus:",   "http://localhost:9090")
    Write-Host ("  {0,-22} {1}" -f "Grafana:",      "http://localhost:3002")
    Write-Host "  ------------------------------------------------" -ForegroundColor Cyan
    Write-Host ""
}

# ── Help ───────────────────────────────────────────────────────────────────────

function Show-Help {
    Write-Host @"

Usage:
  .\validate.ps1           Config check + runtime service health
  .\validate.ps1 config    Config files only (stack doesn't need to be running)
  .\validate.ps1 runtime   Running services only
  .\validate.ps1 --help    Show this help

"@
    exit 0
}

# ── Entry point ────────────────────────────────────────────────────────────────

if ($Mode -in "--help","-h") { Show-Help }

Write-Header "Validate"

switch ($Mode) {
    "config"  { Invoke-ConfigValidation }
    "runtime" { Invoke-RuntimeValidation }
    default   { Invoke-ConfigValidation; Invoke-RuntimeValidation }
}
