---
name: qt6-build
description: 本プロジェクトの Qt6 + CMake 構成・ビルド・実行手順。新しい開発環境でセットアップする時、ビルドが通らなくなった時、CI を作る時に参照する。macOS 14+ の AGL 罠回避手順を含む。
origin: hmi-platform
---

# Qt6 + CMake ビルド手順

## 適用タイミング（When to Use）

- 新しい開発機でセットアップする時
- `cmake` 系のコマンドを叩く必要がある時
- ビルドが通らなくなった / リンカエラーが出た時
- CI / cron 化を検討する時

## 必要環境

- Qt **6.8 以上**（macOS 14+ では Qt 6.7 以前は AGL.framework 不在でリンク不可）
- CMake **3.21 以上**
- C++17 対応コンパイラ

macOS の推奨セットアップ：

```sh
brew install qt
# → /opt/homebrew/opt/qt （現時点で 6.11.1）
```

Windows の推奨セットアップ：

- Qt Online Installer から **Qt 6.11.0 MinGW 64-bit** kit と付属 MinGW 13.1 / Ninja / CMake を一括導入（既定 `C:\Qt`）
- MSVC kit は本プロジェクトでは現状未使用（Qt 側に MSVC kit を入れていないため）

## 標準コマンド

### macOS

```sh
# 構成
cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt

# 全体ビルド
cmake --build build

# 個別ターゲット
cmake --build build --target hmi_editor
cmake --build build --target hmi_simulator
cmake --build build --target hmi_runtime    # Phase 3-B-1 / Task 22 以降。Simulator のソース共有 PC ビルド
cmake --build build --target hmi_schema
cmake --build build --target hmi_widgets

# 起動
./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor
./build/Simulator/hmi_simulator.app/Contents/MacOS/hmi_simulator
./build/Runtime/hmi_runtime.app/Contents/MacOS/hmi_runtime --open <path/to/project.json>
```

### Windows（PowerShell）

補助スクリプト経由が最短ルート（PATH 整備 + configure + build を一括）：

```powershell
.\scripts\windows\build.ps1                  # 全体
.\scripts\windows\build.ps1 -Target hmi_editor
.\scripts\windows\build.ps1 -Reconfigure     # build-mingw を消して再構成
```

手動で叩く場合：

```powershell
. .\scripts\windows\setup-env.ps1            # 必ず dot-source
cmake -S . -B build-mingw -G Ninja `
  -DCMAKE_PREFIX_PATH=C:\Qt\6.11.0\mingw_64 `
  -DCMAKE_CXX_COMPILER=C:/Qt/Tools/mingw1310_64/bin/g++.exe
cmake --build build-mingw

# 起動（setup-env.ps1 後）
.\build-mingw\hmi_editor.exe
.\build-mingw\hmi_simulator.exe
.\build-mingw\hmi_runtime.exe --open <path\to\project.json>   # Phase 3-B-1 / Task 22 以降
```

実行ファイル出力先は macOS とは異なり、ビルドツリーのトップ（`build-mingw\hmi_editor.exe`）になる（hmi_runtime も同じく `build-mingw\hmi_runtime.exe`）。

### Windows: Explorer ダブルクリック起動用デプロイ（windeployqt）

`setup-env.ps1` を dot-source した開発シェルから起動する分には不要だが、**Explorer からダブルクリックで開きたい**場合は Qt6 DLL・MinGW ランタイム・プラグインを exe の隣へ配置する：

```powershell
.\scripts\windows\deploy.ps1                 # 両 exe に windeployqt を実行
.\scripts\windows\build.ps1 -Deploy          # build と同時に実行する場合
```

- 中身は `windeployqt --release --compiler-runtime --qmldir <qml>`。Qt6 DLL・MinGW ランタイム（`libstdc++-6.dll` 等）・プラグイン（`platforms\qwindows.dll`）・QML モジュールを exe の隣へ配置して自己完結させる。
- **`build-mingw` をクリーン消去した後は再実行が必要**（DLL も消えるため）。
- Explorer で「Qt の DLL が見つからない」エラーが出るのは、`setup-env.ps1` 未読込のシェル / Explorer が Qt・MinGW の `bin` を PATH に持たないため。`deploy.ps1` で解消する。

### Windows: exe アイコン埋め込み（Atlas ブランド）

3 つの exe（hmi_editor / hmi_simulator / hmi_runtime）には Atlas ブランドアイコンが埋め込まれる（Explorer・タスクバー・ウィンドウタイトルバーに表示）。

```powershell
.\scripts\windows\generate-icon.ps1   # branding\atlas.ico を再生成（次のビルドで反映）
```

