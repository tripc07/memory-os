<#
.SYNOPSIS
    Memory OS — Windows Native Setup Script

.DESCRIPTION
    Installs and configures Redis, Qdrant, and the ARQ worker to run natively
    on Windows (no Docker, no WSL). Requires PowerShell 5.1+ and Python 3.11+.

    This script:
    1. Validates prerequisites (Python, pip)
    2. Installs Redis for Windows (Memurai community or Redis via winget)
    3. Downloads and extracts Qdrant for Windows
    4. Creates the .hermes directory structure
    5. Installs Python dependencies
    6. Initialises SQLite databases
    7. Registers Windows Task Scheduler jobs (replaces cron)

.NOTES
    Run as Administrator for service installation.
    Run from the repository root: .\setup\setup_windows.ps1

.EXAMPLE
    # Full setup
    powershell -ExecutionPolicy Bypass -File .\setup\setup_windows.ps1

    # Skip service install (just deps + databases)
    powershell -ExecutionPolicy Bypass -File .\setup\setup_windows.ps1 -SkipServices
#>

[CmdletBinding()]
param(
    [switch]$SkipServices,
    [switch]$SkipScheduledTasks,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ── Paths ────────────────────────────────────────────────────────────────────
$HermesHome     = $env:HERMES_HOME ?? (Join-Path $env:USERPROFILE ".hermes")
$QdrantDir      = Join-Path $env:LOCALAPPDATA "qdrant"
$QdrantVersion  = "1.17.1"
$RepoRoot       = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# If run from setup/ directly, adjust
if (-not (Test-Path (Join-Path $RepoRoot "requirements.txt"))) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
if (-not (Test-Path (Join-Path $RepoRoot "requirements.txt"))) {
    $RepoRoot = Get-Location
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Memory OS — Windows Native Setup           ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Repo root   : $RepoRoot"
Write-Host "  Hermes home : $HermesHome"
Write-Host "  Qdrant dir  : $QdrantDir"
Write-Host ""

# ── 1. Validate prerequisites ────────────────────────────────────────────────
Write-Host "[1/7] Checking prerequisites..." -ForegroundColor Yellow

# Python
$python = Get-Command python -ErrorAction SilentlyContinue
if (-not $python) {
    Write-Error "Python not found. Install Python 3.11+ from https://python.org and ensure it's on PATH."
    exit 1
}
$pyVersion = & python --version 2>&1
Write-Host "  ✓ $pyVersion" -ForegroundColor Green

# pip
& python -m pip --version | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "pip not found. Run: python -m ensurepip --upgrade"
    exit 1
}
Write-Host "  ✓ pip available" -ForegroundColor Green

# ── 2. Create directory structure ─────────────────────────────────────────────
Write-Host "[2/7] Creating directory structure..." -ForegroundColor Yellow

$directories = @(
    $HermesHome,
    (Join-Path $HermesHome "logs"),
    (Join-Path $HermesHome "plugins" "icarus"),
    (Join-Path $HermesHome "cron" "output"),
    (Join-Path $HermesHome "cron" "output" "quality_report")
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        Write-Host "  + $dir" -ForegroundColor DarkGray
    } else {
        Write-Host "  ✓ $dir (exists)" -ForegroundColor Green
    }
}

# ── 3. Install Python dependencies ───────────────────────────────────────────
Write-Host "[3/7] Installing Python dependencies..." -ForegroundColor Yellow

$reqFile = Join-Path $RepoRoot "requirements.txt"
if (Test-Path $reqFile) {
    if (-not $DryRun) {
        & python -m pip install -r $reqFile --quiet
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Some pip packages failed. You may need Visual Studio Build Tools for fastembed C extensions."
            Write-Host "  → Install from: https://visualstudio.microsoft.com/visual-cpp-build-tools/"
            Write-Host "  → Select 'Desktop development with C++' workload"
        } else {
            Write-Host "  ✓ Python dependencies installed" -ForegroundColor Green
        }
    } else {
        Write-Host "  [DRY RUN] Would install from $reqFile"
    }
} else {
    Write-Warning "requirements.txt not found at $reqFile"
}

