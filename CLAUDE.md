# CLAUDE.md

このファイルは、本リポジトリで作業する Claude Code（claude.ai/code）への指針です。
**ユーザーは日本人のため、応答・ドキュメント・コミットメッセージは日本語を基本とします**（コード識別子は英語可）。

---

## プロジェクト概要

Yocto / i.MX8M Plus 向け Qt6 HMI ランタイムを対象に、HMI 作画ツール（Editor）・PC 試験環境（Simulator）・実機ランタイム（Runtime）・JSON スキーマ（Shared/Schema）・共有 Widget（Shared/Widgets）を統合した開発基盤。詳細は [README.md](README.md)。

**現在のフェーズ**：MVP（Editor で配置・保存／Simulator で表示）を 1 タスクずつ完成させている段階。

---

## コア原則

1. **1 タスクずつ完結** — 設計書の MVP タスク順を厳守し、各タスクは `cmake --build` 成功を完了基準とする。
2. **Shared/Schema が唯一の真実** — Widget / Screen / Project に該当する型・JSON 入出力はここにのみ定義。
3. **継続的改善（kaizen）の遵守** — タスク完了報告の前に、得た知見を CLAUDE.md / README / メモリ / 設定のいずれかに反映する（[kaizen-close](.claude/skills/kaizen-close/SKILL.md) スキルで標準化）。
4. **既存資産の保護** — フォルダ構成変更禁止・既存コード削除禁止（例外は明示されたプレースホルダーのみ）。
5. **計画してから実装** — 複雑なタスクはエージェントに計画させてから手を動かす。

---

## ビルドと実行

### macOS

```sh
# 構成（Qt 6.8 以上を指す。後述「Qt バージョンの罠」参照）
cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt

# 全体ビルド
cmake --build build

# 個別ターゲット
cmake --build build --target hmi_editor
cmake --build build --target hmi_simulator
cmake --build build --target hmi_schema
cmake --build build --target hmi_widgets

# 起動
./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor
./build/Simulator/hmi_simulator.app/Contents/MacOS/hmi_simulator
```

### Windows（PowerShell）

```powershell
# configure + build （build-mingw/ に出力）
.\scripts\windows\build.ps1
.\scripts\windows\build.ps1 -Target hmi_editor
.\scripts\windows\build.ps1 -Reconfigure

# 起動（build.ps1 実行後はそのまま起動可。新シェルなら setup-env.ps1 を dot-source）
. .\scripts\windows\setup-env.ps1
.\build-mingw\hmi_editor.exe
.\build-mingw\hmi_simulator.exe
```

Windows は **Qt 6.11.0 MinGW 64-bit kit + 付属 MinGW 13.1 + Ninja** を前提とする（MSVC kit は未使用）。`scripts/windows/setup-env.ps1` が Qt 付属ツールチェイン（MinGW / Ninja / CMake）を PATH 先頭に挿入することで、システム側の VS `cl.exe` や別 MinGW を回避する。詳細・罠は [qt6-build](.claude/skills/qt6-build/SKILL.md) スキル参照。

テスト・lint・フォーマッタは未整備。

---

## アーキテクチャ

ルート `CMakeLists.txt` から 4 つのサブプロジェクトを統合：

| モジュール | ターゲット名 | 種類 | URI | 役割 |
|---|---|---|---|---|
| Shared/Schema | `hmi_schema` | STATIC lib | — | プロジェクト JSON の**唯一の真実**。Widget/Screen/Project の型と JSON I/O |
| Shared/Widgets | `hmi_widgets` | QML module | `HmiWidgets` | Editor/Simulator で共有する Widget 部品 |
| Editor | `hmi_editor` | アプリ | `HmiEditor` | 作画アプリ。`loadFromModule("HmiEditor", "Main")` で起動 |
| Simulator | `hmi_simulator` | アプリ | `HmiSimulator` | 読み取り専用の試験アプリ。同じ JSON を描画 |
| Runtime | — | — | — | 予約フォルダ。i.MX8MP / Yocto 向け。**MVP 後着手・現状 CMake 対象外** |

