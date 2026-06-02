# Windows: build-mingw の exe を windeployqt で自己完結（ポータブル）化する
#
# 使い方:
#   PS> .\scripts\windows\deploy.ps1                    # hmi_editor + hmi_simulator 両方
#   PS> .\scripts\windows\deploy.ps1 -Target hmi_editor
#
# 役割:
#   素の Explorer / 開発シェル外から exe をダブルクリック起動できるよう、
#   Qt6 DLL / MinGW ランタイム / プラグイン / QML モジュールを exe の隣に配置する。
#   （setup-env.ps1 を読み込んだ開発シェルから起動する分には PATH で解決されるので不要）。
#
# 注意:
#   build-mingw を消してクリーンビルドした後は DLL も消えるため再実行が必要。
#   exe をインクリメンタルに再ビルドしただけなら配置済み DLL は残り起動可能なまま。

param(
    [string]$BuildDir = 'build-mingw',
    [ValidateSet('all', 'hmi_editor', 'hmi_simulator')]
    [string]$Target = 'all'
)

# $ErrorActionPreference = 'Stop' は使わない（build.ps1 と同方針）。
# PS 5.1 は native コマンド（windeployqt）の stderr 出力を ErrorRecord 化するため、
# Stop だと警告だけで止まる。失敗判定は $LASTEXITCODE で行う。

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
# Qt/MinGW を PATH 先頭へ。windeployqt が --compiler-runtime の libstdc++ 等を
# MinGW bin から拾うために必要。$env:QT_DIR もここで公開される。
. (Join-Path $scriptDir 'setup-env.ps1')

$repoRoot  = Resolve-Path (Join-Path $scriptDir '..\..')
$buildPath = Join-Path $repoRoot $BuildDir

$windeployqt = Join-Path $env:QT_DIR 'bin\windeployqt.exe'
if (-not (Test-Path $windeployqt)) { throw "windeployqt が見つかりません: $windeployqt" }

# Qt の mingw_64 kit は release-only のため --release を明示する
# （Debug ビルドの exe も release の Qt6*.dll にリンクするので、自動判定に任せると
#  Qt6Cored.dll を探して失敗しうる）。--qmldir に QML ソースを渡し、QtQuick.Controls
# / QtQuick.Dialogs 等の QML プラグインも収集させる。
function Invoke-Deploy {
    param([string]$ExeName, [string]$QmlDir)

    $exe = Join-Path $buildPath "$ExeName.exe"
    if (-not (Test-Path $exe)) { throw "exe が見つかりません（先に build.ps1 を実行）: $exe" }

    Write-Host "--- windeployqt: $ExeName ---"
    & $windeployqt --release --compiler-runtime --qmldir (Join-Path $repoRoot $QmlDir) $exe
    if ($LASTEXITCODE -ne 0) { throw "windeployqt failed for $ExeName (exit $LASTEXITCODE)" }
}

if ($Target -eq 'all' -or $Target -eq 'hmi_editor')    { Invoke-Deploy -ExeName 'hmi_editor'    -QmlDir 'Editor\qml' }
if ($Target -eq 'all' -or $Target -eq 'hmi_simulator') { Invoke-Deploy -ExeName 'hmi_simulator' -QmlDir 'Simulator\qml' }

Write-Host ''
Write-Host 'Deploy OK. build-mingw の exe を Explorer からダブルクリック起動できます。'
