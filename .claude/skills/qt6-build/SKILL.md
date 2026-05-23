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

## 標準コマンド

```sh
# 構成
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

## 関連エージェント

- ビルドエラーの根本対処は [cmake-build-resolver](../../agents/cmake-build-resolver.md) に委譲可能