JSON 入出力は `QJsonDocument`（外部依存なし）。データモデルは `QAbstractListModel` ベースで QML に公開する想定。

---

## 利用可能なエージェント

能動的に手を動かす作業は専門エージェントへ委譲する（Agent ツール経由）。

| エージェント | 役割 | 呼ぶタイミング |
|---|---|---|
| [mvp-task-runner](.claude/agents/mvp-task-runner.md) | MVP の次タスクを 1 つだけ実装 | 「次のタスクを進めて」「Task N をやる」 |
| [cmake-build-resolver](.claude/agents/cmake-build-resolver.md) | CMake/Qt ビルドエラー解決 | `cmake --build` 失敗時 |

独立したタスクは並列起動して効率化する。

### コードレビューの担当分け

本プロジェクトの **コードレビューは ChatGPT Codex（GitHub App）** が担当する。Claude 側でレビュー専用エージェント / スキル（読み取り＋指摘のみのもの）は作らない。実装・ビルド修正・ドキュメント更新など **能動的な作業** に限ってエージェント化する。

---

## Codex 連携 / PR ワークフロー

本プロジェクトはレビューを Codex GitHub App に委ねるため、**MVP タスクは PR 経由で main に取り込む**。Claude は以下のフローに従う。

Codex 向けの永続的な指示は **リポジトリ直下の [AGENTS.md](AGENTS.md)** に記述する（Codex 公式推奨形式）。レビューを日本語化するための `## Review guidelines` セクションを含み、Codex GitHub App / Codex CLI の両方がレビュー時に参照する。Codex 関連で「全 PR に効かせたい」指示が増えたら、CLAUDE.md ではなく AGENTS.md 側に追記すること。

### ブランチ命名

- MVP タスク：`task/<N>-<短い名>` 形式（例：`task/2-canvas`, `task/3-widget-schema`, `task/6-json-save`）
- ドキュメント・設定変更：`docs/<短い名>` 形式（例：`docs/codex-auto-review`, `docs/qml-canvas-structure`）
- 1 単位 = 1 ブランチ = 1 PR。いずれも main から派生させる

### タスク完了時のフロー

1. 実装 → `cmake --build build` で緑を確認 → 動作確認
2. README の進捗表を更新
3. [kaizen-close](.claude/skills/kaizen-close/SKILL.md) スキルを実行
4. `task/<N>-<短い名>` ブランチを作成し、コミット
5. `gh pr create` で **ready-for-review** の PR を作成（draft にしない — Codex GitHub App に即レビューさせるため）
6. **`gh pr comment <N> --body "@codex review"` で明示的にレビュー依頼**（自動レビュー任せにせず毎回コメントで発火）
7. PR URL をユーザーに提示

詳細は [codex-pr](.claude/skills/codex-pr/SKILL.md) スキルを参照。

### PR タイトル / 本文

- **タイトル**：`Task N: <短い説明>`（コミット先頭行と同じ）
- **本文**：Summary / 変更点 / Test plan / Codex 向け補足（不安な観点や重点的に見てほしい箇所）を含める

### マージ戦略

- **Squash and merge**。1 タスク = main 上の 1 コミットになるよう統合する。
- マージは **ユーザーが行う**（Codex のレビュー指摘を反映してから）。Claude は勝手にマージしない。

### Codex 指摘への対応

- Codex のレビュー結果は **PR コメントとして自動投稿される**。ユーザーから「Codex の指摘を修正して」と指示が来たら、Claude は `gh pr view <番号> --comments` と `gh api repos/.../pulls/<番号>/comments` で内容を取得し、当該ブランチで対応コミットを追加 push する。
- 修正 push の **直後にも必ず** `gh pr comment <N> --body "@codex review"` で再レビューを依頼する（PR 作成時と同じ運用）。
- 大きな方針差し戻しになる場合は新タスクとして切り出すかを相談する。

### 前提（Codex 側のセットアップ）

