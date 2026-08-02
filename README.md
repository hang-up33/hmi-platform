# hmi-platform（Atlas）

GUI で HMI 画面を作図し、JSON 形式で保存。PC 試験環境でも組込み実機でも全く同じ画面を描画する、Qt6 ベースの次世代 HMI 開発プラットフォームです。

- **Editor** … マウスドラッグ＆ドロップで Widget を配置・編集する作画ツール
- **Simulator** … PC 上で同じ JSON を描画し、変数動作や通信を検証する試験環境
- **Runtime** … i.MX8M Plus などの Linux 実機（Yocto / Qt6）で高速描画する実機ランタイム

> **開発コードネーム: Atlas**（天空を支える巨神 ＝ 各モジュールを束ねる基盤の意）。正式なリポジトリ名は `hmi-platform` です。

---

## 画面イメージと機能デモ

### 1. HMI Editor（作画ツール）

![HMI Editor でライン監視ダッシュボードを組み上げる様子](Docs/screenshots/editor.gif)

- **直感的なキャンバス操作**: Widget の追加、ドラッグ＆ドロップ配置、リサイズ、グリッドスナップ、コピペ、Undo/Redo に対応。
- **リッチなプロパティ編集**: インスペクタで背景色・文字色・フォント・角丸・ボーダー・透明度・クリックアクション・変数バインディングを編集可能。
- **Widget サンプルパレット**: 見た目そのままのサンプルを並べたパレットからキャンバスへ直接追加。

### 2. HMI Simulator（試験環境）

![HMI Simulator](Docs/screenshots/simulator.png)

- **ロジック & 通信の検証**: Editor で作成した JSON をそのまま読み込み、ボタン操作、数値入力、変数の追従動作を PC 上でリアルタイム確認。
- **デバッグパネル**: ツールバーの「変数」トグルで、実行時の内部タグ（変数）一覧と値をライブモニタリング。

---

## 主な機能と対応 Widget

### 対応 Widget 種別
- **Button / SimpleButton**: タッチ / クリック操作、状態別スタイル、変数操作アクション
- **Label**: テキスト表示、変数バインディングによる動的表示
- **NumericField**: 数値入力（int / real 対応、min/max 範囲クランプ）
- **Trend**: ライブ折れ線グラフ（単系列 / 複数系列、軸目盛り・凡例表示、QML Canvas 自描画）
- **Meter**: 車のスピードメーター風アーク＋針表示（範囲・色・目盛りカスタマイズ）

### 産業プロトコル・通信連携
- **Modbus TCP**: PLC レジスタ（Coil / Discrete / Input / Holding）の周期ポーリング & 書込
- **OPC-UA**: 産業用標準プロトコルによるタグ読込・書込・自動再接続

---

## 必要動作環境

- **Qt**: 6.8 以上（macOS / Windows / Linux / Yocto）
- **CMake**: 3.21 以上
- **コンパイラ**: C++17 対応コンパイラ（Clang / GCC / MSVC / MinGW）

---

## クイックスタート（ビルドと実行）

### macOS

```sh
brew install qt
cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt
cmake --build build

# アプリ起動
./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor
./build/Simulator/hmi_simulator.app/Contents/MacOS/hmi_simulator
```

### Windows (PowerShell)

Qt Online Installer で **Qt 6.11.0 MinGW 64-bit** kit をインストール後:

```powershell
.\scripts\windows\build.ps1     # ビルド実行 → build-mingw\ に出力
.\build-mingw\hmi_editor.exe
.\build-mingw\hmi_simulator.exe
```

> **Note**: 新しい PowerShell シェルからは `. .\scripts\windows\setup-env.ps1` で環境変数を設定できます。詳細は [qt6-build スキル](.claude/skills/qt6-build/SKILL.md) を参照してください。

---

## プロジェクト構造 & データ形式

データモデルは `Shared/Schema` を唯一の真実とし、プロジェクト全体をシンプルフラットな JSON で表現します。

```json
{
  "project": "SampleProject",
  "screens": [
    {
      "name": "MainScreen",
      "widgets": [
        {
          "id": "btn001",
          "type": "Button",
          "x": 100,
          "y": 50,
          "width": 120,
          "height": 40,
          "text": "Start",
          "backgroundColor": "#e63946",
          "textColor": "#ffffff",
          "fontSize": 18
        }
      ]
    }
  ]
}
```

```text
hmi-platform/
├─ Editor/        作画アプリ（Qt6 + QML）
├─ Simulator/     試験アプリ（PC 用エミュレーション）
├─ Runtime/       実機用ランタイム（Simulator ソース共有・軽量化）
├─ Shared/
│   ├─ Schema/    JSON スキーマ・C++ データモデル（唯一の真実）
│   └─ Widgets/   共有 QML Widget ライブラリ
├─ Docs/          設計・開発ドキュメント
└─ CMakeLists.txt ルート CMake
```

---

## 組込み実機への展開（i.MX8M Plus / Yocto）

`hmi_runtime` を aarch64 向けにクロスビルドし、実機ボードへ転送して起動します。

```sh
# クロスビルド (WSL2 / Linux 環境)
./scripts/yocto/cross-build.sh
scp -O ~/build-yocto/Runtime/hmi_runtime root@<board-ip>:/tmp/hmi_runtime
```

![hmi_runtime on i.MX8MP](Docs/screenshots/task-43-runtime-action.png)

実機環境での詳細な展開手順・Wayland/Weston 設定は [scripts/yocto/README.md](scripts/yocto/README.md) を参照してください。

---

## 開発ドキュメント

詳細な開発仕様、進捗状況、各種ガイドラインは `Docs/` 配下を参照してください。

- 🚀 **[フェーズ進捗・ステータス](Docs/phase-status.md)**: 現在の開発フェーズおよび完了機能の一覧
- 📐 **[アーキテクチャ概要](Docs/architecture.md)**: モジュール構成、CMake、データモデル設計
- 🔄 **[開発ワークフローとルール](Docs/workflow.md)**: PR 運用、コード規約、開発ルール
- 🔍 **[コードレビューガイドライン](Docs/review-guidelines.md)**: PR レビュー観点・重要度定義
- 📜 **[開発経緯・PR 履歴](Docs/development-history.md)**: 過去のタスク達成履歴と技術的知見

---

## ライセンス

本プロジェクトはオープンソース/独自ライセンスの準備中です。
