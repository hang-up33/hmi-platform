# Docs/archive — 完了済みフェーズの計画書（歴史記録）

ここにあるのは **完了したフェーズの「実装指示書」** です。当時 AI エージェントに作業させるために書かれたもので、
スコープ・完了基準・レイヤ別の変更点・レビュー指摘番号などが含まれます。

> **⚠️ これらは現在の仕様書ではありません。**
> 「今の Atlas が何をできるか」を知りたい場合は [README.md](../../README.md) と [phase-status.md](../phase-status.md) を見てください。
> ここのファイルは「なぜそう作ったか」を遡って調べるときにだけ開く場所です。

## 中身

| ファイル | 何の記録か |
|---|---|
| [phase1-mvp-plan.md](phase1-mvp-plan.md) | MVP（Editor / Simulator / JSON Schema の基礎） |
| [phase2-testing-plan.md](phase2-testing-plan.md) | QtTest による単体テスト基盤 |
| [phase3-e2e-plan.md](phase3-e2e-plan.md) | Spix による E2E テスト統合 |
| [phase3b-runtime-plan.md](phase3b-runtime-plan.md) | Runtime 追加・Yocto クロスビルド・i.MX8MP 実機描画（計画） |
| [phase3b-runtime-journey.md](phase3b-runtime-journey.md) | 同上の振り返り（読み物。人間向け） |
| [phase4-button-slice-plan.md](phase4-button-slice-plan.md) | Button の縦スライス深掘り + 編集体験・変数・アクション |
| [inspector-ux-plan.md](inspector-ux-plan.md) | インスペクタの UX 改善 |
| [phase5-widget-expansion-plan.md](phase5-widget-expansion-plan.md) | Label 追加と型分岐の足場 |
| [phase6-input-widget-plan.md](phase6-input-widget-plan.md) | NumericField（数値入力） |
| [phase6b-numeric-extend-plan.md](phase6b-numeric-extend-plan.md) | NumericField の real 型・min/max 拡張 |
| [phase8-trend-plan.md](phase8-trend-plan.md) | Trend（折れ線グラフ） |
| [phase8b-trend-extend-plan.md](phase8b-trend-extend-plan.md) | Trend の複数系列・軸目盛り・凡例 |
| [phase9-opcua-plan.md](phase9-opcua-plan.md) | OPC-UA クライアント |
| [phase10-meter-plan.md](phase10-meter-plan.md) | Meter（メーター） |
| [phase11-widget-palette-plan.md](phase11-widget-palette-plan.md) | Widget サンプルパレット + SimpleButton |
| [ci-self-hosted-plan.md](ci-self-hosted-plan.md) | Proxmox self-hosted runner による自動 CI 復活 |
| [v1-release-plan.md](v1-release-plan.md) | v1.0 の OSS 公開（機微情報の棚卸し・ライセンス・CI の公開対応・公開作業） |
| [v1-release-runbook.md](v1-release-runbook.md) | v1.0 公開当日の手順書（履歴の置き換え・新しいリポジトリへの移行） |
| [requirements-legacy.md](requirements-legacy.md) | 旧要求仕様 / 機能バックログ（2026-10-31 に `Docs/requirements/` へ分割。実装状況は Phase 6-B 時点で止まっている） |
| [qml-canvas-structure.md](qml-canvas-structure.md) | Canvas.qml の構造解説（**内容が実装と乖離**。冒頭の注記を参照） |

Phase 7（Modbus）だけは実機作業（MB-5 / MB-6）が残っているため、[Docs/phase7-modbus-plan.md](../phase7-modbus-plan.md) に現行として置いています。
