# メモリ索引（クロスマシン共有）

このディレクトリ（`.claude/rules/`）配下の `*.md` は、元々 Mac のローカル自動メモリ
（`~/.claude/projects/<project>/memory/`）に蓄積していた知見を **git 管理の共有メモリ** に移したもの。

> **なぜ rules に置くか**：自動メモリは **マシンローカル**で Windows ↔ Mac を跨いで共有されない。
> 一方 `.claude/rules/*.md` は git 管理＋毎セッション自動読込されるため、どのマシンでも同じ知見を参照できる。
> 環境固有の現状は [dev-environment.md](dev-environment.md)、本ファイルは「振る舞い・好み」の知見索引。
> （Claude Code メモリ仕様：https://code.claude.com/docs/ja/memory ）

## 運用ルール

- **新しい知見が出たらこのディレクトリに 1 ファイル追加**し、本索引に 1 行追記する（ファイル名は小文字＋ハイフン区切り）。
- **二重メンテを避ける**：CLAUDE.md / `Docs/*.md` に書ける「プロジェクト事実・設計判断」はそちらを正とし、ここには置かない。ここに残すのは **作業の進め方・好み（user / feedback / reference）** と、CLAUDE.md に要約しか無い保留事項。
- 本文中の `[[slug]]` は同ディレクトリの該当ファイル（`slug.md`）への相互参照。

## 索引

### user / feedback（作業の進め方・好み）

- [User language (Japanese)](user-language-japanese.md) — ユーザーは日本人、書き物は日本語優先
- [Continuous improvement](feedback-continuous-improvement.md) — タスク完了前に知見を CLAUDE.md / README / メモリに反映する
- [Docs style](feedback-docs-style.md) — ドキュメントは Mermaid 図 + 最小説明から始める。冗長な ASCII 図 + 詳細散文は嫌われる
- [Codex review comment](feedback-codex-review-comment.md) — PR 作成後・修正 push 後は毎回 `@codex review` を明示投稿する
- [Codex auto-loop](feedback-codex-auto-loop.md) — PR 作成後は Codex レビューを自走で待ち、指摘 0 件まで修正→再 push→再依頼を繰り返す
- [CodeRabbit fallback](feedback-coderabbit-fallback.md) — Codex が利用上限で沈黙したら、代替レビュアー CodeRabbit の指摘を同じ自走ループで対応する
- [Plan docs consistency](feedback-plan-docs-consistency.md) — 計画ドキュメントは API 制約・未確認情報の保留・複数アプリ統合・既定値・README 同期の 5 点を守る

### reference

- [Context7 MCP](reference-context7-mcp.md) — ユーザースコープで導入済み、最新ライブラリドキュメント参照に使える（Qt6/QML 等）

### project（CLAUDE.md / Docs に要約しか無い保留事項）

- [widgetModel refactor deferred](project-widgetmodel-refactor-deferred.md) — widgetModel の QAbstractListModel 化は Phase 3-B スコープ確定後に再評価（保留の経緯付き。CLAUDE.md は要約のみ）

### project 規約（path-scoped — 該当ファイル編集時のみロード）

CLAUDE.md の肥大化対策で切り出した詳細規約。`paths:` frontmatter で対象ファイルを触る時だけ自動ロードされる（CLAUDE.md 側にはポインタ表のみ残置）。

- [schema-conventions](schema-conventions.md) — Shared/Schema の型・JSON I/O 実装規約（`paths: Shared/Schema/**`）
- [qml-module-conventions](qml-module-conventions.md) — QML モジュール URI・命名衝突・STATIC plugin 共有・EditableWidget 結線・Simulator/Runtime ソース共有・ルート CMake の `add_subdirectory` 順序制約（`paths: **/*.qml`・Editor/Simulator/Runtime/Shared/Widgets・`**/CMakeLists.txt`）

## 重複のため移植しなかったメモリ（実体は git 管理ドキュメント側）

以下はローカル自動メモリに存在したが、既に CLAUDE.md / `Docs/*.md` に git 管理で書かれているため、二重メンテ回避のため移植せず実体を正とする：

| 旧メモリ | 実体（正） |
|---|---|
| Review owner: Codex | [CLAUDE.md](../../CLAUDE.md)「コードレビューの担当分け」 |
| Codex PR workflow | [CLAUDE.md](../../CLAUDE.md)「Codex 連携 / PR ワークフロー」 |
| Phase 2 testing plan | [Docs/phase2-testing-plan.md](../../Docs/phase2-testing-plan.md) |
| Phase 3-A E2E plan | [Docs/phase3-e2e-plan.md](../../Docs/phase3-e2e-plan.md) |
| Phase 3-B Runtime plan | [Docs/phase3b-runtime-plan.md](../../Docs/phase3b-runtime-plan.md) |
| Runtime host OS | [dev-environment.md](dev-environment.md) / [Docs/phase3b-runtime-plan.md](../../Docs/phase3b-runtime-plan.md) |
| Runtime transfer requirement | [Docs/phase3b-runtime-plan.md](../../Docs/phase3b-runtime-plan.md)（Phase 3-C 候補・転送機能は持たない方針） |
| Development history doc | [Docs/development-history.md](../../Docs/development-history.md) |
