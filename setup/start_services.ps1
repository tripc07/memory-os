<#
.SYNOPSIS
    Start Memory OS services (Redis, Qdrant, Ollama, llama.cpp, ARQ Worker) as background processes on Windows.

.DESCRIPTION
    Launches Redis, Qdrant, Ollama, llama.cpp, and the ARQ worker as background processes.
    PID files are written to $HERMES_HOME so stop_services.ps1 can shut them down.

.EXAMPLE
    .\setup\start_services.ps1
    .\setup\start_services.ps1 -Only redis,qdrant,ollama,llamacpp
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
$QdrantDir  = if ($env:QDRANT_DIR) { $env:QDRANT_DIR } else { Join-Path $env:LOCALAPPDATA "qdrant" }
$PidDir     = Join-Path $HermesHome "pids"
$LogDir     = if ($env:HERMES_LOGS_DIR) { $env:HERMES_LOGS_DIR } else { Join-Path $HermesHome "logs" }
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

function GetProcessFromPidFile($pidFile) {
    if (-not (Test-Path $pidFile)) { return $null }

    try {
        $pidText = (Get-Content -LiteralPath $pidFile -ErrorAction Stop | Select-Object -First 1).Trim()
        $pidValue = 0
        if (-not [int]::TryParse($pidText, [ref]$pidValue)) {
            Remove-Item -LiteralPath $pidFile -Force
            return $null
        }

        return Get-Process -Id $pidValue -ErrorAction Stop
    } catch {
        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function TestQdrantHealth() {
    $qdrantPort = if ($env:QDRANT_PORT) { $env:QDRANT_PORT } else { "6333" }
    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:$qdrantPort/healthz" -TimeoutSec 2 | Out-Null
        return $true
    } catch {
        return $false
    }
}

function TestLlamaCppHealth() {
    $llamaPort = if ($env:LLAMA_CPP_PORT) { $env:LLAMA_CPP_PORT } else { "8080" }
    try {
        $health = Invoke-RestMethod -Uri "http://127.0.0.1:$llamaPort/health" -TimeoutSec 2
        return $health.status -eq "ok"
    } catch {
        return $false
    }
}

function TestOllamaHealth() {
    $ollamaPort = if ($env:OLLAMA_PORT) { $env:OLLAMA_PORT } else { "11434" }
    try {
        Invoke-RestMethod -Uri "http://127.0.0.1:$ollamaPort/api/tags" -TimeoutSec 2 | Out-Null
        return $true
    } catch {
        return $false
    }
}

function FindMemoryOsWorkerProcesses($workerScript) {
    $escapedWorkerScript = [regex]::Escape($workerScript)
    Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -match "^python" -and
            $_.CommandLine -and
            $_.CommandLine -match $escapedWorkerScript -and
            $_.CommandLine -match "--run-worker"
        } |
        Sort-Object ProcessId
}

function FindOllamaProcesses($ollamaExe) {
    $escapedOllamaExe = if ($ollamaExe) { [regex]::Escape($ollamaExe) } else { "" }
    Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -eq "ollama.exe" -and
            $_.CommandLine -and
            $_.CommandLine -match "serve" -and
            (
                (-not $escapedOllamaExe) -or
                $_.CommandLine -match $escapedOllamaExe
            )
        } |
        Sort-Object ProcessId
}

function FindLlamaCppProcesses($modelPath, $llamaCppDir) {
    $escapedModelPath = if ($modelPath) { [regex]::Escape($modelPath) } else { "" }
    $escapedLlamaCppDir = if ($llamaCppDir) { [regex]::Escape($llamaCppDir) } else { "" }
    Get-CimInstance Win32_Process |
        Where-Object {
            $_.Name -eq "llama-server.exe" -and
            $_.CommandLine -and
            (
                ($escapedLlamaCppDir -and $_.CommandLine -match $escapedLlamaCppDir) -or
                ($escapedModelPath -and $_.CommandLine -match $escapedModelPath) -or
                ((-not $escapedLlamaCppDir) -and (-not $escapedModelPath))
            )
        } |
        Sort-Object ProcessId
}

function FindWinGetExecutable($exeName) {
    $packagesDir = Join-Path $env:LOCALAPPDATA "Microsoft\WinGet\Packages"
    if (-not (Test-Path $packagesDir)) { return $null }

    Get-ChildItem -Path $packagesDir -Recurse -Filter $exeName -ErrorAction SilentlyContinue |
        Select-Object -First 1 -ExpandProperty FullName
}

# -- Load .env ---------------------------------------------------------------
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

