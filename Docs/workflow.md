# 開発ワークフローと開発ルール (Workflow & Rules)

本ドキュメントは、Atlas（hmi-platform）プロジェクトにおける**開発プロセス、ブランチ・PR 運用、および禁止事項の正本**です。

---

## 1. コア原則

1. **1 タスクずつ完結** — 設計書のフェーズタスク順（[Docs/phase-status.md](phase-status.md)）を厳守し、各タスクは `cmake --build` 成功を完了基準とします。
2. **Shared/Schema が唯一の真実** — Widget / Screen / Project に該当する型・JSON 入出力はここにのみ定義します。
3. **継続的改善（kaizen）の遵守** — タスク完了報告の前に、得た知見をドキュメント・ルール・スキルのいずれかに反映します（[kaizen-close](../.claude/skills/kaizen-close/SKILL.md) スキル）。
4. **既存資産の保護** — フォルダ構成変更禁止・既存コード削除禁止（対象は**ソース / ビルド構成**。`Docs/` 配下の整理はユーザー承認時に限り可）。
5. **計画してから実装** — 複雑なタスクはエージェントに計画させてから手を動かします。

---

## 2. ブランチ命名と PR ワークフロー

- **マージ方針**: 全ての変更は **PR 経由で main に取り込み**ます（main 直接 push は絶対禁止）。
- **ブランチ命名**:
  - フェーズタスク: `task/<N>-<短い名>`（例: `task/2-canvas`）
  - ドキュメント・設定: `docs/<短い名>`
- **1 単位 = 1 ブランチ = 1 PR**: 原則として `main` から派生します。直前 PR が未マージの場合は依存ブランチから派生し `gh pr create --base <依存>` を使用します。
- **PR 作成規約**:
  - PR は **ready-for-review**（draft 禁止）で作成します。
  - タイトル: `Task N: <短い説明>`
  - 本文: Summary / 変更点 / Test plan / Codex 向け補足
  - GUI 変更がある場合は動作証跡スクショを添付（[screenshot-capture](../.claude/skills/screenshot-capture/SKILL.md) スキル）。

---

## 3. Codex レビュー自走ループ

- **レビュー依頼**: `gh pr create` 直後と修正 push 直後の両方で `gh pr comment <N> --body "@codex review"` を投稿します。
- **自走ループ**: ユーザーの指示を待たずに Codex レビュー結果をポーリングし、指摘 0 件のクリーンレビュー（`Didn't find any major issues. 👍`）になるまで修正・push・再依頼を繰り返します。
- **マージ**: マージは Squash and merge でユーザーが行います。

---

## 4. 遵守ルール (Must Always / Must Never)

### Must Always
- **現フェーズのタスク順を守る**: 1 タスクずつ進め、複数フェーズタスクを 1 回でまとめて実装しません。未承認フェーズ（「候補」段階）には自動着手せず、先にスコープをユーザーと確定します。
- **Shared/Schema への型定義集中**: Widget / Screen / Project 型と JSON I/O は `Shared/Schema` にのみ実装します。
- **知見のルール化**: 新しい知見・方針は `.claude/rules/` に保存し、[.claude/rules/memory-index.md](../.claude/rules/memory-index.md) を更新します。

### Must Never
- 複数のフェーズタスクを 1 回でまとめて実装する。
- フォルダ構成を変更する（`Editor/`, `Simulator/`, `Runtime/`, `Shared/Schema/`, `Shared/Widgets/`, `Docs/` を維持）。
  - 守る対象は**ソース / ビルド構成**。`Docs/` 配下のサブディレクトリ整理（`Docs/archive/` など）は**ユーザー承認時に限り可**。
- 既存コードを削除する。
- qmake その他の代替ビルドシステムを導入する。
- main ブランチに直接 push / コミットする。
- 設計書未承認のフレームワーク / ライブラリを独断で追加する。
