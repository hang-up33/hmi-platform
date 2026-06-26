# Qt 6.11.0 MinGW 64-bit に qtopcua + open62541 backend を導入する
#
# 使い方:
#   PS> .\scripts\windows\build-opcua.ps1
#   PS> .\scripts\windows\build-opcua.ps1 -Force        # 既存を上書き再インストール
#   PS> .\scripts\windows\build-opcua.ps1 -SkipStageA   # 7z ダウンロードをスキップしてソースビルドへ
#   PS> .\scripts\windows\build-opcua.ps1 -WorkDir D:\Temp\opcua-build
#
# 動作:
#   Stage A: Qt サーバから qtopcua 7z をダウンロードしてマージ（SerialBus と同じ方法）
#            open62541 backend plugin が含まれれば完了。含まれなければ Stage B へ。
#   Stage B: open62541 と qtopcua を MinGW でソースビルドしてマージ（確実だが時間がかかる）
#
# 完了後: .\scripts\windows\build.ps1 -Reconfigure でプロジェクト全体を再ビルドする。
#
# 罠・詳細は .claude/rules/dev-environment.md「Windows qtopcua 導入」節を参照。

param(
    [string]$WorkDir    = "C:\Temp\opcua-build",
    [string]$QtDir      = "C:\Qt\6.11.0\mingw_64",
    [string]$MinGWBin   = "C:\Qt\Tools\mingw1310_64\bin",
    [switch]$Force,
    [switch]$SkipStageA
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'setup-env.ps1')

# --- ヘルパー ---

function Invoke-NativeCommand {
    param([string]$Desc, [scriptblock]$Cmd)
    Write-Host "  >> $Desc"
    & $Cmd
    if ($LASTEXITCODE -ne 0) { throw "$Desc 失敗 (exit $LASTEXITCODE)" }
}

function Expand-7z {
    param([string]$Archive, [string]$Dest)
    # py7zr (aqtinstall の依存) を使う。サブコマンドは "x"（extract ではない）
    python -m py7zr x $Archive $Dest
    if ($LASTEXITCODE -ne 0) {
        throw "7z 展開失敗: $Archive -> $Dest`npy7zr が無い場合は: pip install py7zr"
    }
}

# --- Stage A: 7z ダウンロード ---

function TryStageA {
    Write-Host ""
    Write-Host "=== Stage A: Qt サーバから 7z ダウンロード ==="

    # Qt バージョンを $QtDir パスから導出（例: C:\Qt\6.11.0\mingw_64 → "6.11.0" → "6110"）
    $stageAQtVer = ($QtDir -split '[\\\/]' | Where-Object { $_ -match '^\d+\.\d+\.\d+$' } | Select-Object -First 1)
    if (-not $stageAQtVer) { $stageAQtVer = "6.11.0" }
    $stageAQtVerParts   = $stageAQtVer -split '\.'
    $stageAQtVerCompact = $stageAQtVerParts[0] + $stageAQtVerParts[1] + $stageAQtVerParts[2]

    $base    = "https://download.qt.io/online/qtsdkrepository/windows_x86/desktop/qt6_$stageAQtVerCompact/qt6_${stageAQtVerCompact}_mingw"
    $pkgName = "qt.qt6.$stageAQtVerCompact.addons.qtopcua.win64_mingw"
    # Updates.xml はリポジトリルート直下にある（コンポーネント配下ではない）
    $xmlUrl  = "$base/Updates.xml"

    try {
        Write-Host "  Updates.xml 取得: $xmlUrl"
        $resp = Invoke-WebRequest -Uri $xmlUrl -UseBasicParsing -TimeoutSec 30 -ErrorAction Stop
        [xml]$updates = $resp.Content

        $pkg = $updates.Updates.PackageUpdate | Where-Object { $_.Name -eq $pkgName } | Select-Object -First 1
        if (-not $pkg) { throw "パッケージ '$pkgName' が Updates.xml に見つからない" }

        $ver      = $pkg.Version
        $archives = ($pkg.DownloadableArchives -split ', ') | Where-Object { $_ -like "*.7z" }
        if (-not $archives) { throw "7z アーカイブが Updates.xml に無い" }

        New-Item -Force -ItemType Directory $WorkDir | Out-Null

        foreach ($archive in $archives) {
            $fileUrl  = "$base/$pkgName/$ver$archive"
            # Qt MinGW addon リポジトリのチェックサムは .sha1（.sha256 は存在しない）
            $sha1Url  = "$fileUrl.sha1"
            $tmpFile  = Join-Path $WorkDir $archive
            $extractDir= Join-Path $WorkDir ("extracted-" + [System.IO.Path]::GetFileNameWithoutExtension($archive))

            Write-Host "  ダウンロード: $archive"
            Invoke-WebRequest -Uri $fileUrl -OutFile $tmpFile -UseBasicParsing

            Write-Host "  SHA1 検証..."
            $expected = ((Invoke-WebRequest -Uri $sha1Url -UseBasicParsing).Content.Trim() -split '\s+')[0].ToLower()
            $actual   = (Get-FileHash $tmpFile -Algorithm SHA1).Hash.ToLower()
            if ($actual -ne $expected) { throw "SHA1 不一致`n  expected: $expected`n  actual:   $actual" }
            Write-Host "  SHA1 OK"

            Write-Host "  展開: $extractDir"
            if (Test-Path $extractDir) { Remove-Item -Recurse -Force $extractDir }
            Expand-7z $tmpFile $extractDir

            # 展開後のサブディレクトリを Qt にマージ
            # Qt 7z は "<version>" サブディレクトリに入っている場合がある
            $srcRoot = $extractDir
            $subDirs = Get-ChildItem $extractDir -Directory
            if ($subDirs.Count -eq 1 -and $subDirs[0].Name -match '^\d') {
                $srcRoot = $subDirs[0].FullName
            }

            Write-Host "  Qt dir にマージ: $QtDir"
            Copy-Item -Path (Join-Path $srcRoot "*") -Destination $QtDir -Recurse -Force
        }

        # backend plugin の確認
        $backendDll = Get-ChildItem (Join-Path $QtDir "plugins\opcua") -Filter "*open62541*" -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($backendDll) {
            Write-Host "  Stage A 完了（backend plugin: $($backendDll.Name)）"
            return $true
        }
        else {
            Write-Host "  open62541 backend plugin が含まれていない -> Stage B へ進む"
            return $false
        }
    }
    catch {
        Write-Host "  Stage A スキップ: $_"
        return $false
    }
}

