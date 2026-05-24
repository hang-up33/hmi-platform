# Windows ワンショットビルド
#
# 使い方:
#   PS> .\scripts\windows\build.ps1                # configure + build
#   PS> .\scripts\windows\build.ps1 -Target hmi_editor
#   PS> .\scripts\windows\build.ps1 -Reconfigure   # build-mingw を消して configure からやり直し

param(
    [string]$BuildDir   = 'build-mingw',
    [string]$Target     = '',
    [string]$BuildType  = 'Debug',
    [switch]$Reconfigure
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'setup-env.ps1')

$repoRoot = Resolve-Path (Join-Path $scriptDir '..\..')
$buildPath = Join-Path $repoRoot $BuildDir

if ($Reconfigure -and (Test-Path $buildPath)) {
    Write-Host "Removing $buildPath"
    Remove-Item -Recurse -Force $buildPath
}

if (-not (Test-Path (Join-Path $buildPath 'CMakeCache.txt'))) {
    Write-Host '--- CMake configure ---'
    cmake -S $repoRoot -B $buildPath -G Ninja `
        -DCMAKE_PREFIX_PATH="$env:QT_DIR" `
        -DCMAKE_CXX_COMPILER='C:/Qt/Tools/mingw1310_64/bin/g++.exe' `
        -DCMAKE_BUILD_TYPE=$BuildType
    if ($LASTEXITCODE -ne 0) { throw "configure failed (exit $LASTEXITCODE)" }
}

Write-Host '--- CMake build ---'
if ($Target) {
    cmake --build $buildPath --target $Target
} else {
    cmake --build $buildPath
}
if ($LASTEXITCODE -ne 0) { throw "build failed (exit $LASTEXITCODE)" }

Write-Host ''
Write-Host 'Build OK.'
Write-Host "  Editor:    $buildPath\hmi_editor.exe"
Write-Host "  Simulator: $buildPath\hmi_simulator.exe"
