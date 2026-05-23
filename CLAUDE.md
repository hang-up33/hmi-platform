# CLAUDE.md

このファイルは、本リポジトリで作業する Claude Code（claude.ai/code）への指針です。
**ユーザーは日本人のため、応答・ドキュメント・コミットメッセージは日本語を基本とします**（コード識別子は英語でも可）。

## ビルドと実行

```sh
# 構成（CMAKE_PREFIX_PATH は Qt 6.8 以上のインストール先を指定 — 後述の罠参照）
cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt

# 全体ビルド
cmake --build build

# 個別ターゲットビルド
cmake --build build --target hmi_editor
cmake --build build --target hmi_simulator
cmake --build build --target hmi_schema
cmake --build build --target hmi_widgets

# 起動（macOS の .app バンドル経由）
./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor
./build/Simulator/hmi_simulator.app/Contents/MacOS/hmi_simulator
```

テスト・lint・フォーマッタは未整備。

## Qt バージョンの罠（macOS）

同梱の `~/Qt/6.7.0/macos` は **macOS 14 以降（Darwin 25+）でリンク不可**。`FindWrapOpenGL.cmake` が常に `-framework AGL` をリンクするが、AGL は macOS 14 で SDK から削除されているため `framework 'AGL' not found` で失敗する。

→ **Homebrew Qt 6.11.1（`/opt/homebrew/opt/qt`）または Qt 6.8 以上を使用すること**。`AGL` 関連のリンクエラーが出たら、プロジェクトコードではなく `CMAKE_PREFIX_PATH` を疑う。

## アーキテクチャ

ルート `CMakeLists.txt` から 4 つのサブプロジェクトを統合：

- **Shared/Schema**（`hmi_schema`, STATIC ライブラリ） — プロジェクト JSON フォーマットの**唯一の真実**。Editor / Simulator / Runtime はすべてこれを参照し、独自の Widget / Screen / Project 型を定義してはならない。JSON 入出力は `QJsonDocument`（外部依存なし）。
- **Shared/Widgets**（`hmi_widgets`, QML モジュール URI `HmiWidgets`） — Editor と Simulator で共有する Widget 部品。Button / Label の見た目を一元化。
- **Editor**（`hmi_editor`, アプリ） — QML モジュール URI `HmiEditor`。`engine.loadFromModule("HmiEditor", "Main")` で起動（`qrc:` パス指定は使わない）。`hmi_schema` をリンク。
- **Simulator**（`hmi_simulator`, アプリ） — Editor と対称構造、URI は `HmiSimulator`。読み取り専用で同じ JSON を描画する。
- **Runtime/** — i.MX8MP / Yocto 実機向けの予約フォルダ。**現時点で CMake グラフに追加していない**。MVP 後着手。

JSON スキーマ（README 参照）が Editor（書き手）と Simulator/Runtime（読み手）の契約。

## 開発ルール（設計書由来 — 厳守）

1. **MVP は 1 タスクずつ**。順序: Qt6 プロジェクト → キャンバス → Widget データ構造 → Button 配置 → ドラッグ → JSON 保存 → JSON 読込 → Simulator 表示。各タスクの完了基準は `cmake --build` 成功。
2. **`Shared/Schema` を唯一の真実とする**。Widget / Screen / Project 型を他の場所に重複定義しない。
3. **フォルダ構成を変更しない**（`Editor/ Simulator/ Runtime/ Shared/Schema/ Shared/Widgets/ Docs/`）。
4. **既存コードを削除しない**。基本は追記・拡張。例外は後述のプレースホルダー 2 件のみ。
5. **Qt6 + CMake 前提**。qmake や別ビルドシステムは使わない。
6. **継続的改善（kaizen）を遵守する**。タスク完了前に「今回詰まった点・回避策・新たな知見はあるか？」を必ず自問し、見つけたら CLAUDE.md / README / メモリ / 設定のいずれかに反映してから完了報告する。次セッションが同じ罠を踏まないようにする。

## 削除可能なプレースホルダー（削除はタスク到達時のみ）

下記 2 ファイルは「空のモジュールをビルド可能にする」目的のスタブで、対応する MVP タスクで実コンテンツに置き換える：

- `Shared/Schema/src/schema_placeholder.cpp` → Task 3 で `WidgetData` / `ScreenData` / `ProjectData` を追加時に削除。
- `Shared/Widgets/qml/Placeholder.qml` → Task 4 で最初の共有 Widget を追加時に削除。

実ソースを追加する際は、同じ変更内で対応する `CMakeLists.txt`（`qt_add_library` / `qt_add_qml_module`）のソース一覧を更新し、スタブファイルを削除すること。

## QML モジュール規約

- 各アプリと共有 Widget は `qt_add_qml_module` で **明示的に `URI` を付与**（`HmiEditor` / `HmiSimulator` / `HmiWidgets`）。
- `Shared/Widgets` は `OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/HmiWidgets` を指定し、ビルドパスを URI と一致させる（指定しないと Qt が警告を出す）。
- QML ロードは `loadFromModule(URI, "Main")` を使用し、ファイルパス指定は避ける。

## 対象プラットフォーム

現状の開発・動作確認は **macOS のみ**。Yocto / i.MX8MP クロスビルドは MVP 完了後に `Runtime/` で対応する。
