# フェーズ進捗と開発ステータス

このドキュメントは、Atlas（hmi-platform）が**いま何合目か・どこまで終わったか**を知りたいときに見る場所（進捗の正本）。

---

## 現在のフェーズ

### **v1.0 公開準備（OSS 化）(2026-11-05 承認・着手中)**

- **概要**: **2026-11-09（月）に v1.0 を MIT ライセンスの OSS として公開する**。11/5〜11/9 は機能凍結し、機微情報の確認・ライセンス・CI の公開対応・公開作業だけを行う。
- **進捗ステータス**: V1-0（計画書）と V1-1（機微情報の棚卸し）完了。秘密情報は 0 件。作者メールを置き換えた履歴を新しい public リポジトリへ移す方針に決めた。V1-2（`LICENSE` とライセンス一覧）も完了。次タスク = V1-3（CONTRIBUTING などの公開用ファイル）。
- **計画書正本**: [Docs/v1-release-plan.md](v1-release-plan.md)「進捗」表

### **契約→テスト→実装（DbC + テスト先行）の導入 (開発プロセスの改善)**

- **進捗ステータス**: DT-1（計画とルール）完了（#181）。DT-2〜DT-6 は未着手で、v1.0 公開後に着手する。
- **計画書正本**: [Docs/dbc-tdd-plan.md](dbc-tdd-plan.md)「進捗」表

### **リファクタリング計画 (2026-07-22 承認・一区切り。残りは保留)**

- **概要**: リファクタリング中は機能追加を一切行わず、`Editor/qml/Main.qml` の肥大化と「新しい Widget 種別を足すたびに約 10 箇所を触らないといけない」という散らばりを整理する。1 タスク = 1 PR で進める。
- **進捗ステータス**:
  - **RF-A, RF-B, RF-D, RF-E, RF-G 完了**: RF-A（ツールバー / ダイアログ抽出）、RF-B（インスペクタ本体を `InspectorPanel.qml` へ抽出。Main.qml 2,712→346 行）、RF-D（種別テーブル集約）、RF-E（Button / Label / SimpleButton の delegate を `Shared/Widgets` の型別ホスト QML へ集約・#178）、RF-G（`InspectorPanel.qml` をセクション単位のファイルへ分割。2,372→435 行・#180）。
  - **保留**: RF-E の残り種別（NumericField / Trend / Meter）と RF-F（`widgetModel` のモデル化）。v1.0 公開後に必要になったら再評価する。
- **計画書正本**: [Docs/refactoring-plan.md](refactoring-plan.md)「進捗」表

> **新機能のフェーズタスクは Phase 11 で全部やり終えている。** 次のフェーズは「まだ承認前の候補」の中からユーザーと相談して範囲を決めてから着手する（勝手には始めない）。

---

## 完了済みフェーズ一覧

完了したフェーズの計画書は [Docs/archive/](archive/) に置いてある（当時の実装指示書なので、今の仕様書としては読まないこと）。

| フェーズ | 概要 | 主な成果物 / PR / 計画書 |
|---|---|---|
| **Phase 1** | MVP 開発 | Editor, Simulator, JSON Schema 基礎。[phase1-mvp-plan.md](archive/phase1-mvp-plan.md) |
| **Phase 2** | テスト基盤 | Unit Test (QtTest) 基盤構築。[phase2-testing-plan.md](archive/phase2-testing-plan.md) |
| **Phase 3-A** | E2E テスト | Spix (E2E) 統合。[phase3-e2e-plan.md](archive/phase3-e2e-plan.md) |
| **Phase 3-B** | Runtime & 実機描画 | 3 バイナリ構成（Editor / Simulator / Runtime）、Yocto SDK クロスビルド、i.MX8MP 実機描画。[phase3b-runtime-plan.md](archive/phase3b-runtime-plan.md) |
| **Phase 4** | Button 縦スライス | Button 1 つを全レイヤ（Schema→Widgets→Editor→Simulator→Runtime→実機）で深掘り。[phase4-button-slice-plan.md](archive/phase4-button-slice-plan.md) |
| **Phase 4 拡張** | 編集体験 & 状態/アクション | グリッドスナップ、複数選択・整列、コピペ、undo-redo、変数ストア + アクション + 状態別スタイル。[phase4-button-slice-plan.md](archive/phase4-button-slice-plan.md) |
| **インスペクタ UX 改善** | インスペクタ整理 | セクション化、色スウォッチ / ColorDialog。[inspector-ux-plan.md](archive/inspector-ux-plan.md) |
| **Phase 5** | Label 横展開 | 型分岐の足場（Loader + Component）導入、Label Widget 追加。[phase5-widget-expansion-plan.md](archive/phase5-widget-expansion-plan.md) |
| **Phase 6** | NumericField (数値入力) | 読み書き両用 binding、IntValidator。[phase6-input-widget-plan.md](archive/phase6-input-widget-plan.md) |
| **Phase 6-B** | NumericField 拡張 | real 型 (`DoubleValidator`)、数値範囲 (min/max) clamp。[phase6b-numeric-extend-plan.md](archive/phase6b-numeric-extend-plan.md) |
| **Phase 7** | Modbus TCP 通信 | QtSerialBus (QModbusTcpClient) ポーリング/書込、実 PLC 読込確認。**機能は完了だが MB-5（実 PLC 書込確認）/ MB-6（実機 Runtime 展開）は未着手**（実機作業のため Web 不可）。[phase7-modbus-plan.md](phase7-modbus-plan.md) |
| **Phase 8** | Trend (折れ線グラフ) | QML Canvas 自描画、単系列ライブ折れ線グラフ。[phase8-trend-plan.md](archive/phase8-trend-plan.md) |
| **Phase 8-B** | Trend 拡張 | 複数系列 (series)、軸目盛り / 凡例描画。[phase8b-trend-extend-plan.md](archive/phase8b-trend-extend-plan.md) |
| **Phase 9** | OPC-UA クライアント | QtOpcUa クライアント、i.MX8MP 実機 VNC 動作確認。[phase9-opcua-plan.md](archive/phase9-opcua-plan.md) |
| **Phase 10** | Meter (メーター) | QML Canvas 円弧＋針描画、スピードメーター風 Widget。[phase10-meter-plan.md](archive/phase10-meter-plan.md) |
| **Phase 11** | Widget サンプルパレット + SimpleButton | 見た目そのままのサンプルを並べてキャンバスへ D&D 追加する汎用パレット UX、新 Widget 種別 `SimpleButton`。[phase11-widget-palette-plan.md](archive/phase11-widget-palette-plan.md) |

---

## 注意事項・今後の未承認候補

- 履歴永続化、step / decimals / unit、後続入力 Widget (Toggle)、複数メータースタイル / 色帯、他 Widget プリセット拡充などは、まだ「候補」のままで承認されていない。着手する前に、必ずユーザーと範囲を決める。
- これまでの開発の経緯・PR 履歴・学びは [Docs/development-history.md](development-history.md) にまとめてある。
