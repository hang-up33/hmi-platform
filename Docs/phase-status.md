# フェーズ進捗と開発ステータス

本ドキュメントは、Atlas（hmi-platform）プロジェクトにおける**フェーズ進捗および開発ステータスの正本（Single Source of Truth）**です。

---

## 現在のフェーズ

### **Phase 11 / Widget サンプルパレット（D&D 追加）＋ 初号「シンプルボタン」** (着手中)

- **概要**: issue #155「シンプル・イズ・ベスト版 HMI ボタン（ベゼル無し）」を新 Widget 種別 `SimpleButton`（`HmiSimpleButton.qml`）として QML で忠実再現し、見た目そのままの Widget サンプルをインスペクタに並べてキャンバスへ D&D で追加する汎用パレット UX を新設。Canvas 自描画で新 Qt 依存ゼロ（Meter/Trend と同方針）。
- **進捗ステータス**:
  - **W-A〜W-D 完了**: Schema 拡張 / HmiSimpleButton 描画 + delegate 6 分岐目 / サンプルパレット / パレット→キャンバス D&D 追加（`addPresetWidget(preset, dropX, dropY)` を座標対応化 + Canvas に `DropArea`）。
  - **次タスク = W-E**: インスペクタ型対応 + cross-app E2E + スクショ。
- **計画書正本**: [Docs/phase11-widget-palette-plan.md](Docs/phase11-widget-palette-plan.md)「進捗」表

### **並行：リファクタリング計画 (2026-07-22 承認)**

- **進捗ステータス**:
  - **RF-A, RF-D 完了**: RF-A（ツールバー / ダイアログ抽出）、RF-D（種別テーブル集約）。
  - **次タスク = RF-B**: インスペクタ本体を `InspectorPanel.qml` へ抽出。
- **計画書正本**: [Docs/refactoring-plan.md](Docs/refactoring-plan.md)「進捗」表

---

## 完了済みフェーズ一覧

| フェーズ | 概要 | 主な成果物 / PR / 計画書 |
|---|---|---|
| **Phase 1** | MVP 開発 | Editor, Simulator, JSON Schema 基礎。[phase1-mvp-plan.md](Docs/phase1-mvp-plan.md) |
| **Phase 2** | テスト基盤 | Unit Test (QtTest) 基盤構築。[phase2-testing-plan.md](Docs/phase2-testing-plan.md) |
| **Phase 3-A** | E2E テスト | Spix (E2E) 統合。[phase3-e2e-plan.md](Docs/phase3-e2e-plan.md) |
| **Phase 3-B** | Runtime & 実機描画 | 3 バイナリ構成（Editor / Simulator / Runtime）、Yocto SDK クロスビルド、i.MX8MP 実機描画。[phase3b-runtime-plan.md](Docs/phase3b-runtime-plan.md) |
| **Phase 4** | Button 縦スライス | Button 1 つを全レイヤ（Schema→Widgets→Editor→Simulator→Runtime→実機）で深掘り。[phase4-button-slice-plan.md](Docs/phase4-button-slice-plan.md) |
| **Phase 4 拡張** | 編集体験 & 状態/アクション | グリッドスナップ、複数選択・整列、コピペ、undo-redo、変数ストア + アクション + 状態別スタイル。[phase4-button-slice-plan.md](Docs/phase4-button-slice-plan.md) |
| **インスペクタ UX 改善** | インスペクタ整理 | セクション化、色スウォッチ / ColorDialog。[inspector-ux-plan.md](Docs/inspector-ux-plan.md) |
| **Phase 5** | Label 横展開 | 型分岐の足場（Loader + Component）導入、Label Widget 追加。[phase5-widget-expansion-plan.md](Docs/phase5-widget-expansion-plan.md) |
| **Phase 6** | NumericField (数値入力) | 読み書き両用 binding、IntValidator。[phase6-input-widget-plan.md](Docs/phase6-input-widget-plan.md) |
| **Phase 6-B** | NumericField 拡張 | real 型 (`DoubleValidator`)、数値範囲 (min/max) clamp。[phase6b-numeric-extend-plan.md](Docs/phase6b-numeric-extend-plan.md) |
| **Phase 7** | Modbus TCP 通信 | QtSerialBus (QModbusTcpClient) ポーリング/書込、実 PLC 動作確認。[phase7-modbus-plan.md](Docs/phase7-modbus-plan.md) |
| **Phase 8** | Trend (折れ線グラフ) | QML Canvas 自描画、単系列ライブ折れ線グラフ。[phase8-trend-plan.md](Docs/phase8-trend-plan.md) |
| **Phase 8-B** | Trend 拡張 | 複数系列 (series)、軸目盛り / 凡例描画。[phase8b-trend-extend-plan.md](Docs/phase8b-trend-extend-plan.md) |
| **Phase 9** | OPC-UA クライアント | QtOpcUa クライアント、i.MX8MP 実機 VNC 動作確認。[phase9-opcua-plan.md](Docs/phase9-opcua-plan.md) |
| **Phase 10** | Meter (メーター) | QML Canvas 円弧＋針描画、スピードメーター風 Widget。[phase10-meter-plan.md](Docs/phase10-meter-plan.md) |

---

## 注意事項・今後の未承認候補

- 履歴永続化、step / decimals / unit、後続入力 Widget (Toggle)、複数メータースタイル / 色帯、他 Widget プリセット拡充などの候補項目は未承認です。先にユーザーとスコープを確定させてから着手します（自動着手禁止）。
- 詳細な開発経緯・PR 履歴・学びは [Docs/development-history.md](Docs/development-history.md) を参照してください。
