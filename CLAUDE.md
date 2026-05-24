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

テスト・lint・フォーマッタは未整備。詳細手順は [qt6-build](.claude/skills/qt6-build/SKILL.md) スキル参照。

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

### ブランチ命名

- `task/<N>-<短い名>` 形式（例：`task/2-canvas`, `task/3-widget-schema`, `task/6-json-save`）
- 1 タスク = 1 ブランチ = 1 PR

### タスク完了時のフロー

1. 実装 → `cmake --build build` で緑を確認 → 動作確認
2. README の進捗表を更新
3. [kaizen-close](.claude/skills/kaizen-close/SKILL.md) スキルを実行
4. `task/<N>-<短い名>` ブランチを作成し、コミット
5. `gh pr create` で **ready-for-review** の PR を作成（draft にしない — Codex GitHub App に即レビューさせるため）
6. PR URL をユーザーに提示

詳細は [codex-pr](.claude/skills/codex-pr/SKILL.md) スキルを参照。

### PR タイトル / 本文

- **タイトル**：`Task N: <短い説明>`（コミット先頭行と同じ）
- **本文**：Summary / 変更点 / Test plan / Codex 向け補足（不安な観点や重点的に見てほしい箇所）を含める

### マージ戦略

- **Squash and merge**。1 タスク = main 上の 1 コミットになるよう統合する。
- マージは **ユーザーが行う**（Codex のレビュー指摘を反映してから）。Claude は勝手にマージしない。

### Codex 指摘への対応

- Codex のレビュー結果は **PR コメントとして自動投稿される**。ユーザーから「Codex の指摘を修正して」と指示が来たら、Claude は `gh pr view <番号> --comments` で内容を取得し、当該ブランチで対応コミットを追加 push する。
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

---

## 削除可能なプレースホルダー（タスク到達時のみ削除）

| ファイル | 削除タイミング |
|---|---|
| `Shared/Schema/src/schema_placeholder.cpp` | Task 3 で `WidgetData` / `ScreenData` / `ProjectData` を追加する時 |
| `Shared/Widgets/qml/Placeholder.qml` | Task 4 で最初の共有 Widget を追加する時 |

実ソース追加と同時に対応する `CMakeLists.txt` の `QML_FILES` / ソース一覧を更新し、スタブを削除する。

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

---

## ファイル命名規約

- 小文字 + ハイフン区切り（例：`mvp-task-runner.md`, `qt6-build/SKILL.md`）
- エージェント：`.claude/agents/<name>.md`（YAML frontmatter に `name` `description` `tools` `model`）
- スキル：`.claude/skills/<name>/SKILL.md`（YAML frontmatter に `name` `description` `origin`）
- コミットメッセージ：`Task N: <短い説明>` を基本フォーマットとする

---

## 対象プラットフォーム

現状の開発・動作確認は **macOS のみ**。Yocto / i.MX8MP クロスビルドは MVP 完了後に `Runtime/` で対応する。
