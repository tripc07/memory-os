<#
.SYNOPSIS
    Stop Memory OS services (Redis, Qdrant, ARQ Worker) on Windows.

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

$HermesHome = $env:HERMES_HOME ?? (Join-Path $env:USERPROFILE ".hermes")
$PidDir     = Join-Path $HermesHome "pids"

function ShouldStop($name) {
    if (-not $Only -or $Only.Count -eq 0) { return $true }
    return $Only -contains $name
}

$services = @("redis", "qdrant", "worker")

foreach ($svc in $services) {
    if (-not (ShouldStop $svc)) { continue }

    $pidFile = Join-Path $PidDir "$svc.pid"
    if (Test-Path $pidFile) {
        $pid = Get-Content $pidFile
        try {
            $proc = Get-Process -Id $pid -ErrorAction Stop
            Stop-Process -Id $pid -Force
            Write-Host "  ✓ Stopped $svc (PID $pid)" -ForegroundColor Green
        } catch {
            Write-Host "  ○ $svc not running (PID $pid)" -ForegroundColor DarkGray
        }
        Remove-Item $pidFile -Force
    } else {
        Write-Host "  ○ $svc — no PID file found" -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "Services stopped." -ForegroundColor Cyan
