# Changelog / 変更履歴

このファイルには、リリースごとの主な変更を書く。書き方は [Keep a Changelog](https://keepachangelog.com/ja/1.1.0/) に、バージョン番号は [Semantic Versioning](https://semver.org/lang/ja/) に従う。

## [1.0.0] - 2026-11-09

最初の公開リリース。

### アプリ

- **Editor**：PC で HMI 画面を作画し、JSON 形式のプロジェクトファイルに保存する。主な機能は次のとおり。
  - グリッドスナップ、複数選択と整列
  - コピー・貼り付け、元に戻す・やり直し
  - Widget サンプルパレットからのドラッグ&ドロップ
- **Simulator**：PC で画面を動かして試す。変数・アクション・状態別スタイル・通信が実機と同じように動く。
- **Runtime**：Qt6 が動く組込み Linux で画面を表示する。Simulator とソースを共有する。

### Widget

- Button：クリック、状態別スタイル、変数を変えるアクション
- SimpleButton：クリックと長押し（長押しの時間は設定できる）
- Label：文字の表示、変数の値の表示
- NumericField：数値の入力（整数・実数、最小値と最大値の制限）
- Trend：ライブの折れ線グラフ（複数系列、軸の目盛り、凡例）
- Meter：スピードメーター風の円弧と針

### 通信

- Modbus TCP：PLC のレジスタを周期的に読み、書き込む。接続状態の表示と自動再接続に対応する。
- OPC-UA：ノードの値を購読し、書き込む。接続状態の表示と自動再接続に対応する。Qt OPC UA が導入されている場合だけ使える。

### 動作確認した環境

- PC：macOS、Windows（MinGW）、Linux
- 実機：NXP i.MX8M Plus EVK（Yocto scarthgap、Qt 6.8）

### 既知の制限

- 実際の PLC への書き込み確認と、実機の Runtime での Modbus の確認はまだ行っていない。
- 通信の暗号化と認証の設定には対応していない（[SECURITY.md](SECURITY.md)）。
- ビルド済みのバイナリは配布していない。ソースからビルドする。
- `hmi_runtime --version` は、Simulator と同じ名前で `hmi_simulator 1.0.0` と表示する（Runtime は Simulator のソースを共有しているため）。

[1.0.0]: https://github.com/hang-up33/hmi-platform/releases/tag/v1.0.0