- **ChatGPT Codex（Web 版エージェント）** を使用する。
- chatgpt.com の **Codex** → **Settings** から GitHub を OAuth 連携し、`hang-up33/hmi-platform` への権限を付与しておく。
- GitHub の Installed Apps 一覧には "ChatGPT" / "OpenAI Codex" などの名前で出現する（マーケットプレイス検索ではヒットしない）。
- **Codex 側の自動レビュー設定が有効** になっており、`ready-for-review` で PR を push すれば手動操作なしに Codex が PR コメントでレビューを返す。Claude は `gh pr view <番号> --comments` で結果を取得できる。

---

## 利用可能なスキル

| スキル | 用途 |
|---|---|
| [mvp-next-task](.claude/skills/mvp-next-task/SKILL.md) | MVP の次タスクを進める標準ワークフロー |
| [codex-pr](.claude/skills/codex-pr/SKILL.md) | Codex レビュー前提の PR 作成手順 |
| [qt6-build](.claude/skills/qt6-build/SKILL.md) | Qt6 + CMake セットアップ・ビルド手順と既知の罠 |
| [kaizen-close](.claude/skills/kaizen-close/SKILL.md) | タスク完了直前に学びをドキュメントに反映する手順 |

---

## ルール（Must Always / Must Never）

### Must Always

- 設計書由来の MVP タスク順を守る（Qt6 プロジェクト → キャンバス → Widget データ構造 → Button → ドラッグ → JSON 保存 → JSON 読込 → Simulator 表示）。
- Widget / Screen / Project 型と JSON I/O は `Shared/Schema` にのみ実装。
- 完了報告の直前に [kaizen-close](.claude/skills/kaizen-close/SKILL.md) を実行し、得た知見を反映する。
- QML モジュール URI とアプリの `loadFromModule()` 引数を一致させる。
- 出力（応答・ドキュメント・コミットメッセージ）は日本語を基本とする。

### Must Never

- 複数の MVP タスクを 1 回で実装する。
- フォルダ構成を変更する（`Editor/ Simulator/ Runtime/ Shared/Schema/ Shared/Widgets/ Docs/` を維持）。
- 既存コードを削除する（例外：後述のプレースホルダー 2 件のみ）。
- qmake その他の代替ビルドシステムを導入する。
- main ブランチに直接 push / コミットする。タスクは必ず `task/<N>-<短い名>` ブランチ + PR で取り込む。
- 設計書未承認のフレームワーク / ライブラリを独断で追加する。

---

## Qt バージョンの罠（macOS）

同梱の `~/Qt/6.7.0/macos` は **macOS 14 以降（Darwin 25+）でリンク不可**。`FindWrapOpenGL.cmake` が常に `-framework AGL` をリンクするが、AGL は macOS 14 で SDK から削除されている。

→ **Homebrew Qt 6.11.1（`/opt/homebrew/opt/qt`）または Qt 6.8+ を使用すること**。`AGL` 関連のリンクエラーが出たら、コードではなく `CMAKE_PREFIX_PATH` を疑う。詳細・他の罠は [qt6-build](.claude/skills/qt6-build/SKILL.md) と [cmake-build-resolver](.claude/agents/cmake-build-resolver.md) を参照。

## Windows 環境の罠（要注意）

