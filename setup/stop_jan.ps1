<#
.SYNOPSIS
    Stop Jan AI model server on Windows.

.DESCRIPTION
    Reads the Jan PID file from $HERMES_HOME/pids/jan.pid and stops the process.
    Also checks for any lingering jan.exe processes.

.EXAMPLE
    .\\setup\\stop_jan.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$DefaultHermesHome = Join-Path $env:LOCALAPPDATA "hermes"
if (-not (Test-Path $DefaultHermesHome)) {
    $DefaultHermesHome = Join-Path $env:USERPROFILE ".hermes"
}
$HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { $DefaultHermesHome }
$JanPid = Join-Path $HermesHome "pids\jan.pid"

$stopped = $false

# Stop via PID file
if (Test-Path $JanPid) {
    try {
        $pidValue = Get-Content $JanPid -ErrorAction Stop
        $proc = Get-Process -Id ([int]$pidValue) -ErrorAction Stop
        if ($proc -and $proc.ProcessName -match "jan") {
            Stop-Process -Id $pidValue -Force -ErrorAction Stop
            Write-Host "  [OK] Stopped Jan (PID $pidValue)" -ForegroundColor Green
            $stopped = $true
        }
    } catch {
        Write-Host "  [--] Jan PID file exists but process not found" -ForegroundColor DarkGray
    }
    Remove-Item $JanPid -Force -ErrorAction SilentlyContinue
} else {
    Write-Host "  [--] No Jan PID file found at $JanPid" -ForegroundColor DarkGray
}

# Check for any remaining jan processes by port
$janPort = if ($env:JAN_PORT) { $env:JAN_PORT } else { "6767" }
$janProcesses = Get-NetTCPConnection -LocalPort $janPort -ErrorAction SilentlyContinue | ForEach-Object {
    (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).Id
}

foreach ($pid in $janProcesses) {
    try {
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc -and $proc.ProcessName -match "jan") {
            Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
            Write-Host "  [OK] Stopped orphan Jan process (PID $pid)" -ForegroundColor Green
            $stopped = $true
        }
    } catch {
        # Process may have exited
    }
}

if (-not $stopped) {
    Write-Host "  [--] Jan not running" -ForegroundColor DarkGray
}

Write-Host ""
Write-Host "Jan stopped." -ForegroundColor Cyan