---
name: feedback-coderabbit-fallback
description: Codex の利用上限到達時は、代替レビュアー CodeRabbit のレビューを拾って Codex と同じ流れで対応する
metadata: 
  type: feedback
---

本プロジェクトのコードレビューは原則 **Codex GitHub App** が担当する（[CLAUDE.md](../../CLAUDE.md)「コードレビューの担当分け」）。ただし **Codex が利用上限（レート / クォータ）に達して沈黙した場合**、代わりに **CodeRabbit（GitHub App。2026-06-08 導入）** がレビューを返すことがある。その時は CodeRabbit のレビュー指摘も Codex と同様に拾って対応する。

**Why:** ユーザーが 2026-06-08 に「Codex 利用上限が来たら CodeRabbit からレビューが帰ってくるかもしれない。その時は対応してね」と明示指示した。Codex 上限で PR が止まると困るため、フォールバックのレビュアーを用意した。

**How to apply:**

- PR のレビュー待ち受け（[[feedback-codex-auto-loop]]）でレビュー待ちポーリング中、**Codex が上限等で返ってこない場合は CodeRabbit のレビューコメント（issue / inline / review オブジェクト）も検出対象に含める**。
- CodeRabbit の指摘も Codex 指摘と同じ扱いで対応する。依頼（`@coderabbitai review`）は Codex と合わせて 1 PR 1 回。Blocker / Major を直して push し、再依頼せずに完了報告する（[[feedback-review-convergence]]）。
- どちらのレビュアーが応答しているかを確認し、**実際に返ってきた側の指摘に対応する**（Codex が生きていれば従来どおり Codex 優先、上限時のみ CodeRabbit にフォールバック）。
- 大規模な方針差し戻し指摘は、レビュアーに関わらず自走を中断してユーザーに相談する。
- **Codex の上限通知の文言**：上限時 Codex（`chatgpt-codex-connector[bot]`）は issue コメントに `"You have reached your Codex usage limits for code reviews."` を投稿する。これを検出したら即フォールバック（`@coderabbitai review` を投稿）に切り替えてよい（10 分待つ必要はない）。
- **CodeRabbit の検出は Codex と段階が違う（実証：PR #88 / 2026-06-09 初フォールバック）**：CodeRabbit（`coderabbitai[bot]`）は ①受付 ack（本文に `auto-generated reply` / "Review triggered"）→ ②`"review in progress"` → ③**最終サマリ**、の順で出すが、**②と③は同一 issue コメントを編集して更新**する（新規コメントが増えない）。よって `created_at` の新しさだけで待つと空振りする。検出は **本文で除外**する：`auto-generated reply` と `review in progress` を含むものを弾き、残った CodeRabbit issue コメントを最終レビューとみなす。指摘有無は最終サマリ本文の **`No actionable comments were generated`（=クリーン 🎉）** か、`Actionable comments posted: N`（N>0）/ inline コメント / review オブジェクトで判定する。再レビューは `@coderabbitai review`（CodeRabbit は incremental で、明示しないと既レビュー済みコミットを再評価しない）。再依頼はユーザーが頼んだときだけ行う。

関連：[[feedback-codex-auto-loop]] / [[feedback-codex-review-comment]] / PR ワークフローは [CLAUDE.md](../../CLAUDE.md)「Codex 連携 / PR ワークフロー」