- **PowerShell の ExecutionPolicy が Restricted だと `.ps1` を直接起動できない**。VSCode のターミナルや素の `powershell.exe` で `.\scripts\windows\build.ps1` を叩くと `UnauthorizedAccess` で拒否される。初回セットアップ時に一度だけ `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force` を実行する（CurrentUser スコープなので管理者権限不要、Microsoft 推奨の開発者向け設定）。設定後は VSCode のターミナルを開き直して反映させる。
- **日本語コメントを含む `.ps1` は UTF-8 with BOM で保存する**。Windows PowerShell 5.1 は BOM 無し UTF-8 を cp932 と誤認し、`The string is missing the terminator` でパースエラーになる。Edit/Write 直後は BOM 無しになることがあるので、`scripts/windows/` 配下の `.ps1` を新規作成・更新したら `[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($true))` で付け直す。
- **`-DKEY=$var` 形式の native コマンド引数は変数展開されない**。`cmake ... -DCMAKE_BUILD_TYPE=$BuildType` のように裸で書くと、PS 5.1 は `$BuildType` をリテラルとして cmake に渡す。引数全体を `"-DCMAKE_BUILD_TYPE=$BuildType"` のように **ダブルクォートで囲む** こと（シングルクォートだと展開されない）。
- **CMake が VS の `cl.exe` を掴まないようにする**。Windows には Visual Studio Build Tools が同居していることが多く、PATH 先頭に Qt 付属 MinGW を入れないと CMake が MSVC を選んで Qt MinGW kit と ABI 不一致になる。`scripts/windows/setup-env.ps1` がこれを担保する。
- **EXE の出力先が macOS と違う**。Windows は `build-mingw\hmi_<name>.exe`（ビルドツリーのトップ）に出る。macOS は `build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor`。
- 詳細・他の罠は [qt6-build](.claude/skills/qt6-build/SKILL.md) を参照。

---

## 削除可能なプレースホルダー（タスク到達時のみ削除）

削除可能なプレースホルダーは現在ありません（`Shared/Schema/src/schema_placeholder.cpp` は Task 3、`Shared/Widgets/qml/Placeholder.qml` は Task 4 で削除済み）。

実ソース追加と同時に対応する `CMakeLists.txt` の `QML_FILES` / ソース一覧を更新し、スタブを削除する。

---

## Schema 実装規約（`Shared/Schema`）

Task 3 で定着したスタイル。新しいデータ型を追加するときも踏襲する。

- **型は struct + namespace `hmi::schema`** で表現する（Q_GADGET / Q_OBJECT は必要になるまで付けない。Task 3 時点では QML 直接 expose しないため）。
- **ヘッダ配置**：`Shared/Schema/include/hmi/schema/<TypeName>.h`。利用側は `#include "hmi/schema/<TypeName>.h"`。
- **ソース**：`Shared/Schema/src/<TypeName>.cpp`。新規追加時は `Shared/Schema/CMakeLists.txt` の `qt_add_library(hmi_schema STATIC ...)` 一覧にも追記する。
- **JSON I/O**：各型に `QJsonObject toJson() const;` と `static <T> fromJson(const QJsonObject &);` を持たせる（メンバ関数 + 静的ファクトリ）。`QJsonDocument` は最上位（Project）でのみ使用する想定。
- **省略可能フィールド**：`toJson()` で `isEmpty()` 判定して書き出しを省略する（Widget の `text` / `tag` が前例）。
- **JSON 検証 API**：各型に `static bool isValidJson(const QJsonObject &);` も持たせる（Task 7 で定着）。`fromJson` はキー欠落時に既定値で埋める緩い設計なので、Editor / Simulator の読込側は **必ず `ProjectData::isValidJson` を通してから `fromJson` を呼ぶ**。検証は階層構造的に：`ProjectData::isValidJson` → `ScreenData::isValidJson` → `WidgetData::isValidJson` と再帰し、Shared/Schema 側に検証ロジックを集約する（利用側に検証コードを散らさない）。新しい必須フィールドを足す型変更時は `isValidJson` も同時に更新する。

---

## QML モジュール規約

- すべての QML モジュールは `qt_add_qml_module` で **明示的に `URI` を付与**（`HmiEditor` / `HmiSimulator` / `HmiWidgets`）。
- `Shared/Widgets` は `OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/HmiWidgets` を指定し、ビルドパスを URI と一致させる（Qt の警告防止）。
- QML ロードは `loadFromModule(URI, "Main")` を使用し、`qrc:` パス指定は避ける。
- QML import は Qt6 形式（`import QtQuick` — バージョン番号無し）。
- **QtQuick 標準型と同名の QML ファイルを作らない**（`Canvas.qml` / `Rectangle.qml` / `Item.qml` / `Text.qml` / `Image.qml` / `Window.qml` / `Button.qml`〔Controls〕等）。`import QtQuick` だけでは標準型が優先解決され、`Cannot assign to non-existent property` 等のエラーになる。回避策はいずれか：
  - **プレフィックス命名**（推奨）：`EditorCanvas.qml` / `HmiButton.qml` のように接頭辞を付ける。
  - **自モジュールを明示 import**：`Canvas.qml` のような名前を採用した場合、利用側 QML に `import HmiEditor`（または `HmiWidgets`）を必ず記述する。
