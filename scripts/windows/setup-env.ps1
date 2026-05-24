# Windows 開発環境用 PATH セットアップ
#
# 使い方:
#   PS> . .\scripts\windows\setup-env.ps1
#
# ※ 必ず "dot-source"（先頭にピリオド + 半角スペース）で実行すること。
#    通常実行だと子プロセス内でしか PATH が変わらず、現在のシェルに反映されない。
#
# 役割:
#   - Qt 6.11.0 mingw_64 kit と付属 MinGW 13.1 / Ninja / CMake にパスを通す
#   - VS の cl.exe や別の MinGW より Qt 付属ツールが優先されるよう先頭に挿入する
#   - $env:QT_DIR をビルドスクリプトから参照できるよう公開する

$qtVersion = '6.11.0'
$qtRoot    = "C:\Qt\$qtVersion\mingw_64"
$mingwBin  = 'C:\Qt\Tools\mingw1310_64\bin'
$ninjaBin  = 'C:\Qt\Tools\Ninja'
$cmakeBin  = 'C:\Qt\Tools\CMake_64\bin'

foreach ($p in @($qtRoot, $mingwBin, $ninjaBin, $cmakeBin)) {
    if (-not (Test-Path $p)) {
        Write-Warning "Path not found: $p"
    }
}

$env:QT_DIR = $qtRoot
$env:PATH   = "$mingwBin;$qtRoot\bin;$ninjaBin;$cmakeBin;$env:PATH"

Write-Host "Qt:    $qtRoot"
Write-Host "MinGW: $mingwBin"
Write-Host "Ninja: $ninjaBin"
Write-Host "CMake: $cmakeBin"
Write-Host ''
Write-Host 'OK. これで cmake / ninja / qmake / gcc が Qt 付属版を指す。'
