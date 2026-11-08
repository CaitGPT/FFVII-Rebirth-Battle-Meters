param(
    [string]$BuildDirectory = (Join-Path (Split-Path $PSScriptRoot -Parent) 'build\native'),
    [string]$Source = $PSScriptRoot
)
# Builds Battle Meters Native against pinned UE4SS v3.0.1 (c0a8d4c) sources and an import library for the UE4SS.dll you run.
# The machine's paths come from tools\build-config.local.json (not in git):
#   cmake              CMake that can drive Visual Studio 2022's C++ build tools
#   python             a Python that can run the interface script below
#   ue4ssWork          a folder with official-ue4ss-v3.0.1\ (RE-UE4SS template, UEPseudo, header deps) and BenchSlot2OfficialNoOp\UE4SS.lib
#   telemetryExporter  a folder with Prepare-InstalledUe4ssInterface.py, which extracts the installed build's mod interface
# The output is build\native\Release\main.dll, which the release puts in ue4ss\BattleMetersNative\dlls\.
$ErrorActionPreference = 'Stop'
$configPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'tools\build-config.local.json'
if (-not (Test-Path -LiteralPath $configPath)) { throw "Missing $configPath; see the comments at the top of this script." }
$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$work = $config.ue4ssWork
$sourceRoot = "$work\official-ue4ss-v3.0.1\UE4SSCPPTemplate\RE-UE4SS"
New-Item -ItemType Directory -Force $BuildDirectory | Out-Null
$interfaceRoot = Join-Path $BuildDirectory 'installed-interface'
& $config.python (Join-Path $config.telemetryExporter 'Prepare-InstalledUe4ssInterface.py') $sourceRoot $interfaceRoot
if ($LASTEXITCODE -ne 0) { throw 'Could not prepare the pinned installed-build interface.' }
& $config.cmake -S $Source -B $BuildDirectory -G 'Visual Studio 17 2022' -A x64 `
    "-DINSTALLED_INTERFACE=$interfaceRoot" `
    "-DUE4SS_SOURCE=$sourceRoot" `
    "-DUEPSEUDO_SOURCE=$work\official-ue4ss-v3.0.1\UEPseudo-authenticated" `
    "-DIMGUI_SOURCE=$work\official-ue4ss-v3.0.1\header-deps\imgui" `
    "-DIMGUI_TEXT_EDIT_SOURCE=$work\official-ue4ss-v3.0.1\header-deps\ImGuiColorTextEdit" `
    "-DZYDIS_SOURCE=$sourceRoot/../../header-deps/zydis-v4.1.0" `
    "-DUE4SS_IMPORT_LIB=$work\BenchSlot2OfficialNoOp\UE4SS.lib"
if ($LASTEXITCODE -ne 0) { throw "CMake configure failed with exit code $LASTEXITCODE" }
& $config.cmake --build $BuildDirectory --config Release -- /m
if ($LASTEXITCODE -ne 0) { throw "CMake build failed with exit code $LASTEXITCODE" }
$dll = Join-Path $BuildDirectory 'Release\main.dll'
if (-not (Test-Path -LiteralPath $dll)) { throw "Build did not produce $dll" }
Get-FileHash -Algorithm SHA256 -LiteralPath $dll
