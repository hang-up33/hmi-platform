# フェーズ進捗と開発ステータス

本ドキュメントは、Atlas（hmi-platform）プロジェクトにおける**フェーズ進捗および開発ステータスの正本（Single Source of Truth）**です。

---

## 現在のフェーズ

### **リファクタリング計画 (2026-07-22 承認・着手中)**

- **概要**: 機能追加は一切せず、`Editor/qml/Main.qml` の肥大化と「新 Widget 種別を足すたびに約 10 箇所を触る」分岐の散在を解消する。1 タスク = 1 PR。
- **進捗ステータス**:
  - **RF-A, RF-D, RF-B 完了**: RF-A（ツールバー / ダイアログ抽出）、RF-D（種別テーブル集約）、RF-B（インスペクタ本体 + インスペクタ専用ヘルパーを `InspectorPanel.qml` へ抽出。RF-A と合わせて Main.qml 2,712→346 行）。
  - **次タスク = RF-E**: Editor / Simulator の delegate 重複削減（着手時に方式 (a)/(b) を試作比較）。
- **計画書正本**: [Docs/refactoring-plan.md](refactoring-plan.md)「進捗」表

> **フェーズタスク（新機能）は Phase 11 完了時点で全消化済み。** 次フェーズは「未承認候補」からユーザーとスコープを確定してから着手する（自動着手禁止）。

---

## 完了済みフェーズ一覧

| フェーズ | 概要 | 主な成果物 / PR / 計画書 |
|---|---|---|
| **Phase 1** | MVP 開発 | Editor, Simulator, JSON Schema 基礎。[phase1-mvp-plan.md](phase1-mvp-plan.md) |
| **Phase 2** | テスト基盤 | Unit Test (QtTest) 基盤構築。[phase2-testing-plan.md](phase2-testing-plan.md) |
| **Phase 3-A** | E2E テスト | Spix (E2E) 統合。[phase3-e2e-plan.md](phase3-e2e-plan.md) |
| **Phase 3-B** | Runtime & 実機描画 | 3 バイナリ構成（Editor / Simulator / Runtime）、Yocto SDK クロスビルド、i.MX8MP 実機描画。[phase3b-runtime-plan.md](phase3b-runtime-plan.md) |
| **Phase 4** | Button 縦スライス | Button 1 つを全レイヤ（Schema→Widgets→Editor→Simulator→Runtime→実機）で深掘り。[phase4-button-slice-plan.md](phase4-button-slice-plan.md) |
| **Phase 4 拡張** | 編集体験 & 状態/アクション | グリッドスナップ、複数選択・整列、コピペ、undo-redo、変数ストア + アクション + 状態別スタイル。[phase4-button-slice-plan.md](phase4-button-slice-plan.md) |
| **インスペクタ UX 改善** | インスペクタ整理 | セクション化、色スウォッチ / ColorDialog。[inspector-ux-plan.md](inspector-ux-plan.md) |
| **Phase 5** | Label 横展開 | 型分岐の足場（Loader + Component）導入、Label Widget 追加。[phase5-widget-expansion-plan.md](phase5-widget-expansion-plan.md) |
| **Phase 6** | NumericField (数値入力) | 読み書き両用 binding、IntValidator。[phase6-input-widget-plan.md](phase6-input-widget-plan.md) |
| **Phase 6-B** | NumericField 拡張 | real 型 (`DoubleValidator`)、数値範囲 (min/max) clamp。[phase6b-numeric-extend-plan.md](phase6b-numeric-extend-plan.md) |
| **Phase 7** | Modbus TCP 通信 | QtSerialBus (QModbusTcpClient) ポーリング/書込、実 PLC 動作確認。[phase7-modbus-plan.md](phase7-modbus-plan.md) |
| **Phase 8** | Trend (折れ線グラフ) | QML Canvas 自描画、単系列ライブ折れ線グラフ。[phase8-trend-plan.md](phase8-trend-plan.md) |
| **Phase 8-B** | Trend 拡張 | 複数系列 (series)、軸目盛り / 凡例描画。[phase8b-trend-extend-plan.md](phase8b-trend-extend-plan.md) |
| **Phase 9** | OPC-UA クライアント | QtOpcUa クライアント、i.MX8MP 実機 VNC 動作確認。[phase9-opcua-plan.md](phase9-opcua-plan.md) |
| **Phase 10** | Meter (メーター) | QML Canvas 円弧＋針描画、スピードメーター風 Widget。[phase10-meter-plan.md](phase10-meter-plan.md) |
| **Phase 11** | Widget サンプルパレット + SimpleButton | 見た目そのままのサンプルを並べてキャンバスへ D&D 追加する汎用パレット UX、新 Widget 種別 `SimpleButton`。[phase11-widget-palette-plan.md](phase11-widget-palette-plan.md) |

---

## 注意事項・今後の未承認候補

- 履歴永続化、step / decimals / unit、後続入力 Widget (Toggle)、複数メータースタイル / 色帯、他 Widget プリセット拡充などの候補項目は未承認です。先にユーザーとスコープを確定させてから着手します（自動着手禁止）。
- 詳細な開発経緯・PR 履歴・学びは [Docs/development-history.md](development-history.md) を参照してください。
