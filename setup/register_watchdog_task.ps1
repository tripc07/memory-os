<#
.SYNOPSIS
    Register a lightweight scheduled task to keep Memory OS services running.
    Runs every 5 minutes - only starts services if they're offline.
#>

$taskName = "Memory OS Watchdog"
$watcherScript = "python"
$watcherArgs = "`"$HOME\memory-os\setup\memory_os_watchdog.py`""

# Create the scheduled task (runs only when services are down, minimal overhead)
$action = New-ScheduledTaskAction -Execute $watcherScript -Argument $watcherArgs
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 365)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

# Run under current user context
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Force

Write-Host "Scheduled task '$taskName' created - runs every 5 minutes" -ForegroundColor Green
Write-Host "To view: Get-ScheduledTask -TaskName '$taskName'" -ForegroundColor Cyan
Write-Host "To remove: Unregister-ScheduledTask -TaskName '$taskName' -Confirm:`$false" -ForegroundColor Cyan