# Worker dependencies (same packages needed for running worker natively)
$workerReqFile = Join-Path $RepoRoot "docker" "worker" "requirements.txt"
if (Test-Path $workerReqFile) {
    if (-not $DryRun) {
        & python -m pip install -r $workerReqFile --quiet
        Write-Host "  ✓ Worker dependencies installed" -ForegroundColor Green
    }
}

# ── 4. Install Redis ─────────────────────────────────────────────────────────
if (-not $SkipServices) {
    Write-Host "[4/7] Setting up Redis..." -ForegroundColor Yellow

    $redisCmd = Get-Command redis-server -ErrorAction SilentlyContinue
    if ($redisCmd) {
        Write-Host "  ✓ Redis already installed: $($redisCmd.Source)" -ForegroundColor Green
    } else {
        Write-Host "  Redis is not installed. Install options:" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "  Option A — winget (recommended):" -ForegroundColor White
        Write-Host "    winget install Redis.Redis" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Option B — Memurai (Redis-compatible, native Windows):" -ForegroundColor White
        Write-Host "    https://www.memurai.com/get-memurai" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  Option C — Chocolatey:" -ForegroundColor White
        Write-Host "    choco install redis-64" -ForegroundColor DarkGray
        Write-Host ""
        Write-Host "  After installing, set REDIS_PASSWORD and restart this script."
    }

    # ── 5. Install Qdrant ─────────────────────────────────────────────────────
    Write-Host "[5/7] Setting up Qdrant..." -ForegroundColor Yellow

    $qdrantExe = Join-Path $QdrantDir "qdrant.exe"
    if (Test-Path $qdrantExe) {
        Write-Host "  ✓ Qdrant already installed at $qdrantExe" -ForegroundColor Green
    } else {
        $arch = if ([System.Environment]::Is64BitOperatingSystem) { "x86_64" } else { "x86_64" }
        $qdrantUrl = "https://github.com/qdrant/qdrant/releases/download/v${QdrantVersion}/qdrant-x86_64-pc-windows-msvc.zip"
        $qdrantZip = Join-Path $env:TEMP "qdrant-${QdrantVersion}.zip"

        Write-Host "  Downloading Qdrant v${QdrantVersion}..."
        if (-not $DryRun) {
            try {
                Invoke-WebRequest -Uri $qdrantUrl -OutFile $qdrantZip -UseBasicParsing
                New-Item -ItemType Directory -Path $QdrantDir -Force | Out-Null
                Expand-Archive -Path $qdrantZip -DestinationPath $QdrantDir -Force
                Remove-Item $qdrantZip -Force
                Write-Host "  ✓ Qdrant extracted to $QdrantDir" -ForegroundColor Green
            } catch {
                Write-Warning "Failed to download Qdrant automatically."
                Write-Host "  → Manual download: $qdrantUrl"
                Write-Host "  → Extract to: $QdrantDir"
            }
        } else {
            Write-Host "  [DRY RUN] Would download from $qdrantUrl"
        }
    }

    # Create Qdrant storage directory
    $qdrantStorage = Join-Path $QdrantDir "storage"
    if (-not (Test-Path $qdrantStorage)) {
        if (-not $DryRun) { New-Item -ItemType Directory -Path $qdrantStorage -Force | Out-Null }
    }
} else {
    Write-Host "[4/7] Skipping Redis setup (--SkipServices)" -ForegroundColor DarkGray
    Write-Host "[5/7] Skipping Qdrant setup (--SkipServices)" -ForegroundColor DarkGray
}

# ── 6. Initialise databases ──────────────────────────────────────────────────
Write-Host "[6/7] Initialising databases..." -ForegroundColor Yellow

