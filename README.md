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

> 🗺️ **どの文書が人間向けで、どれが AI エージェント向けかは [DOCS-MAP.md](DOCS-MAP.md) にまとめています。**
> このリポジトリには Claude Code / Codex への指示ファイルが多数含まれるため、まず地図を見ると迷いません。

詳細な開発仕様、進捗状況、各種ガイドラインは `Docs/` 配下を参照してください。

- 🚀 **[フェーズ進捗・ステータス](Docs/phase-status.md)**: 現在の開発フェーズおよび完了機能の一覧
- 📐 **[アーキテクチャ概要](Docs/architecture.md)**: モジュール構成、CMake、データモデル設計
- 🔄 **[開発ワークフローとルール](Docs/workflow.md)**: PR 運用、コード規約、開発ルール
- 🔍 **[コードレビューガイドライン](Docs/agents/review-guidelines.md)**: PR レビュー観点・重要度定義
- 📜 **[開発経緯・PR 履歴](Docs/development-history.md)**: 過去のタスク達成履歴と技術的知見
- 📦 **[完了フェーズの計画書](Docs/archive/)**: 過去の実装指示書（現在の仕様書ではありません）

---

## 現在地

- **現在地**: **v1.0 公開準備（2026-11-05 承認）着手中 — 2026-11-09（月）に MIT ライセンスの OSS として公開予定**。11/9 まで機能凍結し、機微情報の確認・ライセンス・CI の公開対応を進める。V1-0（計画書）と V1-1（機微情報の棚卸し）完了、V1-2（`LICENSE` とライセンス一覧）完了、次タスク = V1-3（CONTRIBUTING などの公開用ファイル）。進捗の正本は [Docs/v1-release-plan.md](Docs/v1-release-plan.md)。
  - **契約→テスト→実装（DbC + テスト先行）の導入**：DT-1（計画とルール）完了、DT-2〜DT-6 は v1.0 公開後。正本は [Docs/dbc-tdd-plan.md](Docs/dbc-tdd-plan.md)。
  - **リファクタリング計画（2026-07-22 承認）一区切り — RF-A / RF-B / RF-D / RF-E / RF-G 完了**。機能追加はせず、`Editor/qml/Main.qml` の肥大化（2,712→346 行）と型分岐の散在を解消した。RF-E〔Button / Label / SimpleButton の delegate を `Shared/Widgets` の型別ホスト QML へ集約〕と RF-G〔`InspectorPanel.qml` をセクション単位へ分割〕も v1.0 に含める。RF-E の残り種別と RF-F は保留。進捗の正本は [Docs/refactoring-plan.md](Docs/refactoring-plan.md)。
  - **Phase 11 / Widget サンプルパレット（ドラッグ&ドロップ追加）＋ 初号「シンプルボタン」完了（W-A〜W-E クローズ）**。issue #155「シンプル・イズ・ベスト版 HMI ボタン（ベゼル無し）」を新 Widget 種別 `SimpleButton`（`HmiSimpleButton.qml`）として QML で忠実再現し、**見た目そのままの Widget サンプルをインスペクタに並べてキャンバスへ D&D で追加**する汎用パレット UX を新設した（将来他 Widget もパレット化）。Canvas 自描画で新 Qt 依存ゼロ（Meter/Trend 同方針）。W-A〔Schema 拡張〕/ W-B〔HmiSimpleButton 描画 + delegate 6 分岐目〕/ W-C〔サンプルパレット〕/ W-D〔パレット→キャンバス D&D 追加〕/ W-E〔インスペクタ型対応（シンプルボタン詳細＝形状 / テーマ / 差し色 / 長押し時間）+ cross-app E2E `e2e_simple_button_live` + スクショ同期〕すべて完了（Web `ctest` 27/27 緑）。次フェーズは未承認候補から選定（自動着手しない）。進捗の正本は [Docs/archive/phase11-widget-palette-plan.md](Docs/archive/phase11-widget-palette-plan.md)。
  - **Phase 10 / メーター（Meter・車のスピードメーター風）完了**（M-A〜M-D クローズ）。新 Widget 種別「Meter」を横展開テンプレに乗せた（円弧＋針の QML `Canvas` 自描画で新 Qt モジュール依存ゼロ）。進捗の正本は [Docs/archive/phase10-meter-plan.md](Docs/archive/phase10-meter-plan.md)。
  - **Phase 9 / OPC-UA クライアント完了**（2026-06-27 OP-6 クローズ）。**OP-1〜OP-6 すべて完了**：OP-1〔Schema + Editor UI〕／OP-2〔PC 読込/購読〕／OP-3〔実サーバ読込確認〕／OP-4〔書込 + 接続状態 + 自動再接続〕／OP-5〔実サーバ書込確認〕／OP-6〔実機 Runtime 展開（i.MX8MP で OPC-UA ライブ値を VNC キャプチャで確認）〕。**🔴 Qt OpcUa は aqtinstall 非同梱＝Web/CI 不可。macOS / Windows / 実機（SDK 包含）ともに導入済み**（手順は [.claude/rules/dev-environment.md](.claude/rules/dev-environment.md)）。進捗の正本は [Docs/archive/phase9-opcua-plan.md](Docs/archive/phase9-opcua-plan.md)。
  - **Phase 8 / トレンドグラフ（単系列ライブ折れ線）完了**（2026-06-16 承認・PR #127〜#131）。新 Widget 種別「Trend」を横展開テンプレに乗せ、`Canvas` 自描画で実機にそのまま載る。進捗の正本は [Docs/archive/phase8-trend-plan.md](Docs/archive/phase8-trend-plan.md)。
  - **Phase 7 / Modbus TCP** は MB-1〜MB-4（書込 + 接続状態 + 自動再接続・PR #119/#121/#122）完了。残る MB-5〔実 PLC 書込確認〕/ MB-6〔実機 Yocto〕はローカル専用で Web 不可。進捗の正本は [Docs/phase7-modbus-plan.md](Docs/phase7-modbus-plan.md)。
- 開発の時系列（各タスクの目的 / PR / 学び）: [Docs/development-history.md](Docs/development-history.md)
- 各フェーズの計画と進捗表（正本）: 進行中は [Docs/](Docs/) の `phase*-plan.md`、完了済みは [Docs/archive/](Docs/archive/)
- 開発ガイド・ビルドの罠・ルール: [CLAUDE.md](CLAUDE.md)

## ライセンス

本プロジェクトは [MIT License](LICENSE) で公開しています。

Qt などの依存ライブラリは、それぞれのライセンスに従います。一覧と、Qt を使ったアプリを配布するときの注意は [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) にまとめています。
