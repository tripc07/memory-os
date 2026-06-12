<#
.SYNOPSIS
    Register startup task for Memory OS + Jan services.

.DESCRIPTION
    Creates a Windows Task Scheduler task that runs at logon to auto-start
    all Memory OS services (Redis, Qdrant, ARQ Worker, Jan AI).
    Ideal for reboot recovery.

.EXAMPLE
    .\\setup\\register_startup_task.ps1
    .\\setup\\register_startup_task.ps1 -Detach # Start Jan in background mode
#>

[CmdletBinding()]
param(
    [switch]$Detach
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent $PSScriptRoot
$TaskRunner = Join-Path $RepoRoot "setup\start_all.ps1"

if (-not (Test-Path $TaskRunner)) {
    Write-Error "start_all.ps1 not found at $TaskRunner"
    exit 1
}

$taskArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$TaskRunner`""
if ($Detach) { $taskArgs += " -Detach" }

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $taskArgs -WorkingDirectory $RepoRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn

try {
    Register-ScheduledTask -TaskName "MemoryOS-AutoStart" -Action $action -Trigger $trigger -Description "Start Memory OS and Jan AI services at logon" -Force
    Write-Host "  [OK] Registered MemoryOS-AutoStart task" -ForegroundColor Green
    Write-Host "  Services will start automatically at next logon" -ForegroundColor Cyan
} catch {
    Write-Warning "Failed to register task. Try running as Administrator."
    Write-Warning $_
}

Write-Host ""
Write-Host "To remove the auto-start task: Unregister-ScheduledTask -TaskName 'MemoryOS-AutoStart' -Confirm:`$false" -ForegroundColor Yellow