- 共有 Widget（`HmiWidgets`）を新規追加する際は、上記の命名衝突に特に注意する（`Button` / `Label` / `Slider` 等は Controls と衝突しうる）。
- **共有 QML モジュールは `STATIC` でビルドし、利用側アプリで plugin ターゲットをリンクする**。これは Qt 公式の「Multiple QML Modules in One Binary」推奨構成：
  - 共有側（`Shared/Widgets/CMakeLists.txt`）：`qt_add_qml_module(hmi_widgets STATIC URI HmiWidgets ...)`
  - 利用側（`Editor` / `Simulator`）：`target_link_libraries(<app> PRIVATE hmi_widgetsplugin)`
  - 動的ビルド（`STATIC` を付けない）だと plugin が `MODULE_LIBRARY` になり `target_link_libraries` がエラーになる。
  - 代替として利用側で `IMPORTS HmiWidgets` を宣言する書き方もあるが、本プロジェクトの Qt 6.11（Homebrew）構成では自モジュール（`HmiEditor`）のリソース解決と競合して `No module named "HmiEditor"` で起動失敗した実績がある。STATIC plugin + 直リンクが唯一動作確認済みの方法。
  - Yocto / i.MX8MP の組み込みデプロイでも静的リンクの方が dylib 配布パスの問題を避けられて好都合。
- **`default property alias content: <inner>.data` で受けた子要素の `parent` は内部 Item を指す**。たとえば `EditableWidget` は内部 `container` に子を流し込むため、Main.qml で `EditableWidget { HmiButton { text: parent.widgetText } }` と書くと `parent` は `container` を指してしまい、`widgetText`（root のプロパティ）が undefined になる。回避策：外側 Item に `id` を付け、子からは `id` 経由で参照する（例：`EditableWidget { id: btn; HmiButton { text: btn.widgetText } }`）。Canvas.qml も同じ構造のため同様の注意が必要。
- **C++ ヘルパーを QML に公開するときは `setContextProperty` が最も軽い**。Editor 側に存在する一時的なコントローラ（例：`ProjectIo`）は `engine.rootContext()->setContextProperty("projectIo", &io)` でグローバル変数として QML から呼べる。`qmlRegisterType` / QML_ELEMENT は型インスタンス化が必要な場合に使う。**`hmi_schema` 等の Shared ライブラリは QML を一切知らないことを保ち**、QML 連携クラスは利用側アプリ（Editor / Simulator）に置く。
- **QtQuick.Controls / QtQuick.Dialogs は QML `import` だけで動く**（Qt 6.5+）。CMake で `Qt6::QuickControls2` 等を明示リンクしなくても plugin が動的にロードされるため、`target_link_libraries` への追加は不要。デプロイ時のみ `windeployqt` / `macdeployqt` で plugin 同梱を確認する。
- **`FileDialog.selectedFile` は `file:///...` 形式の `QUrl`**。C++ で受けるときは `QUrl::toLocalFile()` で OS パスに変換してから `QFile` / `QSaveFile` に渡すこと（`toString()` だと `file://` が残って書き込みに失敗する）。書き込みは `QSaveFile` を使い `commit()` で原子的に保存するのが安全。

---

## 動作証跡スクリーンショット運用

GUI に変化がある PR（MVP Task 2 / 4 / 5 / 8 のような Editor / Simulator の見た目が変わるもの、UI 系の bugfix）には **スクリーンショットを必ず添付する**。Codex / 人間レビュアーの両方が、コードを脳内実行せず「実際にこう見える」を確認できるようにするため。

