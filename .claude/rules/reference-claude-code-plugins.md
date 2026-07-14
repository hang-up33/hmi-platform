---
name: reference-claude-code-plugins
description: 公式マーケットプレイス claude-plugins-official から導入した4プラグイン（clangd-lsp / qt-development-skills / skill-creator / claude-md-management）と導入理由・期待効果
metadata:
  type: reference
---

`.claude/settings.json` の `enabledPlugins` に、公式マーケットプレイス `claude-plugins-official`（`~/.claude/plugins/marketplaces/claude-plugins-official`）から以下4つを有効化（2026-07-14）：

| プラグイン | 導入理由 | 期待効果 |
|---|---|---|
| `clangd-lsp` | 本リポジトリは Qt6 C++/QML 中心。C/C++ 言語サーバで定義ジャンプ・参照検索・補完を得る | Shared/Schema・Shared/Widgets 等の C++ 横断編集が速くなる |
| `qt-development-skills`（Qt Group 公式） | Qt C++/QML 特化のコーディング/ドキュメント支援 skill | QML Widget 追加時のコーディング品質向上。**付属のコードレビュー機能は使わない**（レビューは Codex 専任というプロジェクト方針 [CLAUDE.md](../../CLAUDE.md)「コードレビューの担当分け」と衝突するため） |
| `skill-creator` | 本プロジェクトは `.claude/skills/` に自作 skill を多数蓄積・育成する文化がある | 新規 skill 作成・既存 skill（mvp-next-task, codex-pr 等）の改善・評価を支援 |
| `claude-md-management` | CLAUDE.md の品質監査・肥大化防止は既存ルール（[[feedback-phase-status-sync]] 等）で手動運用中 | [kaizen-close](../skills/kaizen-close/SKILL.md) 運用の補完（監査の抜け漏れ検出） |

**Why:** ユーザーが 2026-07-14 に4つの導入を明示指示。効果測定のため「何を入れて何が改善したか」を記録する運用にした。

**How to apply:**
- `clangd-lsp` / `skill-creator` / `claude-md-management` はマーケットプレイスの clone 内（`plugins/<name>/`）に実体がありローカルで即使える。**`qt-development-skills` は外部リポジトリ（`github.com/TheQtCompanyRnD/agent-skills.git`）参照のため、settings.json 編集だけでは fetch されない可能性がある**。次回 Claude Code 起動時に自動同期（`Syncing installed_plugins.json with enabledPlugins from all settings.json files`）で解決しなければ、`/plugin install qt-development-skills@claude-plugins-official` を手動実行する。
- 導入後、実際に使ってみて効果があった/なかった項目があれば、この表の「期待効果」を実績に更新する（体感が伴わなければ `enabledPlugins` から外すことも検討）。
- `qt-development-skills` のコードレビュー系 skill が誤って呼ばれた場合は使用を控え、Codex レビューに一本化する。

関連：[[feedback-plan-docs-consistency]] / [CLAUDE.md](../../CLAUDE.md)「コードレビューの担当分け」
