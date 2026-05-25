# hmi-platform

Yocto 上で動作する i.MX8M Plus 向け Qt/QML HMI ランタイムを対象に、HMI 作画・シミュレーション・タグ管理・実機デプロイを統合した開発環境。

## 成果物

| モジュール | 役割 |
|---|---|
| **Editor** | HMI 作画ツール（Qt6 + QML） |
| **Simulator** | PC 上での HMI 試験環境（Qt6 + QML） |
| **Runtime** | i.MX8MP / Yocto 実機向けランタイム（MVP 後着手） |
| **Shared/Schema** | プロジェクト JSON スキーマ / C++ データモデル（唯一の真実） |
| **Shared/Widgets** | 共通 QML Widget（Button / Label 等） |

## 技術スタック

- **言語 / フレームワーク**: Qt 6 (Qt Quick / QML), C++17
- **ビルド**: CMake (≥ 3.21)
- **ホスト OS（開発）**: macOS / Windows（共に動作確認済み）
  - **Claude Code on the web は非対応**（コンテナのネットワークポリシーが Qt 公式ミラーを遮断するため Qt 6.5+ を取得できない。詳細は [CLAUDE.md](CLAUDE.md) の「Claude Code on the web は非対応」節）。
- **ターゲット OS（最終）**: Yocto on i.MX8MP

## フォルダ構成

```
hmi-platform/
├─ Editor/              HMI Editor アプリ
│   ├─ CMakeLists.txt
│   ├─ src/
│   └─ qml/
├─ Simulator/           HMI Simulator アプリ
│   ├─ CMakeLists.txt
│   ├─ src/
│   └─ qml/
├─ Runtime/             i.MX8MP / Yocto 実機向け（MVP 後）
├─ Shared/
│   ├─ Schema/          JSON スキーマ・C++ データモデル
│   │   ├─ CMakeLists.txt
│   │   ├─ include/
│   │   └─ src/
│   └─ Widgets/         共通 QML Widget モジュール
│       ├─ CMakeLists.txt
│       └─ qml/
├─ Docs/
└─ CMakeLists.txt       ルート CMake
```

## 前提

- Qt 6.8 以上（macOS 14+ では Qt 6.7 以前は `AGL.framework` 不在によりリンクエラーになるため）
- CMake 3.21 以上
- C++17 対応コンパイラ

macOS で Homebrew Qt を使う場合：

```sh
brew install qt
```

Windows は Qt Online Installer から **Qt 6.11.0 MinGW 64-bit** kit と付属 MinGW 13.1 / Ninja / CMake をインストール（既定パス `C:\Qt`）。

## ビルド

### macOS

```sh
cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt
cmake --build build
```

`CMAKE_PREFIX_PATH` は環境に合わせて変更してください（例: `~/Qt/6.8.0/macos`）。

### Windows（PowerShell）

リポジトリ同梱の補助スクリプトを使うのが最も簡単：

```powershell
# configure + build を一発実行（build-mingw/ に出力）
.\scripts\windows\build.ps1

# 個別ターゲットや再 configure
.\scripts\windows\build.ps1 -Target hmi_editor
.\scripts\windows\build.ps1 -Reconfigure
```

手動で実行する場合は、まず PATH を整える（dot-source）：

```powershell
. .\scripts\windows\setup-env.ps1
cmake -S . -B build-mingw -G Ninja `
  -DCMAKE_PREFIX_PATH=C:\Qt\6.11.0\mingw_64 `
  -DCMAKE_CXX_COMPILER=C:/Qt/Tools/mingw1310_64/bin/g++.exe
cmake --build build-mingw
```

詳細・罠は [.claude/skills/qt6-build/SKILL.md](.claude/skills/qt6-build/SKILL.md) を参照。

## 起動

### macOS

```sh
./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor
./build/Simulator/hmi_simulator.app/Contents/MacOS/hmi_simulator
```

### Windows

`build.ps1` で通すと PATH に Qt の bin が乗るため、そのまま実行できる：

```powershell
.\build-mingw\hmi_editor.exe
.\build-mingw\hmi_simulator.exe
```

新しいシェルから起動する場合は `. .\scripts\windows\setup-env.ps1` で PATH を通してから実行。

## フェーズ進捗

### Phase 1: MVP（Editor / Simulator の作画 → 保存 → 読込）

| # | タスク | 状態 |
|---|---|---|
| 1 | Qt6 プロジェクト作成 | ✅ 完了 |
| 2 | キャンバス表示 | ✅ 完了 |
| 3 | Widget データ構造定義 | ✅ 完了 |
| 4 | Button 配置 | ✅ 完了 |
| 5 | ドラッグ | ✅ 完了 |
| 6 | JSON 保存 | ✅ 完了 |
| 7 | JSON 読込 | ✅ 完了 |
| 8 | Simulator 表示 | ✅ 完了 |

### Phase 2: テスト基盤導入

詳細は [Docs/phase2-testing-plan.md](Docs/phase2-testing-plan.md)。

| # | タスク | 状態 |
|---|---|---|
| 9 | Qt Test 基盤構築 | ✅ 完了 |
| 10 | Schema JSON I/O テスト | ✅ 完了 |
| 11 | ファイル I/O テスト（ProjectIo / ProjectLoader） | ✅ 完了 |
| 12 | Qt Quick Test 基盤構築 | ⬜ 未着手 |
| 13 | 共有 Widget テスト | ⬜ 未着手 |
| 14 | Editor QML テスト | ⬜ 未着手 |
| 15 | CI 整備（GitHub Actions） | ⬜ 未着手（任意） |

### Phase 3 候補（未承認）

- E2E テスト
- Runtime（i.MX8MP / Yocto）対応

## 共通データ仕様（Project Format）

`Shared/Schema` を唯一の真実とし、以下の JSON 形状で project / screen / widget を表現する。

```json
{
  "project": "Sample",
  "screens": [
    {
      "name": "Main",
      "widgets": [
        {
          "id": "btn001",
          "type": "Button",
          "x": 100,
          "y": 50,
          "width": 120,
          "height": 40,
          "text": "Start",
          "tag": "PLC.START"
        }
      ]
    }
  ]
}
```

## 開発ルール

- 1 タスクごとに実装し、ビルド成功を完了基準とする
- `Shared/Schema` を唯一の真実とする
- フォルダ構成の変更禁止
- 既存コードの削除禁止
- Qt6 + CMake 前提
