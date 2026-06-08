---
name: feedback-coderabbit-fallback
description: Codex の利用上限到達時は、代替レビュアー CodeRabbit のレビューを拾って Codex と同じ自走ループで対応する
metadata: 
  type: feedback
---

本プロジェクトのコードレビューは原則 **Codex GitHub App** が担当する（[CLAUDE.md](../../CLAUDE.md)「コードレビューの担当分け」）。ただし **Codex が利用上限（レート / クォータ）に達して沈黙した場合**、代わりに **CodeRabbit（GitHub App。2026-06-08 導入）** がレビューを返すことがある。その時は CodeRabbit のレビュー指摘も Codex と同様に拾って対応する。

**Why:** ユーザーが 2026-06-08 に「Codex 利用上限が来たら CodeRabbit からレビューが帰ってくるかもしれない。その時は対応してね」と明示指示した。Codex 上限で PR が止まると困るため、フォールバックのレビュアーを用意した。

**How to apply:**

- PR の自走ループ（[[feedback-codex-auto-loop]]）でレビュー待ちポーリング中、**Codex が上限等で返ってこない場合は CodeRabbit のレビューコメント（issue / inline / review オブジェクト）も検出対象に含める**。
- CodeRabbit の指摘も Codex 指摘と同じ扱いで自走対応する：修正コミット → push → 再レビュー依頼（CodeRabbit は `@coderabbitai review` コメントで明示再レビューを依頼できる）→ ループ。指摘 0 件のクリーンレビューまで繰り返してから完了報告する。
- どちらのレビュアーが応答しているかを確認し、**実際に返ってきた側の指摘に対応する**（Codex が生きていれば従来どおり Codex 優先、上限時のみ CodeRabbit にフォールバック）。
- 大規模な方針差し戻し指摘は、レビュアーに関わらず自走を中断してユーザーに相談する。

関連：[[feedback-codex-auto-loop]] / [[feedback-codex-review-comment]] / PR ワークフローは [CLAUDE.md](../../CLAUDE.md)「Codex 連携 / PR ワークフロー」
