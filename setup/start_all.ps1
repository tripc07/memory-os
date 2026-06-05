<#
.SYNOPSIS
    Start all Memory OS + Jan AI services as background processes on Windows.

.DESCRIPTION
    Launches Redis, Qdrant, ARQ Worker, and Jan AI model server.
    Use the -Only parameter to start specific services.
    PID files written to $HERMES_HOME/pids/ for stop_all.ps1 shutdown.

.EXAMPLE
    .\\setup\\start_all.ps1
    .\\setup\\start_all.ps1 -Only redis,jan
    .\\setup\\start_all.ps1 -Detach # Start Jan in background mode
#>

[CmdletBinding()]
param(
    [string[]]$Only,
    [switch]$Detach
)

$ErrorActionPreference = "Stop"

$DefaultHermesHome = Join-Path $env:LOCALAPPDATA "hermes"
if (-not (Test-Path $DefaultHermesHome)) {
    $DefaultHermesHome = Join-Path $env:USERPROFILE ".hermes"
}
$HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { $DefaultHermesHome }
$QdrantDir  = if ($env:QDRANT_DIR) { $env:QDRANT_DIR } else { Join-Path $env:LOCALAPPDATA "qdrant" }
$PidDir     = Join-Path $HermesHome "pids"
$LogDir     = if ($env:HERMES_LOGS_DIR) { $env:HERMES_LOGS_DIR } else { Join-Path $HermesHome "logs" }
$JanExe     = Join-Path $env:LOCALAPPDATA "Programs\Jan\resources\bin\jan.exe"
$RepoRoot   = Split-Path -Parent $PSScriptRoot

# If run from setup/ directly, adjust repo root
if (-not (Test-Path (Join-Path $RepoRoot "requirements.txt"))) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
if (-not (Test-Path (Join-Path $RepoRoot "requirements.txt"))) {
    $RepoRoot = Get-Location
}

New-Item -ItemType Directory -Path $PidDir -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

function ShouldStart($name) {
    if (-not $Only -or $Only.Count -eq 0) { return $true }
    return $Only -contains $name
}

function LoadEnvFile($path) {
    if (-not $path -or -not (Test-Path $path)) { return }
    Get-Content $path | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $parts = $line -split "=", 2
            if ($parts.Count -eq 2) {
                $key = $parts[0].Trim()
                $val = $parts[1].Trim().Trim('"')
                if (-not [System.Environment]::GetEnvironmentVariable($key)) {
                    [System.Environment]::SetEnvironmentVariable($key, $val, "Process")
                }
            }
        }
    }
}

# Load .env files
LoadEnvFile (Join-Path $HermesHome ".env")
LoadEnvFile (Join-Path $RepoRoot ".env")

# -- Redis -------------------------------------------------------------------
if (ShouldStart "redis") {
    Write-Host "[1/4] Checking Redis..." -ForegroundColor Yellow
    $redisPid = Join-Path $PidDir "redis.pid"
    $redisCli = Get-Command redis-cli -ErrorAction SilentlyContinue

    $redisRunning = $false
    if ($redisCli) {
        $RedisPassword = if ($env:REDIS_PASSWORD) { $env:REDIS_PASSWORD } else { "" }
        $pingArgs = if ($RedisPassword) { @("-a", $RedisPassword, "ping") } else { @("ping") }
        try {
            $ping = & $redisCli.Source @pingArgs 2>$null
            if ($ping -match "PONG") { $redisRunning = $true }
        } catch { }
    }

    if ($redisRunning) {
        Write-Host "  [OK] Redis already running on 127.0.0.1:6379" -ForegroundColor Green
    } else {
        $redisServer = Get-Command redis-server -ErrorAction SilentlyContinue
        if ($redisServer) {
            $redisLog = Join-Path $LogDir "redis.log"
            $redisArgs = "--port", "6379", "--bind", "127.0.0.1", "--appendonly", "yes", "--maxmemory", "512mb", "--maxmemory-policy", "allkeys-lru"
            $RedisPassword = if ($env:REDIS_PASSWORD) { $env:REDIS_PASSWORD } else { "" }
            if ($RedisPassword) { $redisArgs += "--requirepass", $RedisPassword }

            Write-Host "Starting Redis..." -ForegroundColor Yellow
            $proc = Start-Process -FilePath $redisServer.Source -ArgumentList $redisArgs -RedirectStandardOutput $redisLog -RedirectStandardError (Join-Path $LogDir "redis-error.log") -PassThru -WindowStyle Hidden
            Set-Content -Path $redisPid -Value $proc.Id
            Write-Host "  [OK] Redis started (PID $($proc.Id))" -ForegroundColor Green
        } else {
            Write-Warning "redis-server not found. Install via: winget install Redis.Redis"
        }
    }
}

