PR 本文・PR タイトル・コミットメッセージなど、Claude が作成する文章には**絵文字を含めない**。

- 見出しの ✅ ⚠️ 🎉 のような装飾絵文字はもちろん、Attribution 行の絵文字（「🤖 Generated with [Claude Code](https://claude.com/claude-code)」の 🤖）も対象。Attribution の文言自体（`Generated with [Claude Code](https://claude.com/claude-code)`・コミットの `Co-Authored-By:` 行）は残し、絵文字だけを外す。
- CodeRabbit / Codex など外部ツールが自動投稿するコメント内の絵文字（例：CodeRabbit summary の絵文字見出し）は Claude が書いたものではないため対象外。

**Why:** ユーザーが 2026-09-20 に「PR に絵文字を今後含めないようにしてください」と明示指示した。

**How to apply:** `gh pr create` / `gh pr comment` / commit メッセージを書く前に、本文に絵文字が無いか確認する。[codex-pr](../skills/codex-pr/SKILL.md) スキルで PR 本文を組み立てる際もこのルールを適用する。

関連：[[feedback-codex-review-comment]] / PR ワークフローは [CLAUDE.md](../../CLAUDE.md)「Codex 連携 / PR ワークフロー」