- 仕組み：ルート `CMakeLists.txt` で Windows 限定 `enable_language(RC)` → 各アプリの CMakeLists が `branding/app_icon.rc.in` を `configure_file` で `.rc` 化（`@HMI_APP_ICON_PATH@` に `branding/atlas.ico` の絶対パスを埋める）→ MinGW windres が exe へ焼き込む。
- **windeployqt とは独立**（アイコンは exe 自身に焼かれるので deploy 不要で出る）。Qt は exe 埋め込みアイコンを自動でウィンドウアイコンに採用するため、QML/C++ 側のコード変更は不要。
- アイコン画像の「唯一の真実」は `scripts/windows/generate-icon.ps1`（外部ツール無しで GDI+ 描画 → 16〜256px を PNG 圧縮 ICO にパック）。色・形を変えたいときはこれを編集して再実行する。

## 既知の罠（How It Works — pitfalls）

### 1. `framework 'AGL' not found`（macOS 14+）

**原因**：Qt 6.7 以前の `FindWrapOpenGL.cmake` が常に `-framework AGL` を要求するが、macOS 14 で SDK から削除済み。
**対処**：`CMAKE_PREFIX_PATH` を Qt 6.8+ に切り替える。**コード側を変えない**。

### 2. QML モジュール OUTPUT_DIRECTORY 警告

**原因**：`qt_add_qml_module` の `URI` と出力ディレクトリのパスが不一致。
**対処**：`OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/<URI最終要素>` を明示。
**事例**：Shared/Widgets では `OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/HmiWidgets` を指定済み。

### 3. STATIC ライブラリでソースが空

**原因**：`qt_add_library(... STATIC)` にソースが 1 つも無いと CMake が文句を言う。
**対処**：プレースホルダー .cpp を作る（例：`Shared/Schema/src/schema_placeholder.cpp` の `namespace hmi::schema {}`）。実装が入ったら削除。

### 4. `loadFromModule` で QML が見つからない

**原因**：アプリの `loadFromModule(URI, "Main")` の URI と `qt_add_qml_module` の `URI` が不一致。または `QML_FILES` に対象が無い。
**対処**：両者の URI を一致させ、`QML_FILES` に追加する。

### 5. Windows: PATH 汚染で別 MinGW / VS の cl.exe が優先される

**原因**：`C:\mingw64\bin`（別途インストールの古い MinGW）や VS 2015 の `cl.exe` が PATH 先頭にあると、CMake がそちらを掴んでしまい Qt 付属 MinGW 13.1 と ABI 不一致を起こす。
**対処**：`scripts/windows/setup-env.ps1` を dot-source して **Qt 付属 MinGW / Qt bin / Ninja / CMake を PATH 先頭に挿入**する。手動 `cmake` 実行時も `-DCMAKE_CXX_COMPILER=C:/Qt/Tools/mingw1310_64/bin/g++.exe` を明示すると安全。

### 6. Windows: 実行時に Qt6Core.dll が見つからない

**原因**：Qt の bin (`C:\Qt\6.11.0\mingw_64\bin`) が PATH に通っていないと、EXE 起動時にエラーダイアログが出る。
**対処**：起動前に `. .\scripts\windows\setup-env.ps1` を実行するか、シェル PATH に `C:\Qt\6.11.0\mingw_64\bin` を恒久的に追加する。

### 7. Windows: `.ps1` が ExecutionPolicy で拒否される

**原因**：Windows 既定の ExecutionPolicy は Restricted で、未署名 `.ps1` の直接起動を禁止する。VSCode のターミナルや素の `powershell.exe` で `.\scripts\windows\build.ps1` を叩くと `UnauthorizedAccess` が出る。
**対処**：初回セットアップ時に一度だけ `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force` を実行する（CurrentUser スコープなので管理者権限不要）。設定後は VSCode のターミナルを開き直す。

### 8. Windows PowerShell 5.1: `-DKEY=$var` 形式で変数が展開されない

**原因**：PS 5.1 の native コマンド引数渡しでは、`-DCMAKE_BUILD_TYPE=$BuildType` のように **裸で `=$var` を書くと `$var` がリテラル文字列として渡される**。結果として CMakeCache.txt に `CMAKE_BUILD_TYPE:STRING=$BuildType` のような壊れた値が入り、Ninja の rule 名にもリテラル展開されて `ninja: error: expected newline, got lexing error` が出る。
**対処**：引数全体を **ダブルクォートで囲む**（PS 側に文字列補間を強制）：

```powershell
cmake ... "-DCMAKE_BUILD_TYPE=$BuildType" "-DCMAKE_PREFIX_PATH=$env:QT_DIR"
```

シングルクォートで囲むと展開されないので注意。値に `:` を含む変数（`$env:QT_DIR` など）も同様にダブルクォート化が必要。

### 9. Windows PowerShell 5.1: BOM 無し UTF-8 スクリプトが文字化けする

