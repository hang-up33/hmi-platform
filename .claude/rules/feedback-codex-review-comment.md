---
name: feedback-codex-review-comment
description: "PR 作成後・修正 push 後は毎回 `@codex review` コメントを明示的に投稿する"
metadata: 
  type: feedback
---

PR を `gh pr create` で作成した直後と、レビュー指摘修正を `git push` した直後の **両方** で、必ず `gh pr comment <N> --body "@codex review"` を実行して Codex に明示的なレビューを依頼する。

**Why:** Codex の自動レビューはトリガが「Open PR / Draft → Ready / `@codex review` コメント」の 3 種類だが、ユーザーは「毎回明示的に欲しい」と表明（2026-05-25）。自動レビューに頼ると、push の差分によっては Codex が再レビューを判断せず黙ることがあるため、push のたびに必ずコメントで合図を送って取りこぼしを防ぐ。

**How to apply:** [[codex-pr]] スキルの最後と、Codex 指摘修正の `git push` 後に追加で実行する。PR 作成時：
```sh
gh pr create ... # PR URL を取得
gh pr comment <PR番号> --body "@codex review"
```
修正 push 時：
```sh
git push
gh pr comment <PR番号> --body "@codex review"
```
適用対象は本プロジェクト（hmi-platform）の全 PR。他リポジトリには波及させない。
