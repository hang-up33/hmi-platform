# AGENTS.md

このファイルは **ChatGPT Codex（GitHub App / Codex CLI）** に対するリポジトリ共通の指示です。

---

## 1. 情報の正本（Single Source of Truth）

本リポジトリの開発指針、アーキテクチャ、タスク進捗、およびルールは以下のドキュメントを正本とします。
レビュー時や作業時には必ず該当ドキュメントを参照してください。

- **レビューガイドライン（詳細・観点）**: [Docs/review-guidelines.md](Docs/review-guidelines.md)
- **現在のフェーズ・タスク進捗**: [Docs/phase-status.md](Docs/phase-status.md)
- **アーキテクチャ・モジュール構造**: [Docs/architecture.md](Docs/architecture.md)
- **開発ワークフロー・開発ルール**: [Docs/workflow.md](Docs/workflow.md)
- **開発経緯・PR 履歴**: [Docs/development-history.md](Docs/development-history.md)

---

## 2. Review Guidelines 要約

Codex が PR レビューを行う際は、[Docs/review-guidelines.md](Docs/review-guidelines.md) の指示に従ってください。

- **言語**: **レビューコメントはすべて日本語で記述してください**（コード識別子・ファイルパス・引用ブロックは英語可）。
- **指摘フォーマット**: 「何が」「なぜ問題か」「どう直すべきか」の 3 点を明記し、重要度（`[Blocker]` / `[Major]` / `[Minor]` / `[Nit]`）を付けてください。
- **制約事項**: フォルダ構成の変更提案、qmake の導入提案、および現在進行中フェーズを逸脱する大規模リファクタ提案は禁止です。
- **重点観点**:
  - `Shared/Schema` が JSON I/O の唯一の真実であること
  - QML モジュール URI と `loadFromModule()` の一致
  - QtQuick 標準型との QML ファイル命名衝突回避（`Hmi` プレフィックス必須）
  - 共有 QML モジュール (`Shared/Widgets`) の STATIC ビルド構成
  - macOS での Qt バージョン罠（`~/Qt/6.7.0/macos` 指定の禁止）