# --- Stage B: ソースビルド ---

function RunStageB {
    Write-Host ""
    Write-Host "=== Stage B: qtopcua ソースビルド（同梱 open62541 を使用） ==="
    Write-Host "  ※ 初回は 10〜30 分かかります"

    New-Item -Force -ItemType Directory $WorkDir | Out-Null

    $opcSrc = Join-Path $WorkDir "qtopcua"
    $opcBld = Join-Path $WorkDir "qtopcua-build"

    $gccExe = Join-Path $MinGWBin "gcc.exe"
    $gppExe = Join-Path $MinGWBin "g++.exe"

    # qtopcua のタグは Qt のインストール先パスからバージョンを取得して合わせる
    # 例: C:\Qt\6.11.0\mingw_64 -> v6.11.0
    $qtVer = ($QtDir -split '[\\\/]' | Where-Object { $_ -match '^\d+\.\d+\.\d+$' } | Select-Object -First 1)
    if (-not $qtVer) { $qtVer = "6.11.0" }
    $qtopcuaTag = "v$qtVer"

    # --- qtopcua ソース取得 ---
    if (-not (Test-Path $opcSrc)) {
        Write-Host ""
        Write-Host "  [1/3] qtopcua ソース取得 ($qtopcuaTag)..."
        Invoke-NativeCommand "git clone qtopcua" {
            git clone --depth 1 --branch $qtopcuaTag https://code.qt.io/qt/qtopcua.git $opcSrc
        }
    }

    # --- qtopcua ビルド・インストール ---
    # open62541 は qtopcua に同梱されているためシステム別ビルド不要。
    # INPUT_open62541 を指定しない（既定）と同梱版が使われ、
    # backend plugin (open62541_backend.dll) も同梱版でビルドされる。
    Write-Host ""
    Write-Host "  [2/3] qtopcua configure..."
    Invoke-NativeCommand "cmake configure qtopcua" {
        cmake -S $opcSrc -B $opcBld -G Ninja `
            "-DCMAKE_PREFIX_PATH=$QtDir" `
            "-DCMAKE_CXX_COMPILER=$gppExe" `
            "-DCMAKE_C_COMPILER=$gccExe" `
            "-DCMAKE_BUILD_TYPE=Release" `
            "-DCMAKE_INSTALL_PREFIX=$QtDir"
    }

    Write-Host ""
    Write-Host "  [3/3] qtopcua build + install..."
    Invoke-NativeCommand "cmake build qtopcua" {
        cmake --build $opcBld --parallel
    }
    Invoke-NativeCommand "cmake install qtopcua" {
        cmake --install $opcBld
    }
    Write-Host "  Stage B 完了"
}

# --- メイン ---

Write-Host "build-opcua.ps1 開始"
Write-Host "  Qt dir : $QtDir"
Write-Host "  WorkDir: $WorkDir"

# 既インストール確認
$cmakeDir = Join-Path $QtDir "lib\cmake\Qt6OpcUa"
$backendDllExisting = Get-ChildItem (Join-Path $QtDir "plugins\opcua") -Filter "*open62541*" -ErrorAction SilentlyContinue | Select-Object -First 1

if (-not $Force -and (Test-Path $cmakeDir) -and $backendDllExisting) {
    Write-Host ""
    Write-Host "qtopcua は既にインストール済み（-Force で上書き）"
    Write-Host "  cmake config : $cmakeDir"
    Write-Host "  backend DLL  : $($backendDllExisting.FullName)"
    exit 0
}

$stageADone = $false
if (-not $SkipStageA) {
    $stageADone = TryStageA
}

if (-not $stageADone) {
    RunStageB
}

# --- 検証 ---
Write-Host ""
Write-Host "=== 検証 ==="

$cmakeOk  = Test-Path $cmakeDir
$backendOk = $null -ne (Get-ChildItem (Join-Path $QtDir "plugins\opcua") -Filter "*open62541*" -ErrorAction SilentlyContinue | Select-Object -First 1)
$headerOk  = Test-Path (Join-Path $QtDir "include\QtOpcUa")

Write-Host "  cmake config  : $(if ($cmakeOk)  { 'OK' } else { 'NG - ' + $cmakeDir })"
Write-Host "  backend plugin: $(if ($backendOk) { 'OK' } else { 'NG - plugins\opcua\*open62541* が見つからない' })"
Write-Host "  headers       : $(if ($headerOk)  { 'OK' } else { 'NG - include\QtOpcUa が見つからない' })"

if ($cmakeOk -and $backendOk -and $headerOk) {
    Write-Host ""
    Write-Host "全 OK。次のステップ:"
    Write-Host "  .\scripts\windows\build.ps1 -Reconfigure"
}
else {
    Write-Warning "インストールが不完全。上記の NG 項目を確認してください。"
    Write-Warning "-SkipStageA スイッチでソースビルドを強制することもできます。"
    exit 1
}