### 撮影手順（macOS）

対象アプリ（Editor / Simulator）に応じて起動バイナリとプロセス名を切り替える：

```sh
# Editor の変更を撮る場合
./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor &
sleep 2
scripts/capture-app-window.sh hmi_editor Docs/screenshots/task-<N>-<短い名>.png
kill %1

# Simulator の変更を撮る場合
./build/Simulator/hmi_simulator.app/Contents/MacOS/hmi_simulator &
sleep 2
scripts/capture-app-window.sh hmi_simulator Docs/screenshots/task-<N>-<短い名>.png
kill %1
```

両方の見た目が同時に変わるタスク（例：Task 8 で Editor の保存形式と Simulator の表示を同時に検証したい場合）は両方のスクショを撮り、`Docs/screenshots/task-<N>-<短い名>-editor.png` と `-simulator.png` のように suffix を付けて両方コミットする。

- `scripts/capture-app-window.sh` は Swift で `CGWindowListCopyWindowInfo` を呼び対象プロセスのウィンドウ ID を取得し、`screencapture -l<wid>` で当該ウィンドウのみを切り出す（Retina 倍率は自動考慮、アクセシビリティ権限不要、**画面収録権限のみ**が必要）。
- **初回のみ macOS の画面収録権限を Claude Code 親プロセス（Visual Studio Code / ターミナル）に付与する必要がある**。システム設定 > プライバシーとセキュリティ > 画面収録 で対象アプリを ON にし、再起動。
- Windows でのキャプチャは未対応（必要になったタスクで `scripts/windows/` 配下に PowerShell 版を追加する）。
- **AppleScript で Qt QML の Button を自動クリックする手段は事実上ない**（Task 7 で確認）。`tell application "System Events" to click at {x, y}` の CGEvent も、Accessibility の `click button "name" of window 1` も、QML のクリックイベントとして受理されない（座標は正しくても無反応）。FileDialog を介する読込・保存系の動作証跡が必要な場合は、(a) 起動直後の初期状態だけスクショして「ボタンが追加されたこと」を見せる、(b) どうしても「操作後の状態」を撮りたいなら、テスト用に環境変数や CLI 引数で初期 JSON を自動ロードする小機能を当該タスクに含める、のいずれかを選ぶ。最初から無理に automate しようとせず手動補完で済ませる判断もあり。

### ファイル配置と PR への埋め込み

- 出力先：`Docs/screenshots/task-<N>-<短い名>.png`（branch 名と揃える）
- PR 本文には **commit SHA 固定の raw URL** で参照する。タスクブランチ削除後も生きる：
  ```markdown
  ## Screenshot
  ![Task N: <短い説明>](https://raw.githubusercontent.com/hang-up33/hmi-platform/<commit-sha>/Docs/screenshots/task-<N>-<短い名>.png)
  ```
- SHA は push 後 `git rev-parse HEAD` で取得。PR 本文を `gh pr edit <N> --body-file ...` で更新する場合も同じ SHA を使い続ける（後続の修正コミットでスクショ自体を撮り直したら SHA も更新する）。
- GUI 変化が無いタスク（純粋な Schema / docs / CMake のみ）はスクショ省略可。

---

## ファイル命名規約

- 小文字 + ハイフン区切り（例：`mvp-task-runner.md`, `qt6-build/SKILL.md`）
- エージェント：`.claude/agents/<name>.md`（YAML frontmatter に `name` `description` `tools` `model`）
- スキル：`.claude/skills/<name>/SKILL.md`（YAML frontmatter に `name` `description` `origin`）
- コミットメッセージ：`Task N: <短い説明>` を基本フォーマットとする

---

## 対象プラットフォーム

開発・動作確認は **macOS と Windows の両方**で実施（Editor / Simulator ともに GUI 起動確認済み）。Yocto / i.MX8MP クロスビルドは MVP 完了後に `Runtime/` で対応する。
