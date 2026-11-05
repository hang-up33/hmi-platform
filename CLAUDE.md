# CLAUDE.md

このファイルは、本リポジトリで作業する Claude Code への指針です。
**ユーザーは日本人のため、応答・ドキュメント・コミットメッセージは日本語を基本とします**（コード識別子は英語可）。

> **本プロジェクトの開発コードネームは「Atlas（アトラス）」**（正式プロジェクト名: `hmi-platform`）。詳細は [README.md](README.md)。

---

## 情報の正本（Single Source of Truth）

プロジェクトの仕様・アーキテクチャ・進捗・ルールは **`Docs/` 配下のドキュメントおよび `.claude/` を正本**とします。

- **ドキュメント地図（人間向け / AI 向けの区分）**: [DOCS-MAP.md](DOCS-MAP.md) — **文書を追加・移動したらここを更新する**
- **フェーズ進捗・開発ステータス**: [Docs/phase-status.md](Docs/phase-status.md)
- **アーキテクチャ・モジュール構造**: [Docs/architecture.md](Docs/architecture.md)
- **開発ワークフロー・開発ルール**: [Docs/workflow.md](Docs/workflow.md)
- **コードレビューガイドライン**: [Docs/agents/review-guidelines.md](Docs/agents/review-guidelines.md)
- **開発経緯・PR / 学びの歴史**: [Docs/development-history.md](Docs/development-history.md)
- **開発環境の現状（ホスト/WSL/実機）**: [.claude/rules/dev-environment.md](.claude/rules/dev-environment.md)
- **Claude on the Web での開発**: [Docs/claude-web-dev.md](Docs/claude-web-dev.md)

---

## クイックスタート（ビルドと実行）

詳細なビルド手順と既知の罠は [qt6-build](.claude/skills/qt6-build/SKILL.md) スキルを参照してください。

```sh
# macOS (Qt 6.8+)
cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt
cmake --build build
./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor
```

```powershell
# Windows (Qt 6.11.0 MinGW + Ninja)
.\scripts\windows\build.ps1
. .\scripts\windows\setup-env.ps1
.\build-mingw\hmi_editor.exe
```

---

## コア原則 (要約)

詳細は [Docs/workflow.md](Docs/workflow.md) を参照。

1. **1 タスクずつ完結** — 設計書のフェーズタスク順（[Docs/phase-status.md](Docs/phase-status.md)）を厳守し、`cmake --build` 成功を完了基準とする。
2. **Shared/Schema が唯一の真実** — Widget / Screen / Project に該当する型・JSON 入出力は `Shared/Schema` にのみ実装する。
3. **継続的改善（kaizen）の遵守** — タスク完了直前に [kaizen-close](.claude/skills/kaizen-close/SKILL.md) スキルで得た知見をドキュメント/ルールに反映する。
4. **既存資産の保護** — フォルダ構成変更禁止・既存コード削除禁止・qmake等代替ビルドシステム導入禁止（対象は**ソース / ビルド構成**。`Docs/` 配下の整理はユーザー承認時に限り可）。
5. **PR ワークフロー & Codex レビュー** — ブランチは `task/<N>-<名>`、Codex レビューの依頼は 1 PR 1 回。Blocker / Major を直して push し、再依頼しない（[feedback-review-convergence](.claude/rules/feedback-review-convergence.md)）（マージはユーザーが行う）。
6. **応答スタイル** — 日本語・敬語なし（常体）・簡潔な応答を基本とする。
7. **契約 → テスト → 実装** — 本番コードは「当てはまる契約条件（事前・事後・不変）を書く → 条件ごとのテストを先に書き失敗を確認（振る舞いを変えないリファクタリングは変更前の成功を確認）→ テストに触らず実装」の順で書く（[dbc-tdd](.claude/rules/dbc-tdd.md) / 導入計画 [Docs/dbc-tdd-plan.md](Docs/dbc-tdd-plan.md)）。

---

## 利用可能なスキル

| スキル | 用途 |
|---|---|
| [ship-task](.claude/skills/ship-task/SKILL.md) | 実装を done まで一気通貫で仕上げるオーケストレータ（実装→ビルド→ctest→kaizen→進捗同期→PR→Codex レビュー対応）。詳細は下記 skill へ委譲・Web/ローカル環境差を吸収 |
| [mvp-next-task](.claude/skills/mvp-next-task/SKILL.md) | フェーズタスク進行標準ワークフロー |
| [codex-pr](.claude/skills/codex-pr/SKILL.md) | PR 作成と Codex レビュー（1 PR 1 回）の待ち受け・修正 |
| [qt6-build](.claude/skills/qt6-build/SKILL.md) | Qt6 + CMake ビルド手順・プラットフォーム別ビルド |
| [e2e-spix](.claude/skills/e2e-spix/SKILL.md) | Spix (E2E) テスト実行手順 |
| [screenshot-capture](.claude/skills/screenshot-capture/SKILL.md) | 動作証跡スクショ撮影 |
| [kaizen-close](.claude/skills/kaizen-close/SKILL.md) | タスク完了前の知見反映手順 |
| [hero-demo](.claude/skills/hero-demo/SKILL.md) | README ヒーロー画像用のショーケース demo 組み立て・撮り直し |
| [progress-summary](.claude/skills/progress-summary/SKILL.md) | 指定期間の実装状況・進捗を PR / タスク単位で列挙 |
| [code-comprehension-drill](.claude/skills/code-comprehension-drill/SKILL.md) | コード / PR を能動的に読み込んで理解度を詰める学習ループ |

---

## ドキュメント・領域別規約 (path-scoped rules)

- **Schema 規約**: [.claude/rules/schema-conventions.md](.claude/rules/schema-conventions.md)
- **QML モジュール規約**: [.claude/rules/qml-module-conventions.md](.claude/rules/qml-module-conventions.md)
- **README スクショ同期**: [.claude/rules/readme-screenshot-sync.md](.claude/rules/readme-screenshot-sync.md)

---

## Agent skills（Matt Pocock skills 用設定）

Matt Pocock の engineering skills が参照する設定。詳細は `Docs/agents/*.md`。

### Issue トラッカー

このリポジトリは GitHub Issues を使わない。機能要求は [Docs/requirements/](Docs/requirements/README.md)（関心別の要求仕様書）、
実装タスクと進捗は `Docs/phase*-plan.md`（進行中）/ `Docs/archive/phase*-plan.md`（完了済み）で管理する（各計画書の「進捗」表が正本）。
デリバリは `task/<N>-<名>` ブランチ + PR + Codex レビュー（1 PR 1 回）。詳細は [Docs/agents/issue-tracker.md](Docs/agents/issue-tracker.md)。

### Domain docs

single-context。着手前に [Docs/architecture.md](Docs/architecture.md) / [Docs/requirements/](Docs/requirements/README.md) / `.claude/rules/` を読む。
ADR の正式な置き場（`Docs/adr/`）は未整備で、必要になった時点で作る。詳細は [Docs/agents/domain.md](Docs/agents/domain.md)。
