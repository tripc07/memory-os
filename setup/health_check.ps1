<#
.SYNOPSIS
    Check health of all Memory OS services.

.DESCRIPTION
    Verifies Redis, Qdrant, ARQ Worker, and Jan AI are running and healthy.
    Checks both PID files and actual service health endpoints.

.EXAMPLE
    .\\setup\\health_check.ps1
#>

[CmdletBinding()]
param()

$DefaultHermesHome = Join-Path $env:LOCALAPPDATA "hermes"
if (-not (Test-Path $DefaultHermesHome)) {
    $DefaultHermesHome = Join-Path $env:USERPROFILE ".hermes"
}
$HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { $DefaultHermesHome }
$PidDir = Join-Path $HermesHome "pids"
$JanExe = Join-Path $env:LOCALAPPDATA "Programs\Jan\resources\bin\jan.exe"

Write-Host "Memory OS Service Health Check" -ForegroundColor Cyan
Write-Host "==============================" -ForegroundColor Cyan
Write-Host ""

# Redis
$redisPid = Join-Path $PidDir "redis.pid"
Write-Host "[Redis]" -NoNewline

$redisCli = Get-Command redis-cli -ErrorAction SilentlyContinue
if (-not $redisCli) {
    Write-Host "     [WARN] redis-cli not installed" -ForegroundColor Yellow
} else {
    $pw = $redisCli.Source
    $result = & $pw ping 2>$null
    $resultTrimmed = $result.Trim()
    if ($resultTrimmed -eq "PONG") {
        Write-Host "     [OK] Running - PONG received" -ForegroundColor Green
    } else {
        Write-Host "     [FAIL] Not responding" -ForegroundColor Red
    }
}

# Qdrant
Write-Host "[Qdrant]" -NoNewline
try {
    $port = if ($env:QDRANT_PORT) { $env:QDRANT_PORT } else { "6333" }
    Invoke-RestMethod -Uri "http://127.0.0.1:$port/healthz" -TimeoutSec 2 | Out-Null
    Write-Host "    [OK] Healthy on port $port" -ForegroundColor Green
} catch {
    Write-Host "    [FAIL] Not healthy on port $port" -ForegroundColor Red
}

# ARQ Worker
Write-Host "[ARQ Worker]" -NoNewline
$workerPidFile = Join-Path $PidDir "worker.pid"
if (Test-Path $workerPidFile) {
    $savedPid = Get-Content $workerPidFile
    try {
        $proc = Get-Process -Id ([int]$savedPid) -ErrorAction Stop
        Write-Host "  [OK] Running (PID $savedPid)" -ForegroundColor Green
    } catch {
        Write-Host "  [FAIL] PID file stale (PID $savedPid)" -ForegroundColor Red
    }
} else {
    Write-Host "  [WARN] No PID file found" -ForegroundColor Yellow
}

# Jan AI
Write-Host "[Jan AI]" -NoNewline
$JanPid = Join-Path $PidDir "jan.pid"
$JanPort = $env:JAN_PORT
if (-not $JanPort) {
    if ($env:EMBEDDING_API_BASE -match 'localhost:(\d+)') { $JanPort = $matches[1] }
    elseif ($env:EMBEDDING_API_BASE -match '127.0.0.1:(\d+)') { $JanPort = $matches[1] }
}
if (-not $JanPort) { $JanPort = "6767" }

# Check via port/API first
try {
    $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$JanPort/v1/models" -TimeoutSec 2
    Write-Host "      [OK] Running on port $JanPort" -ForegroundColor Green
} catch {
    # Check PID file as fallback
    if (Test-Path $JanPid) {
        $savedPid = Get-Content $JanPid
        try {
            $proc = Get-Process -Id ([int]$savedPid) -ErrorAction Stop
            Write-Host "      [WARN] PID exists but API not responding (PID $savedPid)" -ForegroundColor Yellow
        } catch {
            Write-Host "      [FAIL] PID file stale (PID $savedPid)" -ForegroundColor Red
        }
    } else {
        Write-Host "      [WARN] Not running (no PID file, port $JanPort free)" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "==============================" -ForegroundColor Cyan
Write-Host "Tip: Run .\setup\start_all.ps1 to start all services" -ForegroundColor DarkGray
Write-Host "     Run .\setup\stop_all.ps1 to stop all services" -ForegroundColor DarkGray