**原因**：Windows PowerShell 5.1 は BOM 無し UTF-8 を ANSI（cp932）として解釈し、日本語コメントを含むスクリプトでパースエラー（`The string is missing the terminator`）になる。
**対処**：日本語を含む `.ps1` ファイルは **UTF-8 with BOM** で保存する。Edit/Write 直後は BOM が付かないことがあるので、必要に応じて以下で付け直す：

```powershell
$utf8Bom = [System.Text.UTF8Encoding]::new($true)
$c = [System.IO.File]::ReadAllText('path\to\script.ps1', [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText('path\to\script.ps1', $c, $utf8Bom)
```

### 10. Windows: 起動中の exe を落とさず再ビルドするとリンクが Permission denied で失敗

**原因**：Windows は実行中の exe を排他ロックするため、`hmi_editor.exe` / `hmi_simulator.exe` を起動したまま再ビルドするとリンカが上書きできず `cannot open output file ...: Permission denied` で落ちる（Task 27 で遭遇）。
**対処**：**コードのエラーではない**ので、`g++`/QML の構文を疑う前に `Get-Process hmi_editor | Stop-Process -Force` で起動中インスタンスを落としてから再ビルドする。動作確認で起動したアプリはキャプチャ後に必ず `Stop-Process` する運用にすると踏まない。

### 11. Windows: `deploy.ps1` 実行後に offscreen の QML ctest が数百秒ハングする

**原因**：`windeployqt` は `build-mingw\platforms\` に **`qwindows.dll` だけ**を配置するが、QML テスト exe（`tst_hmi_widgets_qml` / `tst_hmi_editor_qml`）は build-mingw 直下で動くため、この**ローカル `platforms\` が Qt 本体のプラグイン群（`qoffscreen.dll` 等）を隠す**。結果 `-platform offscreen` 起動が `0xc0000602`（STATUS_FAIL_FAST_EXCEPTION）で失敗し、「no Qt platform plugin could be initialized. Available platform plugins are: windows.」のモーダルダイアログが OK 待ちで張り付いて ctest が数百秒ハングする（563 秒の実測あり。Task 26 で発覚）。
**対処**：ctest 実行時に `$env:QT_QPA_PLATFORM_PLUGIN_PATH = "C:\Qt\6.11.0\mingw_64\plugins\platforms"` を設定して Qt 本体の完全なプラグイン集合を明示する（ローカル `platforms\` より優先される）。**または build-mingw をクリーン再ビルド**（`Remove-Item build-mingw -Recurse -Force; .\scripts\windows\build.ps1`）して配備物（`platforms\`・`qml\`・ローカル `Qt6*.dll`）を消すのが最も確実。`deploy.ps1` 未実行のクリーンな build-mingw では発生しない。デプロイ済みツリーで ctest が固まる／QML テストだけ `0xc0000602` で落ちたらこの罠を疑う（Task 29 でも再発。deploy は ctest と別フェーズで／別ディレクトリへ行うのが安全）。

### 12. CI（aqtinstall）: 最新 Qt バージョンは Updates.xml 未同期で取得失敗する

**原因**：`jurplel/install-qt-action@v4` にローカル開発と同じ最新版（例 `6.11.0`）を渡すと、Qt 公式 mirror の `Updates.xml` 同期遅れで `Failed to locate XML data for Qt version '6.11.0'` で落ちる（Task 15 初回ランで両 OS 再現）。
**対処**：CI では **1〜2 マイナー下げた安定取得可能なバージョン（現状 6.10.0）** を使う。Qt 6.x の minor 互換でテスト緑判定は維持される。バージョンを上げる時は事前に `aqt list-qt <host> desktop --spec "<X.Y>"` で取得可能性を確認する。詳細パターンは [Docs/archive/phase2-testing-plan.md](../../../Docs/archive/phase2-testing-plan.md) の「Task 15 で確立したパターン」を参照。

### 13. Windows PowerShell: `New-Object <型>(<算術式>, ...)` がカンマ演算子で誤パースされる

**原因**：PowerShell ではカンマ演算子 `,` が二項 `-`/`+`/`*` より優先順位が高いため、`New-Object Drawing.RectangleF($cx - $r, $cy - $r, ...)` は `$cx - ($r, $cy) - ...` のように配列を巻き込んで評価され、`[System.Object[]] does not contain a method named 'op_Subtraction'` で落ちる（アイコン生成スクリプト作成時に遭遇）。
**対処**：各引数を括弧で囲む（`($cx - $r), ($cy - $r), ...`）か、事前に変数へ代入してから渡す。メソッド呼び出し `$g.DrawLine($pen, $cx - $r, ...)` では引数が個別に評価されるためこの罠は出ない（`New-Object` = `-ArgumentList` に配列を渡す形に特有）。

## 関連エージェント

- ビルドエラーの根本対処は [cmake-build-resolver](../../agents/cmake-build-resolver.md) に委譲可能
