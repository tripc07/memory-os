<#
.SYNOPSIS
    Start Memory OS services (Redis, Qdrant, ARQ Worker) as background processes on Windows.

.DESCRIPTION
    Launches Redis, Qdrant, and the ARQ worker as background processes.
    PID files are written to $HERMES_HOME so stop_services.ps1 can shut them down.

.EXAMPLE
    .\setup\start_services.ps1
    .\setup\start_services.ps1 -Only redis,qdrant
#>

[CmdletBinding()]
param(
    [string[]]$Only
)

$ErrorActionPreference = "Stop"

$HermesHome = $env:HERMES_HOME ?? (Join-Path $env:USERPROFILE ".hermes")
$QdrantDir  = $env:QDRANT_DIR ?? (Join-Path $env:LOCALAPPDATA "qdrant")
$PidDir     = Join-Path $HermesHome "pids"
$LogDir     = $env:HERMES_LOGS_DIR ?? (Join-Path $HermesHome "logs")
$RepoRoot   = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

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

# ── Load .env ────────────────────────────────────────────────────────────────
$envFile = $env:MAA_ENV_PATH ?? (Join-Path $RepoRoot ".env")
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
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

$RedisPassword = $env:REDIS_PASSWORD ?? ""

# ── Redis ────────────────────────────────────────────────────────────────────
if (ShouldStart "redis") {
    $redisCmd = Get-Command redis-server -ErrorAction SilentlyContinue
    if ($redisCmd) {
        $redisLog = Join-Path $LogDir "redis.log"
        $redisPid = Join-Path $PidDir "redis.pid"

        $redisArgs = @("--port", "6379", "--bind", "127.0.0.1", "--appendonly", "yes", "--maxmemory", "512mb", "--maxmemory-policy", "allkeys-lru")
        if ($RedisPassword) {
            $redisArgs += @("--requirepass", $RedisPassword)
        }

        Write-Host "Starting Redis..." -ForegroundColor Yellow
        $proc = Start-Process -FilePath $redisCmd.Source -ArgumentList $redisArgs `
            -RedirectStandardOutput $redisLog -RedirectStandardError (Join-Path $LogDir "redis-error.log") `
            -PassThru -WindowStyle Hidden
        Set-Content -Path $redisPid -Value $proc.Id
        Write-Host "  ✓ Redis started (PID $($proc.Id))" -ForegroundColor Green
    } else {
        Write-Warning "redis-server not found on PATH. Install Redis first."
    }
}

# ── Qdrant ───────────────────────────────────────────────────────────────────
if (ShouldStart "qdrant") {
    $qdrantExe = Join-Path $QdrantDir "qdrant.exe"
    if (Test-Path $qdrantExe) {
        $qdrantLog = Join-Path $LogDir "qdrant.log"
        $qdrantPid = Join-Path $PidDir "qdrant.pid"

        Write-Host "Starting Qdrant..." -ForegroundColor Yellow
        $proc = Start-Process -FilePath $qdrantExe `
            -RedirectStandardOutput $qdrantLog -RedirectStandardError (Join-Path $LogDir "qdrant-error.log") `
            -PassThru -WindowStyle Hidden -WorkingDirectory $QdrantDir
        Set-Content -Path $qdrantPid -Value $proc.Id
        Write-Host "  ✓ Qdrant started (PID $($proc.Id))" -ForegroundColor Green
    } else {
        Write-Warning "qdrant.exe not found at $qdrantExe. Run setup_windows.ps1 first."
    }
}

# ── ARQ Worker ───────────────────────────────────────────────────────────────
if (ShouldStart "worker") {
    $workerScript = Join-Path $RepoRoot "docker" "worker" "main.py"
    if (Test-Path $workerScript) {
        $workerLog = Join-Path $LogDir "worker.log"
        $workerPid = Join-Path $PidDir "worker.pid"

        # Set worker environment for native mode
        $env:REDIS_HOST = $env:REDIS_HOST ?? "127.0.0.1"
        $env:REDIS_PORT = $env:REDIS_PORT ?? "6379"
        $env:QDRANT_HOST = $env:QDRANT_HOST ?? "localhost"
        $env:QDRANT_PORT = $env:QDRANT_PORT ?? "6333"

        $pythonPath = (Get-Command python).Source

        Write-Host "Starting ARQ Worker..." -ForegroundColor Yellow
        $proc = Start-Process -FilePath $pythonPath -ArgumentList "`"$workerScript`" --run-worker" `
            -RedirectStandardOutput $workerLog -RedirectStandardError (Join-Path $LogDir "worker-error.log") `
            -PassThru -WindowStyle Hidden -WorkingDirectory (Split-Path $workerScript)
        Set-Content -Path $workerPid -Value $proc.Id
        Write-Host "  ✓ ARQ Worker started (PID $($proc.Id))" -ForegroundColor Green
    } else {
        Write-Warning "Worker main.py not found at $workerScript"
    }
}

Write-Host ""
Write-Host "All services started. Stop with: .\setup\stop_services.ps1" -ForegroundColor Cyan
