# Setup Guide

> Step-by-step installation of the Memory OS stack on Windows.
> All services (Redis, Qdrant, ARQ Worker) run as native Windows processes — no Docker or WSL required.

## Prerequisites

| Requirement | Version | Notes |
|---|---|---|
| Windows | 10 21H2+ or 11 | x64 required |
| Python | 3.11+ | Install from [python.org](https://python.org) — check "Add to PATH" |
| Hermes Agent | 0.14.0+ | Tested on 0.15.2 |
| Visual Studio Build Tools | 2022+ | Required for fastembed C extensions ([download](https://visualstudio.microsoft.com/visual-cpp-build-tools/)) — select "Desktop development with C++" workload |
| OpenRouter API key | — | Only if using OpenRouter as embedding backend |

## Quick Start (automated)

```powershell
# Clone the repository
cd C:\Users\your-user
git clone https://github.com/tripc07/memory-os.git
cd memory-os

# Run the setup script (as Administrator for scheduled task registration)
powershell -ExecutionPolicy Bypass -File .\setup\setup_windows.ps1
```

The script will:
1. Validate Python and pip
2. Create the `~\.hermes` directory structure
3. Install Python dependencies (host + worker)
4. Download and extract Qdrant v1.17.1 for Windows
5. Initialise SQLite databases (`state.db`, `memory_store.db`)
6. Register Windows Task Scheduler jobs (replacing cron)

## Manual Setup

### 1. Install Redis

Redis does not have an official Windows build. Choose one option:

**Option A — winget (easiest):**
```powershell
winget install Redis.Redis
```

**Option B — Memurai (Redis-compatible, native Windows, recommended for production):**
Download from [memurai.com](https://www.memurai.com/get-memurai). Memurai is a Redis-compatible server built natively for Windows.

**Option C — Chocolatey:**
```powershell
choco install redis-64
```

After installing, verify:
```powershell
redis-server --version
redis-cli ping   # → PONG
```

### 2. Install Qdrant

Download the Windows binary from the [Qdrant releases page](https://github.com/qdrant/qdrant/releases):

```powershell
# Download and extract (the setup script does this automatically)
$version = "1.17.1"
$url = "https://github.com/qdrant/qdrant/releases/download/v${version}/qdrant-x86_64-pc-windows-msvc.zip"
Invoke-WebRequest -Uri $url -OutFile qdrant.zip
Expand-Archive qdrant.zip -DestinationPath "$env:LOCALAPPDATA\qdrant"
Remove-Item qdrant.zip
```

Verify:
```powershell
& "$env:LOCALAPPDATA\qdrant\qdrant.exe" --version
```

### 3. Install Python Dependencies

```powershell
pip install -r requirements.txt
pip install -r worker\requirements.txt
```

> **Note:** If `fastembed` fails to install, ensure Visual Studio Build Tools are installed with the "Desktop development with C++" workload.

### 4. Initialise Databases

```powershell
python setup\setup_db.py
```

Or with custom paths:
```powershell
$env:STATE_DB_PATH = "C:\Users\your-user\.hermes\state.db"
$env:MEMORY_STORE_PATH = "C:\Users\your-user\.hermes\memory_store.db"
python setup\setup_db.py --state-db $env:STATE_DB_PATH --memory-db $env:MEMORY_STORE_PATH
```

### 5. Configure Environment

```powershell
Copy-Item .env.example .env
notepad .env
```

**Windows-specific paths in `.env`:**
```ini
# Use forward slashes — Python's pathlib handles them on Windows
FABRIC_DIR=C:/Users/your-user/vault/fabric
VAULT_PATH=C:/Users/your-user/vault
WIKI_ROOT=C:/Users/your-user/vault/wiki
HERMES_HOME=C:/Users/your-user/.hermes
STATE_DB_PATH=C:/Users/your-user/.hermes/state.db
MEMORY_STORE_PATH=C:/Users/your-user/.hermes/memory_store.db
HERMES_LOGS_DIR=C:/Users/your-user/.hermes/logs
MAA_ENV_PATH=C:/Users/your-user/memory-os/.env

# Native mode — services run on localhost
REDIS_HOST=127.0.0.1
QDRANT_HOST=localhost

# If using Ollama locally (recommended for Windows):
EMBEDDING_API_BASE=http://localhost:11434/v1
EMBEDDING_MODEL=nomic-embed-text
```

### 6. Install Icarus Plugin

```powershell
Copy-Item -Recurse icarus\ "$env:USERPROFILE\.hermes\plugins\icarus\"
```

### 7. Create Wiki Directory Structure

```powershell
$vaultPath = "C:\Users\your-user\vault"
$dirs = @("wiki\raw", "wiki\concepts", "wiki\entities", "wiki\comparisons", "wiki\_meta", "wiki\_archive")
foreach ($d in $dirs) { New-Item -ItemType Directory -Path (Join-Path $vaultPath $d) -Force }
```

## Running Services

### Start all services:
```powershell
.\setup\start_services.ps1
```

### Start individually:
```powershell
# Redis
redis-server --port 6379 --bind 127.0.0.1 --requirepass YOUR_PASSWORD --appendonly yes

# Qdrant
& "$env:LOCALAPPDATA\qdrant\qdrant.exe"

# ARQ Worker (from repo root)
$env:REDIS_HOST = "127.0.0.1"
$env:QDRANT_HOST = "localhost"
python worker\main.py --run-worker
```

### Stop all services:
```powershell
.\setup\stop_services.ps1
```

### Verify:
```powershell
# Redis
redis-cli -a YOUR_PASSWORD ping
# → PONG

# Qdrant
Invoke-RestMethod http://localhost:6333/healthz
# → @{title=ok; version=1.17.1}
```

## Scheduled Tasks (replaces cron)

The setup script registers these Windows Task Scheduler jobs:

| Task Name | Schedule | Script |
|---|---|---|
| `MemoryOS-WikiContinuousIngest` | Every 1 hour | `wiki_continuous_ingest.py` |
| `MemoryOS-DecayScanner` | Sunday 3:00 AM | `decay_scanner.py` |
| `MemoryOS-DLQManager` | Every 6 hours | `dlq_manager.py` |
| `MemoryOS-SemanticDedup` | 1st of each month | `semantic_dedup.py` |
| `MemoryOS-ReflectionTrigger` | Every 5 minutes | `reflection_trigger.py` |

### Managing tasks manually:

```powershell
# View all Memory OS tasks
Get-ScheduledTask -TaskName "MemoryOS-*"

# Run a task now
Start-ScheduledTask -TaskName "MemoryOS-WikiContinuousIngest"

# Disable a task
Disable-ScheduledTask -TaskName "MemoryOS-ReflectionTrigger"

# Remove all Memory OS tasks
Get-ScheduledTask -TaskName "MemoryOS-*" | Unregister-ScheduledTask -Confirm:$false
```

## Architecture

| Component | How it runs |
|---|---|
| Redis | Native Windows binary or Memurai |
| Qdrant | Native `.exe` from GitHub releases |
| ARQ Worker | `python worker\main.py --run-worker` |
| Networking | `127.0.0.1` / `localhost` |
| Scheduling | Windows Task Scheduler |
| Log files | `%USERPROFILE%\.hermes\logs\` |
| Data volumes | Local directories |
| Embedding | `localhost:11434` for Ollama |

## Troubleshooting

### `fastembed` installation fails
Install Visual Studio Build Tools with the "Desktop development with C++" workload. Then retry `pip install fastembed`.

### Redis connection refused
Ensure Redis is running: `redis-cli ping`. If using Memurai, check that the Memurai service is started: `Get-Service Memurai`.

### Qdrant crashes on startup
Check that `%LOCALAPPDATA%\qdrant\storage\` directory exists. Also ensure port 6333 is not already in use: `netstat -an | findstr 6333`.

### Scripts can't find `.env`
Set `MAA_ENV_PATH` to the absolute path of your `.env` file:
```powershell
$env:MAA_ENV_PATH = "C:\Users\your-user\memory-os\.env"
```

### Path errors with backslashes
Always use forward slashes in `.env` file paths. Python's `pathlib` handles them correctly on Windows. Avoid `C:\Users\...` — use `C:/Users/...` instead.

### Worker can't connect to Redis/Qdrant
Ensure these environment variables are set:
```powershell
$env:REDIS_HOST = "127.0.0.1"
$env:QDRANT_HOST = "localhost"
```