# -- Qdrant ------------------------------------------------------------------
if (ShouldStart "qdrant") {
    Write-Host "[2/4] Checking Qdrant..." -ForegroundColor Yellow
    $qdrantExe = Join-Path $QdrantDir "qdrant.exe"
    $qdrantPid = Join-Path $PidDir "qdrant.pid"

    # Check health endpoint
    try {
        $port = if ($env:QDRANT_PORT) { $env:QDRANT_PORT } else { "6333" }
        Invoke-RestMethod -Uri "http://127.0.0.1:$port/healthz" -TimeoutSec 2 | Out-Null
        Write-Host "  [OK] Qdrant already healthy on 127.0.0.1:$port" -ForegroundColor Green
    } catch {
        if (Test-Path $qdrantExe) {
            $qdrantLog = Join-Path $LogDir "qdrant.log"
            Write-Host "Starting Qdrant..." -ForegroundColor Yellow
            $proc = Start-Process -FilePath $qdrantExe -RedirectStandardOutput $qdrantLog -RedirectStandardError (Join-Path $LogDir "qdrant-error.log") -PassThru -WindowStyle Hidden -WorkingDirectory $QdrantDir
            Set-Content -Path $qdrantPid -Value $proc.Id
            Write-Host "  [OK] Qdrant started (PID $($proc.Id))" -ForegroundColor Green
        } else {
            Write-Warning "qdrant.exe not found at $qdrantExe. Run setup_windows.ps1 first."
        }
    }
}

# -- ARQ Worker --------------------------------------------------------------
if (ShouldStart "worker") {
    Write-Host "[3/4] Checking ARQ Worker..." -ForegroundColor Yellow
    $workerScript = Join-Path $RepoRoot "worker\main.py"
    $workerLog = Join-Path $LogDir "worker.log"
    $workerPid = Join-Path $PidDir "worker.pid"

    if (Test-Path $workerScript) {
        # Set worker environment for native mode
        if (-not $env:REDIS_HOST) { $env:REDIS_HOST = "127.0.0.1" }
        if (-not $env:QDRANT_HOST) { $env:QDRANT_HOST = "localhost" }

        $hermesPython = Join-Path $HermesHome "hermes-agent\venv\Scripts\python.exe"
        $pythonPath = $env:HERMES_PYTHON
        if (-not $pythonPath -and (Test-Path $hermesPython)) { $pythonPath = $hermesPython }
        if (-not $pythonPath) { $pythonPath = (Get-Command python).Source }

        Write-Host "Starting ARQ Worker..." -ForegroundColor Yellow
        $proc = Start-Process -FilePath $pythonPath -ArgumentList "`"$workerScript`"", "--run-worker" -RedirectStandardOutput $workerLog -RedirectStandardError (Join-Path $LogDir "worker-error.log") -PassThru -WindowStyle Hidden -WorkingDirectory (Split-Path $workerScript)
        Set-Content -Path $workerPid -Value $proc.Id
        Write-Host "  [OK] ARQ Worker started (PID $($proc.Id))" -ForegroundColor Green
    } else {
        Write-Warning "Worker main.py not found at $workerScript"
    }
}

# -- Jan AI ------------------------------------------------------------------
if (ShouldStart "jan") {
    Write-Host "[4/4] Checking Jan AI..." -ForegroundColor Yellow

    if (-not (Test-Path $JanExe)) {
        Write-Error "Jan executable not found at $JanExe. Install Jan AI from https://jan.ai"
        exit 1
    }

    $JanPid = Join-Path $PidDir "jan.pid"
    $JanPort = if ($env:JAN_PORT) { $env:JAN_PORT } else { "6767" }

    # Check if already running via port
    try {
        $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$JanPort/v1/models" -TimeoutSec 2
        Write-Host "  [OK] Jan already running on port $JanPort" -ForegroundColor Green
    } catch {
        # Check PID file as fallback
        if (Test-Path $JanPid) {
            try {
                $existingPid = Get-Content $JanPid
                $proc = Get-Process -Id ([int]$existingPid) -ErrorAction Stop
                Write-Host "  [OK] Jan already running (PID $existingPid)" -ForegroundColor Green
            } catch {
                Remove-Item $JanPid -Force
            }
        }

        if (-not (Test-Path $JanPid)) {
            $JanDataDir = Join-Path $env:APPDATA "Jan\data\llamacpp\models"
            $ModelPath = Join-Path $JanDataDir "Jan-v3.5-4B-Q4_K_XL\model.gguf"

            $janArgs = @("serve", "Jan-v3.5-4B-Q4_K_XL")
            if ($Detach) { $janArgs += "--detach" }

            Write-Host "Starting Jan AI server..." -ForegroundColor Yellow
            $proc = Start-Process -FilePath $JanExe -ArgumentList $janArgs -PassThru -WindowStyle Hidden
            Set-Content -Path $JanPid -Value $proc.Id
            Write-Host "  [OK] Jan started (PID $($proc.Id))" -ForegroundColor Green
            Write-Host "  Endpoint: http://127.0.0.1:$JanPort/v1" -ForegroundColor Cyan
        }
    }
}

Write-Host ""
Write-Host "All services started. Stop with: .\setup\stop_all.ps1" -ForegroundColor Cyan