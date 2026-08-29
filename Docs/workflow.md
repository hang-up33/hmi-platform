# 開発ワークフローと開発ルール (Workflow & Rules)

このドキュメントは、Atlas（hmi-platform）の**開発の進め方・ブランチとPRの運用・やってはいけないことの正本**。

---

## 1. コア原則

1. **1 タスクずつ完結させる** — 設計書のフェーズタスクの順番（[Docs/phase-status.md](phase-status.md)）を守り、各タスクは `cmake --build` が通ることを完了基準にする。
2. **Shared/Schema が唯一の真実** — Widget / Screen / Project にあたる型・JSON の入出力は、ここにだけ定義する。
3. **継続的改善（kaizen）を続ける** — タスク完了を報告する前に、得た知見をドキュメント・ルール・スキルのどれかに反映する（[kaizen-close](../.claude/skills/kaizen-close/SKILL.md) スキル）。
4. **既存の資産を守る** — フォルダ構成は変えない・既存コードは消さない（対象は**ソース / ビルド構成**。`Docs/` 配下の整理は、ユーザーの承認があるときだけOK）。
5. **計画してから実装する** — 複雑なタスクは、まずエージェントに計画を立てさせてから手を動かす。

---

## 2. ブランチ命名と PR ワークフロー

- **マージ方針**: 変更はすべて **PR 経由で main に取り込む**（main への直接 push は絶対にしない）。
- **ブランチ命名**:
  - フェーズタスク: `task/<N>-<短い名>`（例: `task/2-canvas`）
  - ドキュメント・設定: `docs/<短い名>`
- **1 単位 = 1 ブランチ = 1 PR**: 基本は `main` から枝分かれさせる。直前の PR がまだマージされていないときは、その依存先のブランチから枝分かれさせて `gh pr create --base <依存>` を使う。
- **PR 作成のお作法**:
  - PR は **ready-for-review**（draft はNG）で作る。
  - タイトル: `Task N: <短い説明>`
  - 本文: Summary / 変更点 / Test plan / Codex 向け補足
  - GUI の見た目や操作を変更した場合は、動作証跡のスクショを添付する（[screenshot-capture](../.claude/skills/screenshot-capture/SKILL.md) スキル）。

---

## 3. Codex レビュー自走ループ

- **レビュー依頼**: `gh pr create` の直後と、修正を push した直後の両方で `gh pr comment <N> --body "@codex review"` を投稿する。
- **自走ループ**: ユーザーの指示を待たず Codex のレビュー結果をポーリングし、指摘が0件のクリーンなレビュー（`Didn't find any major issues. 👍`）になるまで、修正・push・再依頼を繰り返す。
- **マージ**: マージ（Squash and merge）はユーザーが行う。

---

## 4. 遵守ルール (Must Always / Must Never)

### Must Always
- **現フェーズのタスク順を守る**: 1 タスクずつ進め、複数フェーズのタスクをまとめて一気に実装しない。承認前のフェーズ（「候補」段階）には勝手に着手せず、まずユーザーと範囲を決める。
- **Shared/Schema に型を集める**: Widget / Screen / Project の型と JSON I/O は `Shared/Schema` にだけ実装する。
- **知見はルール化する**: 新しく分かったこと・方針は `.claude/rules/` に書き残し、[.claude/rules/memory-index.md](../.claude/rules/memory-index.md) も更新する。

### Must Never
- 複数のフェーズタスクを一度にまとめて実装すること。
- フォルダ構成を変えること（`Editor/`, `Simulator/`, `Runtime/`, `Shared/Schema/`, `Shared/Widgets/`, `Docs/` は維持する）。
  - 守るべきは**ソース / ビルド構成**。`Docs/` 配下の整理（`Docs/archive/` など）は**ユーザーの承認があるときだけ**OK。
- 既存のコードを削除すること。
- qmake など、別のビルドシステムを持ち込むこと。
- main ブランチに直接 push / コミットすること。
- 設計書でまだ承認されていないフレームワーク・ライブラリを、勝手に追加すること。
