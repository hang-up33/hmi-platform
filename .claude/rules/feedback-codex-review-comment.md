---
name: feedback-codex-review-comment
description: "PR 作成直後に `@codex review` を 1 回だけ明示投稿する（修正 push 後は投稿しない）"
metadata: 
  type: feedback
---

PR を `gh pr create` で作成した直後に、`gh pr comment <N> --body "@codex review"` を実行して Codex に明示的なレビューを依頼する。

2026-11-05 以降は、PR 作成直後の 1 回だけ投稿する。修正 push 後は再依頼しない（[[feedback-review-convergence]]）。

**Why:** Codex の自動レビューはトリガが「Open PR / Draft → Ready / `@codex review` コメント」の 3 種類だが、ユーザーは「毎回明示的に欲しい」と表明（2026-05-25）。自動レビューに頼ると、push の差分によっては Codex が再レビューを判断せず黙ることがあるため、コメントで明示的に合図を送る。当初は push のたびに投稿していたが、2026-11-05 に往復が増えすぎる問題への対応として 1 PR 1 回に変更した。

**How to apply:** [[codex-pr]] スキルの最後に実行する。
```sh
gh pr create ... # PR URL を取得
gh pr comment <PR番号> --body "@codex review"
```
適用対象は本プロジェクト（hmi-platform）の全 PR。他リポジトリには波及させない。
