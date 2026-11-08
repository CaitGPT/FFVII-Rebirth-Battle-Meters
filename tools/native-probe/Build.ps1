param([string]$BuildDirectory = (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'build\native-probe'))
# Builds the development probe with the same toolchain as Battle Meters Native (see native\Build.ps1 for the
# tools\build-config.local.json it needs). Builds only; installing is a separate, booked step.
$ErrorActionPreference = 'Stop'
& (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'native\Build.ps1') -BuildDirectory $BuildDirectory -Source $PSScriptRoot
