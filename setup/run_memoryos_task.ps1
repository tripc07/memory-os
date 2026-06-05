<#
.SYNOPSIS
    Run one Memory OS maintenance script with the active Hermes environment.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptName,

    [switch]$FirstDayOnly
)

$ErrorActionPreference = "Stop"

if ($FirstDayOnly -and (Get-Date).Day -ne 1) {
    Write-Host "Skipping $ScriptName because today is not the first day of the month."
    exit 0
}

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path (Join-Path $RepoRoot "requirements.txt"))) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}

$DefaultHermesHome = Join-Path $env:LOCALAPPDATA "hermes"
if (-not (Test-Path $DefaultHermesHome)) {
    $DefaultHermesHome = Join-Path $env:USERPROFILE ".hermes"
}

$HermesHome = if ($env:HERMES_HOME) { $env:HERMES_HOME } else { $DefaultHermesHome }
$env:HERMES_HOME = $HermesHome

function LoadEnvFile($path) {
    if (-not $path -or -not (Test-Path $path)) { return }
    Get-Content $path | ForEach-Object {
        $line = $_.Trim()
        if ($line -and -not $line.StartsWith("#")) {
            $parts = $line -split "=", 2
            if ($parts.Count -eq 2) {
                $key = $parts[0].Trim()
                $val = $parts[1].Trim().Trim('"')
                [System.Environment]::SetEnvironmentVariable($key, $val, "Process")
            }
        }
    }
}

$env:MAA_ENV_PATH = if ($env:MAA_ENV_PATH) { $env:MAA_ENV_PATH } else { Join-Path $HermesHome ".env" }
LoadEnvFile $env:MAA_ENV_PATH
LoadEnvFile (Join-Path $RepoRoot ".env")

$defaultPython = Join-Path $HermesHome "hermes-agent\venv\Scripts\python.exe"
if ($env:HERMES_PYTHON) {
    $python = $env:HERMES_PYTHON
} elseif (Test-Path $defaultPython) {
    $python = $defaultPython
} else {
    $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $pythonCmd) {
        throw "Python not found. Set HERMES_PYTHON or install Python 3.11+."
    }
    $python = $pythonCmd.Source
}

$scriptPath = Join-Path (Join-Path $RepoRoot "scripts") $ScriptName
if (-not (Test-Path $scriptPath)) {
    throw "Memory OS script not found: $scriptPath"
}

Set-Location $RepoRoot
& $python $scriptPath
exit $LASTEXITCODE
