<#
.SYNOPSIS
    Start Jan AI model server on Windows.

.DESCRIPTION
    Starts the Jan AI application as a local model server on localhost:6767/v1.
    Uses the installed Jan-v3.5-4B-Q4_K_XL model by default, or optionally
    starts the embedding model for Qdrant if configured.
    PID file is written to $HERMES_HOME/pids/jan.pid for stop_jan.ps1.

.EXAMPLE
    .\\setup\\start_jan.ps1
    .\\setup\\start_jan.ps1 -Model "janhq/Jan-code-4b-gguf"
    .\\setup\\start_jan.ps1 -Detach
#>

[CmdletBinding()]
param(
    [string]$Model = "Jan-v3.5-4B-Q4_K_XL",
    [switch]$Detach,
    [switch]$Embedding
)

$ErrorActionPreference = "Stop"

$DefaultHermesHome = Join-Path $env:LOCALAPPDATA "hermes"
if (-not (Test-Path $DefaultHermesHome)) {
    $DefaultHermesHome = Join-Path $env:USERPROFILE ".hermes"
}
$HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { $DefaultHermesHome }
$JanExe = Join-Path $env:LOCALAPPDATA "Programs\Jan\resources\bin\jan.exe"
$JanPid = Join-Path $HermesHome "pids\jan.pid"
$LogDir = if ($env:HERMES_LOGS_DIR) { $env:HERMES_LOGS_DIR } else { Join-Path $HermesHome "logs" }

# Ensure directories exist
New-Item -ItemType Directory -Path (Split-Path $JanPid) -Force | Out-Null
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

# Check if Jan is installed
if (-not (Test-Path $JanExe)) {
    Write-Error "Jan executable not found at $JanExe. Install Jan AI from https://jan.ai"
    exit 1
}

# Check if already running - detect port from EMBEDDING_API_BASE
$JanPort = $env:JAN_PORT
if (-not $JanPort) {
    if ($env:EMBEDDING_API_BASE -match 'localhost:(\d+)') { $JanPort = $matches[1] }
    elseif ($env:EMBEDDING_API_BASE -match '127.0.0.1:(\d+)') { $JanPort = $matches[1] }
}
if (-not $JanPort) { $JanPort = "6767" }

if (Test-Path $JanPid) {
    try {
        $existingPid = Get-Content $JanPid -ErrorAction Stop
        $proc = Get-Process -Id ([int]$existingPid) -ErrorAction Stop
        if ($proc) {
            Write-Host "  [OK] Jan already running (PID $existingPid)" -ForegroundColor Green
            exit 0
        }
    } catch {
        # Process not running, clean up stale PID file
        Remove-Item $JanPid -Force -ErrorAction SilentlyContinue
    }
}

# Check if port is already in use
$portInUse = Get-NetTCPConnection -LocalPort $JanPort -ErrorAction SilentlyContinue
if ($portInUse) {
    Write-Host "  [--] Port $JanPort already in use - Jan may be running" -ForegroundColor DarkGray
    exit 0
}

# Determine model path
$JanDataDir = Join-Path $env:APPDATA "Jan\data\llamacpp\models"
if ($Embedding) {
    $ModelName = "bge-m3-embeddings"
    $ModelPath = Join-Path $JanDataDir "bortunac\bge-m3-embeddings-Q4_K_M-GGUF\bge-m3-embeddings-q4_k_m.gguf"
    if (-not (Test-Path $ModelPath)) {
        Write-Warning "Embedding model not found at $ModelPath"
        Write-Warning "Run: jan.exe models list to see available models"
    }
} else {
    $ModelPath = Join-Path $JanDataDir "Jan-v3.5-4B-Q4_K_XL\model.gguf"
    if (-not (Test-Path $ModelPath)) {
        Write-Warning "Model not found at $ModelPath"
        Write-Warning "Checking for alternative models..."

        # Try to find any model
        $altModels = Get-ChildItem -Path $JanDataDir -Recurse -Filter "*.gguf" -ErrorAction SilentlyContinue | Select-Object -First 5
        if ($altModels) {
            Write-Host "  Available models:" -ForegroundColor Yellow
            foreach ($m in $altModels) {
                Write-Host "    $($m.FullName)"
            }
        } else {
            Write-Error "No models found. Download a model via Jan desktop app first."
            exit 1
        }
    }
}

# Build arguments - use EMBEDDING_MODEL if set for consistency
$JanModel = $Model
if ($env:EMBEDDING_MODEL -and $Model -eq "Jan-v3.5-4B-Q4_K_XL") {
    $JanModel = $env:EMBEDDING_MODEL
}

if ($Detach) {
    $Args = @("serve", $JanModel, "--detach")
} else {
    $Args = @("serve", $JanModel)
}

Write-Host "Starting Jan AI server ($JanModel) on port $JanPort..." -ForegroundColor Yellow
$JanLog = Join-Path $LogDir "jan.log"

# Start Jan in background
$proc = Start-Process -FilePath $JanExe -ArgumentList $Args -PassThru -WindowStyle Hidden
Set-Content -Path $JanPid -Value $proc.Id

Write-Host "  [OK] Jan started (PID $($proc.Id))" -ForegroundColor Green
Write-Host "  Endpoint: http://127.0.0.1:$JanPort/v1" -ForegroundColor Cyan

# Give it a moment to initialize
Start-Sleep -Seconds 2

# Verify
try {
    $resp = Invoke-RestMethod -Uri "http://127.0.0.1:$JanPort/v1/models" -TimeoutSec 5
    Write-Host "  [OK] Jan API responding" -ForegroundColor Green
} catch {
    Write-Warning "Jan may still be initializing. Check logs at $JanLog"