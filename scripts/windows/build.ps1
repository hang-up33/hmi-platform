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

# $ErrorActionPreference = 'Stop' は使わない。
# PS 5.1 は native コマンドの stderr 出力（cmake の警告など）を ErrorRecord として
# 例外化するため、Stop だと警告だけで build 全体が止まってしまう。
# 失敗判定は各 cmake 呼び出し後の $LASTEXITCODE で行う。

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'setup-env.ps1')

$repoRoot = Resolve-Path (Join-Path $scriptDir '..\..')
$buildPath = Join-Path $repoRoot $BuildDir

$cachePath = Join-Path $buildPath 'CMakeCache.txt'

# -Reconfigure 指定があれば問答無用で build ディレクトリを消す
if ($Reconfigure -and (Test-Path $buildPath)) {
    Write-Host "Removing $buildPath (-Reconfigure)"
    Remove-Item -Recurse -Force $buildPath
}

# CMAKE_BUILD_TYPE がキャッシュと不一致なら自動で再 configure する。
# Ninja は single-config generator のため、後から CMAKE_BUILD_TYPE を渡すだけでは
# キャッシュ済みの値が優先される可能性があり、意図と違う Debug/Release バイナリが
# 出来てしまう。安全側に倒して build ディレクトリごと作り直す。
if ((Test-Path $cachePath)) {
    $cachedType = ''
    $match = Select-String -Path $cachePath -Pattern '^CMAKE_BUILD_TYPE:[^=]*=(.*)$' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($match) { $cachedType = $match.Matches[0].Groups[1].Value.Trim() }
    if ($cachedType -ne $BuildType) {
        Write-Host "CMAKE_BUILD_TYPE 切替を検出 ('$cachedType' -> '$BuildType')。$buildPath を作り直します。"
        Remove-Item -Recurse -Force $buildPath
    }
}

if (-not (Test-Path $cachePath)) {
    Write-Host '--- CMake configure ---'
    # PS 5.1 の native コマンド引数渡しでは `-DKEY=$var` のように裸で書くと
    # `$var` が展開されずリテラルで渡される。`-DKEY=value` 全体をダブルクォートで
    # 囲むことで PS 側に文字列補間を強制する。
    cmake -S $repoRoot -B $buildPath -G Ninja -Wno-dev `
        "-DCMAKE_PREFIX_PATH=$env:QT_DIR" `
        "-DCMAKE_CXX_COMPILER=C:/Qt/Tools/mingw1310_64/bin/g++.exe" `
        "-DCMAKE_BUILD_TYPE=$BuildType"
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