$envFiles = @()
if ($env:MAA_ENV_PATH) { $envFiles += $env:MAA_ENV_PATH }
$envFiles += (Join-Path $HermesHome ".env")
$envFiles += (Join-Path $RepoRoot ".env")
$envFiles | Select-Object -Unique | ForEach-Object { LoadEnvFile $_ }

if (-not $env:MAA_ENV_PATH) {
    $hermesEnv = Join-Path $HermesHome ".env"
    if (Test-Path $hermesEnv) {
        $env:MAA_ENV_PATH = $hermesEnv
    }
}

$RedisPassword = if ($env:REDIS_PASSWORD) { $env:REDIS_PASSWORD } else { "" }

# -- Redis -------------------------------------------------------------------
if (ShouldStart "redis") {
    $redisPid = Join-Path $PidDir "redis.pid"
    $redisServerCandidates = @(
        (FindWinGetExecutable "redis-server.exe"),
        (Get-Command redis-server -ErrorAction SilentlyContinue).Source,
        "C:\Program Files\Redis\redis-server.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }
    $redisCliCandidates = @(
        (FindWinGetExecutable "redis-cli.exe"),
        (Get-Command redis-cli -ErrorAction SilentlyContinue).Source,
        "C:\Program Files\Redis\redis-cli.exe"
    ) | Where-Object { $_ -and (Test-Path $_) }

    $redisAlreadyRunning = $false
    foreach ($redisCli in $redisCliCandidates) {
        try {
            $pingArgs = @("ping")
            if ($RedisPassword) { $pingArgs = @("--no-auth-warning", "-a", $RedisPassword, "ping") }
            $ping = & $redisCli @pingArgs 2>$null
            if ($ping -match "PONG") {
                $redisAlreadyRunning = $true
                break
            }
        } catch {
            $redisAlreadyRunning = $false
        }
    }

    if ($redisAlreadyRunning) {
        GetProcessFromPidFile $redisPid | Out-Null
        Write-Host "  [OK] Redis already running on 127.0.0.1:6379" -ForegroundColor Green
    }

    $redisCmd = if ($redisServerCandidates.Count -gt 0) { $redisServerCandidates[0] } else { $null }
    if ($redisCmd -and -not $redisAlreadyRunning) {
        $redisLog = Join-Path $LogDir "redis.log"

        $redisArgs = @("--port", "6379", "--bind", "127.0.0.1", "--appendonly", "yes", "--maxmemory", "512mb", "--maxmemory-policy", "allkeys-lru")
        if ($RedisPassword) {
            $redisArgs += @("--requirepass", $RedisPassword)
        }

        Write-Host "Starting Redis..." -ForegroundColor Yellow
        $proc = Start-Process -FilePath $redisCmd -ArgumentList $redisArgs `
            -RedirectStandardOutput $redisLog -RedirectStandardError (Join-Path $LogDir "redis-error.log") `
            -PassThru -WindowStyle Hidden
        Set-Content -Path $redisPid -Value $proc.Id
        Write-Host "  [OK] Redis started (PID $($proc.Id))" -ForegroundColor Green
    } elseif (-not $redisAlreadyRunning) {
        Write-Warning "redis-server not found on PATH. Install Redis first."
    }
}

# -- Qdrant ------------------------------------------------------------------
if (ShouldStart "qdrant") {
    $qdrantExe = Join-Path $QdrantDir "qdrant.exe"
    $qdrantPid = Join-Path $PidDir "qdrant.pid"
    $qdrantProc = GetProcessFromPidFile $qdrantPid

    if ($qdrantProc) {
        Write-Host "  [OK] Qdrant already running (PID $($qdrantProc.Id))" -ForegroundColor Green
    } elseif (TestQdrantHealth) {
        $qdrantPortDisplay = if ($env:QDRANT_PORT) { $env:QDRANT_PORT } else { "6333" }
        Write-Host "  [OK] Qdrant already healthy on 127.0.0.1:$qdrantPortDisplay" -ForegroundColor Green
    } elseif (Test-Path $qdrantExe) {
        $qdrantLog = Join-Path $LogDir "qdrant.log"

        Write-Host "Starting Qdrant..." -ForegroundColor Yellow
        $proc = Start-Process -FilePath $qdrantExe `
            -RedirectStandardOutput $qdrantLog -RedirectStandardError (Join-Path $LogDir "qdrant-error.log") `
            -PassThru -WindowStyle Hidden -WorkingDirectory $QdrantDir
        Set-Content -Path $qdrantPid -Value $proc.Id
        Write-Host "  [OK] Qdrant started (PID $($proc.Id))" -ForegroundColor Green
    } else {
        Write-Warning "qdrant.exe not found at $qdrantExe. Run setup_windows.ps1 first."
    }
}

# -- Ollama ------------------------------------------------------------------
if (ShouldStart "ollama") {
    $ollamaPid = Join-Path $PidDir "ollama.pid"
    $ollamaCandidates = @(
        $env:OLLAMA_EXE,
        (Get-Command ollama -ErrorAction SilentlyContinue).Source,
        (Join-Path $env:LOCALAPPDATA "Programs\Ollama\ollama.exe")
    ) | Where-Object { $_ -and (Test-Path $_) }
    $ollamaExe = if ($ollamaCandidates.Count -gt 0) { $ollamaCandidates[0] } else { $null }
    $ollamaProc = GetProcessFromPidFile $ollamaPid

    if (-not $ollamaProc -and $ollamaExe) {
        $existingOllama = @(FindOllamaProcesses $ollamaExe)
        if ($existingOllama.Count -gt 0) {
            $ollamaProc = Get-Process -Id $existingOllama[0].ProcessId -ErrorAction SilentlyContinue
            if ($ollamaProc) {
                Set-Content -Path $ollamaPid -Value $ollamaProc.Id
            }
        }
    }

    if ($ollamaProc -and (TestOllamaHealth)) {
        Write-Host "  [OK] Ollama already running (PID $($ollamaProc.Id))" -ForegroundColor Green
    } elseif (TestOllamaHealth) {
        Write-Host "  [OK] Ollama already healthy on 127.0.0.1:11434" -ForegroundColor Green
    } elseif ($ollamaExe) {
        $ollamaLog = Join-Path $LogDir "ollama.log"
        $ollamaErr = Join-Path $LogDir "ollama-error.log"

        Write-Host "Starting Ollama..." -ForegroundColor Yellow
        $proc = Start-Process -FilePath $ollamaExe -ArgumentList @("serve") `
            -RedirectStandardOutput $ollamaLog -RedirectStandardError $ollamaErr `
            -PassThru -WindowStyle Hidden
        Set-Content -Path $ollamaPid -Value $proc.Id
        Start-Sleep -Seconds 2
        Write-Host "  [OK] Ollama started (PID $($proc.Id))" -ForegroundColor Green
    } else {
        Write-Warning "ollama.exe not found. Install Ollama or set OLLAMA_EXE."
    }
}

# -- llama.cpp ---------------------------------------------------------------
if (ShouldStart "llamacpp") {
    $llamaCppDir = if ($env:LLAMA_CPP_DIR) { $env:LLAMA_CPP_DIR } else { Join-Path $env:LOCALAPPDATA "llama.cpp\b9601" }
    $llamaExe = Join-Path $llamaCppDir "llama-server.exe"
    $llamaModel = if ($env:LLAMA_CPP_MODEL_PATH) { $env:LLAMA_CPP_MODEL_PATH } else { Join-Path $HermesHome "models\qwen2.5-3b-instruct-q4_k_m.gguf" }
    $llamaHost = if ($env:LLAMA_CPP_HOST) { $env:LLAMA_CPP_HOST } else { "127.0.0.1" }
    $llamaPort = if ($env:LLAMA_CPP_PORT) { $env:LLAMA_CPP_PORT } else { "8080" }
    $llamaCtx = if ($env:LLAMA_CPP_CTX_SIZE) { $env:LLAMA_CPP_CTX_SIZE } else { "4096" }
    $llamaGpuLayers = if ($env:LLAMA_CPP_GPU_LAYERS) { $env:LLAMA_CPP_GPU_LAYERS } else { "all" }
    $llamaAlias = if ($env:LLAMA_CPP_ALIAS) { $env:LLAMA_CPP_ALIAS } else { [System.IO.Path]::GetFileNameWithoutExtension($llamaModel) }
    $llamaPid = Join-Path $PidDir "llamacpp.pid"
    $llamaProc = GetProcessFromPidFile $llamaPid

    if (-not $llamaProc) {
        $existingLlama = @(FindLlamaCppProcesses $llamaModel $llamaCppDir)
        if ($existingLlama.Count -gt 0) {
            $llamaProc = Get-Process -Id $existingLlama[0].ProcessId -ErrorAction SilentlyContinue
            if ($llamaProc) {
                Set-Content -Path $llamaPid -Value $llamaProc.Id
            }
        }
    }

    if ($llamaProc -and (TestLlamaCppHealth)) {
        Write-Host "  [OK] llama.cpp already running (PID $($llamaProc.Id))" -ForegroundColor Green
    } elseif (TestLlamaCppHealth) {
        $existingLlama = @(FindLlamaCppProcesses "" $llamaCppDir)
        if ($existingLlama.Count -gt 0) {
            Set-Content -Path $llamaPid -Value $existingLlama[0].ProcessId
        }
        Write-Host "  [OK] llama.cpp already healthy on 127.0.0.1:$llamaPort" -ForegroundColor Green
    } elseif ((Test-Path $llamaExe) -and (Test-Path $llamaModel)) {
        $llamaOut = Join-Path $LogDir "llama-server-out.log"
        $llamaErr = Join-Path $LogDir "llama-server-error.log"
        $llamaArgs = @(
            "--model", $llamaModel,
            "--host", $llamaHost,
            "--port", $llamaPort,
            "--ctx-size", $llamaCtx,
            "--gpu-layers", $llamaGpuLayers,
            "--alias", $llamaAlias
        )

        Write-Host "Starting llama.cpp..." -ForegroundColor Yellow
        $proc = Start-Process -FilePath $llamaExe -ArgumentList $llamaArgs `
            -RedirectStandardOutput $llamaOut -RedirectStandardError $llamaErr `
            -PassThru -WindowStyle Hidden -WorkingDirectory $llamaCppDir
        Set-Content -Path $llamaPid -Value $proc.Id
        Start-Sleep -Seconds 2
        Write-Host "  [OK] llama.cpp started (PID $($proc.Id))" -ForegroundColor Green
    } else {
        Write-Warning "llama.cpp server or model not found. Expected $llamaExe and $llamaModel."
    }
}

# -- ARQ Worker --------------------------------------------------------------
if (ShouldStart "worker") {
    $workerScript = Join-Path (Join-Path $RepoRoot "worker") "main.py"
    if (Test-Path $workerScript) {
        $workerLog = Join-Path $LogDir "worker.log"
        $workerPid = Join-Path $PidDir "worker.pid"
        $workerProc = GetProcessFromPidFile $workerPid

        if (-not $workerProc) {
            $existingWorkers = @(FindMemoryOsWorkerProcesses $workerScript)
            if ($existingWorkers.Count -gt 0) {
                $workerProc = Get-Process -Id $existingWorkers[0].ProcessId -ErrorAction SilentlyContinue
                if ($workerProc) {
                    Set-Content -Path $workerPid -Value $workerProc.Id
                    if ($existingWorkers.Count -gt 1) {
                        Write-Warning "Multiple Memory OS workers detected; keeping PID $($workerProc.Id). Stop duplicates manually if needed."
                    }
                }
            }
        }

        if ($workerProc) {
            Write-Host "  [OK] ARQ Worker already running (PID $($workerProc.Id))" -ForegroundColor Green
            Write-Host ""
            Write-Host "All services started. Stop with: .\setup\stop_services.ps1" -ForegroundColor Cyan
            exit 0
        }

        # Set worker environment for native mode
        if (-not $env:REDIS_HOST) { $env:REDIS_HOST = "127.0.0.1" }
        if (-not $env:REDIS_PORT) { $env:REDIS_PORT = "6379" }
        if (-not $env:QDRANT_HOST) { $env:QDRANT_HOST = "localhost" }
        if (-not $env:QDRANT_PORT) { $env:QDRANT_PORT = "6333" }

        $hermesPython = Join-Path $HermesHome "hermes-agent\venv\Scripts\python.exe"
        if ($env:HERMES_PYTHON) {
            $pythonPath = $env:HERMES_PYTHON
        } elseif (Test-Path $hermesPython) {
            $pythonPath = $hermesPython
        } else {
            $pythonPath = (Get-Command python).Source
        }

        Write-Host "Starting ARQ Worker..." -ForegroundColor Yellow
        $workerArgs = @("`"$workerScript`"", "--run-worker")
        $proc = Start-Process -FilePath $pythonPath -ArgumentList $workerArgs `
            -RedirectStandardOutput $workerLog -RedirectStandardError (Join-Path $LogDir "worker-error.log") `
            -PassThru -WindowStyle Hidden -WorkingDirectory (Split-Path $workerScript)
        Set-Content -Path $workerPid -Value $proc.Id
        Write-Host "  [OK] ARQ Worker started (PID $($proc.Id))" -ForegroundColor Green
    } else {
        Write-Warning "Worker main.py not found at $workerScript"
    }
}

Write-Host ""
Write-Host "All services started. Stop with: .\setup\stop_services.ps1" -ForegroundColor Cyan
