# 番号の一覧

タスクや要件の番号は、計画書ごとに別の体系で付いている。この表は、どの番号がどこにあるかを引くための索引である。進捗の正本は、各計画書の「進捗」表（全体の目安は [phase-status.md](phase-status.md)）。

## 実装タスクの番号

| 番号 | 対象 | 計画書 | 状態 |
|---|---|---|---|
| `Task 1`〜`Task 8` | MVP | [Phase 1](archive/phase1-mvp-plan.md) | 完了 |
| `Task 9`〜`Task 15` | テスト基盤 | [Phase 2](archive/phase2-testing-plan.md) | 完了 |
| `Task 16`〜`Task 21` | E2E テスト | [Phase 3-A](archive/phase3-e2e-plan.md) | 完了 |
| `Task 22`〜`Task 24` | Runtime と実機描画 | [Phase 3-B](archive/phase3b-runtime-plan.md) | 完了 |
| `Task 25`〜`Task 43` | Button 縦スライスと拡張 | [Phase 4](archive/phase4-button-slice-plan.md) | 完了 |
| `Task 44`〜`Task 46` | インスペクタ整理 | [インスペクタ UX](archive/inspector-ux-plan.md) | 完了 |
| `Task 47`〜`Task 49` | Label | [Phase 5](archive/phase5-widget-expansion-plan.md) | 完了 |
| `Task 50`〜`Task 52` | NumericField | [Phase 6](archive/phase6-input-widget-plan.md) | 完了 |
| `Task 53`〜`Task 55` | NumericField 拡張 | [Phase 6-B](archive/phase6b-numeric-extend-plan.md) | 完了 |
| `MB-1`〜`MB-6` | Modbus | [phase7-modbus-plan.md](phase7-modbus-plan.md) | MB-1〜4 完了。MB-5・6 は実機作業のため未着手 |
| `T-A`〜`T-D` | Trend | [Phase 8](archive/phase8-trend-plan.md) | 完了 |
| `8B-A`〜`8B-E` | Trend 拡張 | [Phase 8-B](archive/phase8b-trend-extend-plan.md) | 完了 |
| `OP-1`〜`OP-6` | OPC-UA | [Phase 9](archive/phase9-opcua-plan.md) | 完了 |
| `M-A`〜`M-D` | Meter | [Phase 10](archive/phase10-meter-plan.md) | 完了 |
| `W-A`〜`W-E` | サンプルパレット・SimpleButton | [Phase 11](archive/phase11-widget-palette-plan.md) | 完了 |
| `V1-0`〜`V1-8` | v1.0 公開準備 | [v1-release-plan.md](archive/v1-release-plan.md) | 完了 |
| `RF-A`〜`RF-G` | リファクタリング | [refactoring-plan.md](refactoring-plan.md) | RF-A・B・D・G 完了、RF-E は一部、RF-F は保留、RF-C は取り下げ |

## 要件の番号

要求仕様書（[requirements/](requirements/README.md)）は、`REQ-<関心>-<3 桁>` と `ACC-<関心>-<3 桁>` の組で番号を付ける。例は `REQ-DAT-001`。

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

旧い要件の番号（`FR-` と `NFR-` で始まるもの）は、[requirements-legacy.md](archive/requirements-legacy.md) にある。新しい番号との対応は、[requirements/README.md](requirements/README.md) の「旧 requirements.md との対応」を見る。

## 注意

- `MB-` と `OP-` はタスクの番号である。`MBS` と `OPC` は要件の接頭辞で、別のものである。
- `T25` のような略記は `Task 25` のことで、Trend の `T-A` とは別である。Phase 4 の計画書に多く出てくる。
- 古い計画書には、番号を持たないものや、別の区切りを使うものがある。例は、CI 復活計画（番号なし）、v1.0 公開計画の決定事項 `D1`〜`D10`、Phase 3 の小区分 `Phase 3-A-1`〜`3` である。
- PR 番号は、公開前のリポジトリの番号（#181 など）と、公開後の番号（#1 から）が混ざっている。
