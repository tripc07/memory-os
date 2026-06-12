<#
.SYNOPSIS
    Sync Memory OS integration files into the active Hermes home.

.DESCRIPTION
    Copies the Icarus Hermes plugin and local Memory OS .env into HERMES_HOME.
    This does not configure Hermes' primary model provider; llama.cpp remains a
    local Memory OS runtime dependency unless the user explicitly chooses it.
#>

[CmdletBinding()]
param(
    [string]$HermesHome,
    [switch]$EnablePlugin
)

$ErrorActionPreference = "Stop"

$RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path (Join-Path $RepoRoot "icarus\plugin.yaml"))) {
    $RepoRoot = Split-Path -Parent $PSScriptRoot
}
if (-not (Test-Path (Join-Path $RepoRoot "icarus\plugin.yaml"))) {
    throw "Could not locate repo root from $PSScriptRoot"
}

if (-not $HermesHome) {
    $HermesHome = if ($env:HERMES_HOME) {
        $env:HERMES_HOME
    } else {
        Join-Path $env:LOCALAPPDATA "hermes"
    }
}

$PluginSource = Join-Path $RepoRoot "icarus"
$PluginDest = Join-Path $HermesHome "plugins\icarus"
$EnvSource = Join-Path $RepoRoot ".env"
$EnvDest = Join-Path $HermesHome ".env"

New-Item -ItemType Directory -Path $PluginDest -Force | Out-Null
Copy-Item -Path (Join-Path $PluginSource "*") -Destination $PluginDest -Recurse -Force
Write-Host "  [OK] Synced Icarus plugin to $PluginDest" -ForegroundColor Green

if (Test-Path $EnvSource) {
    Copy-Item -LiteralPath $EnvSource -Destination $EnvDest -Force
    Write-Host "  [OK] Synced .env to $EnvDest" -ForegroundColor Green
} else {
    Write-Warning ".env not found at $EnvSource; Hermes will use its existing environment."
}

if ($EnablePlugin) {
    $hermes = Get-Command hermes -ErrorAction SilentlyContinue
    if ($hermes) {
        & $hermes.Source plugins enable icarus | Out-Host
    } else {
        Write-Warning "hermes command not found on PATH; enable the icarus plugin from Hermes manually."
    }
}

Write-Host ""
Write-Host "Hermes integration files are synced." -ForegroundColor Cyan
