<#
.SYNOPSIS
    Stop Memory OS services (Redis, Qdrant, Ollama, llama.cpp, ARQ Worker) on Windows.

.DESCRIPTION
    Reads PID files from $HERMES_HOME/pids/ and stops the corresponding processes.

.EXAMPLE
    .\setup\stop_services.ps1
    .\setup\stop_services.ps1 -Only redis,worker
#>

[CmdletBinding()]
param(
    [string[]]$Only
)

$DefaultHermesHome = Join-Path $env:LOCALAPPDATA "hermes"
if (-not (Test-Path $DefaultHermesHome)) {
    $DefaultHermesHome = Join-Path $env:USERPROFILE ".hermes"
}
$HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { $DefaultHermesHome }
$PidDir     = Join-Path $HermesHome "pids"

function ShouldStop($name) {
    if (-not $Only -or $Only.Count -eq 0) { return $true }
    return $Only -contains $name
}

$services = @("redis", "qdrant", "ollama", "llamacpp", "worker")

foreach ($svc in $services) {
    if (-not (ShouldStop $svc)) { continue }

    $pidFile = Join-Path $PidDir "$svc.pid"
    if (Test-Path $pidFile) {
        $pidValue = Get-Content $pidFile
        try {
            $proc = Get-Process -Id $pidValue -ErrorAction Stop
            Stop-Process -Id $pidValue -Force
            Write-Host "  [OK] Stopped $svc (PID $pidValue)" -ForegroundColor Green
        } catch {
            Write-Host "  [--] $svc not running (PID $pidValue)" -ForegroundColor DarkGray
        }
        Remove-Item $pidFile -Force
    } else {
        Write-Host "  [--] $svc - no PID file found" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "Services stopped." -ForegroundColor Cyan
