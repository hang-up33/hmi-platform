---
name: Phase status sync
description: タスク完了・フェーズ進行時は、進捗ステータスが書かれた全常駐文書（CLAUDE.md / AGENTS.md / README / plan 進捗表 / mvp-task-runner / development-history）を同期する
metadata:
  type: feedback
---

タスク完了・フェーズ進行・フェーズ承認のたびに、**進捗ステータスを記載している文書をすべて同期する**。進捗の**正本は `Docs/phase*-plan.md` の「進捗」表**とし、他の文書は「短いステータス + 正本へのポインタ」に留める。

**同期対象（進捗ステータスが書かれている場所）：**

| 文書 | 箇所 |
|---|---|
| `Docs/phase*-plan.md` | 「進捗」表（**正本**） |
| README.md | 「フェーズ進捗」冒頭の散文 + フェーズ別の表 |
| CLAUDE.md | 「現在のフェーズ」段落 + 「Must Always」先頭バレット |
| AGENTS.md | 「スコープ」節 |
| `.claude/agents/mvp-task-runner.md` | 「タスク順（厳守）」リスト |
| `Docs/development-history.md` | フェーズ見出しの状態表記・エントリ |

**Why:** Phase 4 拡張（Task 33〜43）の進行中、各タスク PR では plan 進捗表と README 表だけが更新され、CLAUDE.md「現在のフェーズ」・AGENTS.md・mvp-task-runner が **11 タスク分 stale**（「未着手・次タスクは Task 33」のまま Task 43 まで完了）になった（2026-06-09 整合性レビューで発覚・一括修正）。常駐文書が古いと、次セッションが「次は Task 33」と誤認して**完了済みタスクを再実装するリスク**が直撃する。development-history も Phase 3-B 見出しが「進行中 — Task 22 完了」のまま Task 23/24 エントリと矛盾していた。

**How to apply:**

- タスク完了報告（kaizen-close）の直前に「このタスクで**フェーズの進捗状態**は変わったか？変わったなら上表の全箇所を grep で総ざらいしたか？」を自問する。検索キーワード：`未着手` / `進行中` / `次タスク` / `Task <N>` / 旧フェーズ名。
- 特に **フェーズの開始・完了・承認** はステータスが大きく動くので必ず全文書を確認する（[[feedback-plan-docs-consistency]] 項目 6 のフェーズ再スコープ総ざらいと同じ要領）。
- 二重メンテを減らすため、常駐文書に詳細な進捗を書き足さない：**詳細は正本（plan 進捗表）に書き、他文書は 1〜2 文 + リンク**で済ませる。
- リモート / 別マシンのセッションでは作業前に `git fetch` → `git log --oneline origin/main` で実進捗を確認し、文書の記述を鵜呑みにしない（[dev-environment.md](dev-environment.md)「リポジトリ運用の注意」）。

関連：[[feedback-plan-docs-consistency]] / [[feedback-continuous-improvement]]
