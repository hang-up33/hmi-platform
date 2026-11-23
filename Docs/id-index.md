# 番号の一覧

タスクや要件の番号は、計画書ごとに別の体系で付いている。この表は、どの番号がどこにあるかを引くための索引である。進捗の正本は、各計画書の「進捗」表（全体の目安は [phase-status.md](phase-status.md)）。

## 実装タスクの番号

| 接頭辞・形式 | 範囲 | 計画書 | 状態 |
|---|---|---|---|
| `Task N`（通し番号） | 1〜55 | フェーズ 1〜6-B（[Phase 1](archive/phase1-mvp-plan.md)〜[Phase 6-B](archive/phase6b-numeric-extend-plan.md)）と[インスペクタ UX](archive/inspector-ux-plan.md) | 完了。新規には使わない |
| `MB-1`〜`MB-6` | Modbus | [phase7-modbus-plan.md](phase7-modbus-plan.md) | MB-1〜4 完了。MB-5・6 は実機作業のため未着手 |
| `T-A` ほか | Trend | [Phase 8](archive/phase8-trend-plan.md) | 完了 |
| `8B-A` ほか | Trend 拡張 | [Phase 8-B](archive/phase8b-trend-extend-plan.md) | 完了 |
| `OP-1`〜`OP-6` | OPC-UA | [Phase 9](archive/phase9-opcua-plan.md) | 完了 |
| `M-A` ほか | Meter | [Phase 10](archive/phase10-meter-plan.md) | 完了 |
| `W-A` ほか | サンプルパレット・SimpleButton | [Phase 11](archive/phase11-widget-palette-plan.md) | 完了 |
| `V1-0`〜`V1-8` | v1.0 公開準備 | [v1-release-plan.md](archive/v1-release-plan.md) | 完了（2026-11-09 公開） |
| `RF-A`〜`RF-G` | リファクタリング | [refactoring-plan.md](refactoring-plan.md) | RF-A・B・D・G 完了、RF-E は一部、RF-F は保留、RF-C は取り下げ |
| `DT-1`〜`DT-6` | 契約→テスト→実装の導入 | [dbc-tdd-plan.md](dbc-tdd-plan.md) | DT-1 完了。DT-2〜6 は未着手 |

## 要件の番号

要求仕様書（[requirements/](requirements/README.md)）は、`REQ-<関心>` と `ACC-<関心>` の組で番号を付ける。

| 仕様書 | 接頭辞 |
|---|---|
| 01-data-model | `DAT` |
| 02-widgets | `WGT` |
| 03-project-format | `PRJ` |
| 04-editor | `EDT` |
| 05-runtime-simulator | `RUN` |
| 06-modbus | `MBS` |
| 07-opcua | `OPC` |
| 08-navigation | `NAV` |
| 09-alarm-logging | `ALM` |
| 10-remote-monitoring | `RMT` |
| 11-quality-ops | `QOP` |

## 注意

- `MB-` はタスク、`MBS` は要件の接頭辞で、別のものである。
- PR 番号は、公開前のリポジトリの番号（#181 など）と、公開後の番号（#1 から）が混ざっている。
- 新しい計画書を作るときは、`<略称>-<番号>`（`DT-2` の形）で付け、この表に 1 行足す。夜間実装のブランチ名（`task/<ID>-<名>`）にも、この形が合う。