$setupDb = Join-Path $RepoRoot "setup" "setup_db.py"
if (Test-Path $setupDb) {
    $stateDb  = $env:STATE_DB_PATH ?? (Join-Path $HermesHome "state.db")
    $memoryDb = $env:MEMORY_STORE_PATH ?? (Join-Path $HermesHome "memory_store.db")

    if (-not $DryRun) {
        & python $setupDb --state-db $stateDb --memory-db $memoryDb
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  ✓ Databases initialised" -ForegroundColor Green
        } else {
            Write-Warning "Database setup returned exit code $LASTEXITCODE"
        }
    } else {
        Write-Host "  [DRY RUN] Would run: python $setupDb --state-db $stateDb --memory-db $memoryDb"
    }
} else {
    Write-Warning "setup_db.py not found at $setupDb"
}

# ── 7. Register scheduled tasks ──────────────────────────────────────────────
if (-not $SkipScheduledTasks -and -not $SkipServices) {
    Write-Host "[7/7] Registering Windows scheduled tasks..." -ForegroundColor Yellow

    $pythonPath = (Get-Command python).Source
    $scriptsDir = Join-Path $RepoRoot "scripts"

    $tasks = @(
        @{
            Name        = "MemoryOS-WikiContinuousIngest"
            Script      = "wiki_continuous_ingest.py"
            Description = "Memory OS: Hourly wiki file diff detection and ARQ ingestion"
            Trigger     = New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Hours 1)
        },
        @{
            Name        = "MemoryOS-DecayScanner"
            Script      = "decay_scanner.py"
            Description = "Memory OS: Weekly archive of low-importance Qdrant points"
            Trigger     = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At "03:00"
        },
        @{
            Name        = "MemoryOS-DLQManager"
            Script      = "dlq_manager.py"
            Description = "Memory OS: Dead letter queue monitoring (every 6h)"
            Trigger     = New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Hours 6)
        },
        @{
            Name        = "MemoryOS-SemanticDedup"
            Script      = "semantic_dedup.py"
            Description = "Memory OS: Monthly near-duplicate vector cleanup"
            Trigger     = New-ScheduledTaskTrigger -Monthly -DaysOfMonth 1 -At "03:00" -MonthsOfYear 1,2,3,4,5,6,7,8,9,10,11,12
        },
        @{
            Name        = "MemoryOS-ReflectionTrigger"
            Script      = "reflection_trigger.py"
            Description = "Memory OS: Micro-reflection idle detection (every 5 min)"
            Trigger     = New-ScheduledTaskTrigger -Once -At "00:00" -RepetitionInterval (New-TimeSpan -Minutes 5)
        }
    )

    foreach ($task in $tasks) {
        $scriptPath = Join-Path $scriptsDir $task.Script
        if (-not (Test-Path $scriptPath)) {
            Write-Warning "  Script not found: $scriptPath — skipping $($task.Name)"
            continue
        }

        $existingTask = Get-ScheduledTask -TaskName $task.Name -ErrorAction SilentlyContinue
        if ($existingTask) {
            Write-Host "  ✓ $($task.Name) (already registered)" -ForegroundColor Green
            continue
        }

        if (-not $DryRun) {
            try {
                $action = New-ScheduledTaskAction -Execute $pythonPath -Argument "`"$scriptPath`"" -WorkingDirectory $RepoRoot
                Register-ScheduledTask -TaskName $task.Name -Action $action -Trigger $task.Trigger `
                    -Description $task.Description -RunLevel Highest -Force | Out-Null
                Write-Host "  + $($task.Name)" -ForegroundColor Green
            } catch {
                Write-Warning "  Failed to register $($task.Name): $_"
            }
        } else {
            Write-Host "  [DRY RUN] Would register: $($task.Name)"
        }
    }
} else {
    Write-Host "[7/7] Skipping scheduled tasks" -ForegroundColor DarkGray
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Setup complete                              ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "  1. Copy .env.example to .env and fill in your values"
Write-Host "  2. Start Redis:  redis-server --requirepass YOUR_PASSWORD"
Write-Host "  3. Start Qdrant: $QdrantDir\qdrant.exe"
Write-Host "  4. Start ARQ worker: python docker\worker\main.py --run-worker"
Write-Host "  5. Copy icarus/ to $HermesHome\plugins\icarus\"
Write-Host "  6. Restart Hermes gateway: hermes gateway restart"
Write-Host ""
Write-Host "See setup/install_windows.md for full documentation."
Write-Host ""
