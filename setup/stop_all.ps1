<#
.SYNOPSIS
    Stop all Memory OS + Jan AI services on Windows.

.DESCRIPTION
    Reads PID files from $HERMES_HOME/pids/ and stops the corresponding processes.
    Also checks ports for any lingering processes.

.EXAMPLE
    .\\setup\\stop_all.ps1
    .\\setup\\stop_all.ps1 -Only redis,jan
#>

[CmdletBinding()]
param(
    [string[]]$Only
)

$ErrorActionPreference = "Stop"

$DefaultHermesHome = Join-Path $env:LOCALAPPDATA "hermes"
if (-not (Test-Path $DefaultHermesHome)) {
    $DefaultHermesHome = Join-Path $env:USERPROFILE ".hermes"
}
$HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { $DefaultHermesHome }
$JanExe   = Join-Path $env:LOCALAPPDATA "Programs\Jan\resources\bin\jan.exe"
$PidDir   = Join-Path $HermesHome "pids"

function ShouldStop($name) {
    if (-not $Only -or $Only.Count -eq 0) { return $true }
    return $Only -contains $name
}

# -- Redis -------------------------------------------------------------------
if (ShouldStop "redis") {
    Write-Host "[1/4] Stopping Redis..." -ForegroundColor Yellow
    $redisPid = Join-Path $PidDir "redis.pid"
    if (Test-Path $redisPid) {
        try {
            $pidValue = Get-Content $redisPid
            $proc = Get-Process -Id ([int]$pidValue) -ErrorAction Stop
            Stop-Process -Id $pidValue -Force
            Write-Host "  [OK] Stopped Redis (PID $pidValue)" -ForegroundColor Green
        } catch {
            Write-Host "  [--] Redis not running (PID $pidValue)" -ForegroundColor DarkGray
        }
        Remove-Item $redisPid -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "  [--] No Redis PID file found" -ForegroundColor DarkGray
    }
}

# -- Qdrant ------------------------------------------------------------------
if (ShouldStop "qdrant") {
    Write-Host "[2/4] Stopping Qdrant..." -ForegroundColor Yellow
    $qdrantPid = Join-Path $PidDir "qdrant.pid"
    if (Test-Path $qdrantPid) {
        try {
            $pidValue = Get-Content $qdrantPid
            $proc = Get-Process -Id ([int]$pidValue) -ErrorAction Stop
            Stop-Process -Id $pidValue -Force
            Write-Host "  [OK] Stopped Qdrant (PID $pidValue)" -ForegroundColor Green
        } catch {
            Write-Host "  [--] Qdrant not running (PID $pidValue)" -ForegroundColor DarkGray
        }
        Remove-Item $qdrantPid -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "  [--] No Qdrant PID file found" -ForegroundColor DarkGray
    }
}

# -- ARQ Worker --------------------------------------------------------------
if (ShouldStop "worker") {
    Write-Host "[3/4] Stopping ARQ Worker..." -ForegroundColor Yellow
    $workerPid = Join-Path $PidDir "worker.pid"
    if (Test-Path $workerPid) {
        try {
            $pidValue = Get-Content $workerPid
            $proc = Get-Process -Id ([int]$pidValue) -ErrorAction Stop
            Stop-Process -Id $pidValue -Force
            Write-Host "  [OK] Stopped ARQ Worker (PID $pidValue)" -ForegroundColor Green
        } catch {
            Write-Host "  [--] ARQ Worker not running (PID $pidValue)" -ForegroundColor DarkGray
        }
        Remove-Item $workerPid -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "  [--] No Worker PID file found" -ForegroundColor DarkGray
    }
}

# -- Jan AI ------------------------------------------------------------------
if (ShouldStop "jan") {
    Write-Host "[4/4] Stopping Jan AI..." -ForegroundColor Yellow
    $JanPid = Join-Path $PidDir "jan.pid"
    $JanPort = if ($env:JAN_PORT) { $env:JAN_PORT } else { "6767" }

    if (Test-Path $JanPid) {
        try {
            $pidValue = Get-Content $JanPid
            $proc = Get-Process -Id ([int]$pidValue) -ErrorAction Stop
            Stop-Process -Id $pidValue -Force
            Write-Host "  [OK] Stopped Jan (PID $pidValue)" -ForegroundColor Green
        } catch {
            Write-Host "  [--] Jan not running (PID $pidValue)" -ForegroundColor DarkGray
        }
        Remove-Item $JanPid -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "  [--] No Jan PID file found" -ForegroundColor DarkGray
    }

    # Also check port for any lingering process
    try {
        $janProcs = Get-NetTCPConnection -LocalPort $JanPort -ErrorAction SilentlyContinue | ForEach-Object {
            (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Id
        }
        foreach ($pid in $janProcs) {
            if ($pid) {
                Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
                Write-Host "  [OK] Stopped orphan Jan process (PID $pid)" -ForegroundColor Green
            }
        }
    } catch { }
}

Write-Host ""
Write-Host "Services stopped." -ForegroundColor Cyan