---
name: Phase status sync
description: タスク完了・フェーズ進行時は、進捗ステータスが書かれた全常駐文書（CLAUDE.md / README / plan 進捗表 / mvp-task-runner / development-history）を同期する
metadata:
  type: feedback
---

> **🔴 最優先（2026-06-10 ユーザー明示）：「次回から反映を絶対に忘れない。ユーザーは基本 README を見る」。** README はユーザーが最初に・主に見る面なので、**タスク完了・フェーズ進行・フェーズ承認のたびに README の進捗（冒頭散文 + フェーズ別の表）を必ず同期する**。「次のタスクで」「実装着手時に」と先送りしない（計画 PR でも実装 PR でも、その PR でステータスが動くなら同コミットで反映）。**完了報告の前に「README は最新か？」を必ず自問する。**

タスク完了・フェーズ進行・フェーズ承認のたびに、**進捗ステータスを記載している文書をすべて同期する**。進捗の**正本は `Docs/phase*-plan.md` の「進捗」表**とし、他の文書は「短いステータス + 正本へのポインタ」に留める。

> **🔴 CLAUDE.md / README を再肥大化させない**（2026-06-12 ユーザー明示「今回だけでなく今後も」）：
>
> - CLAUDE.md「現在のフェーズ」と Must Always 先頭、README 冒頭散文は **スナップショット（今どこ / 直近完了 / 次タスク + ポインタ）だけ**にする。
> - **完了タスクの詳細・PR・経緯・学びを段落へ追記しない**。タスクを終えるたびに「現在のフェーズ」へ説明文を足す運用は禁止 ＝ **前タスクの記述を新タスクのスナップショットへ置き換える**（積み増さない）。
> - 完了タスクの詳細は [development-history.md](../../Docs/development-history.md) にだけ書く。
> - CLAUDE.md 本体は **< 200 行（理想 80〜120 行）・流し見できる箇条書き**を保つ（公式 [memory](https://code.claude.com/docs/en/memory) / [best-practices](https://code.claude.com/docs/en/best-practices) 準拠。2026-06-12 に経緯の壁を圧縮済み）。

**同期対象（進捗ステータスが書かれている場所）：**

| 文書 | 箇所 |
|---|---|
| `Docs/phase*-plan.md`（完了後は `Docs/archive/` へ移す） | 「進捗」表（**正本**） |
| README.md | 「フェーズ進捗」冒頭の散文 + フェーズ別の表 |
| CLAUDE.md | 「現在のフェーズ」段落 + 「Must Always」先頭バレット |
| AGENTS.md | 対象外。スコープ節は phase-status.md へのリンクだけで、進捗は書かない |
| `.claude/agents/mvp-task-runner.md` | 「タスク順（厳守）」リスト |
| `Docs/development-history.md` | フェーズ見出しの状態表記・エントリ |

**Why:** Phase 4 拡張（Task 33〜43）の進行中、各タスク PR では plan 進捗表と README 表だけが更新され、CLAUDE.md「現在のフェーズ」・AGENTS.md・mvp-task-runner が **11 タスク分 stale**（「未着手・次タスクは Task 33」のまま Task 43 まで完了）になった（2026-06-09 整合性レビューで発覚・一括修正）。常駐文書が古いと、次セッションが「次は Task 33」と誤認して**完了済みタスクを再実装するリスク**が直撃する。development-history も Phase 3-B 見出しが「進行中 — Task 22 完了」のまま Task 23/24 エントリと矛盾していた。

**How to apply:**

- タスク完了報告（kaizen-close）の直前に「このタスクで**フェーズの進捗状態**は変わったか？変わったなら上表の全箇所を grep で総ざらいしたか？」を自問する。検索キーワード：`未着手` / `進行中` / `次タスク` / `Task <N>` / 旧フェーズ名。
- 特に **フェーズの開始・完了・承認** はステータスが大きく動くので必ず全文書を確認する（[[feedback-plan-docs-consistency]] 項目 6 のフェーズ再スコープ総ざらいと同じ要領）。
- 二重メンテを減らすため、常駐文書に詳細な進捗を書き足さない：**詳細は正本（plan 進捗表）に書き、他文書は 1〜2 文 + リンク**で済ませる。
- リモート / 別マシンのセッションでは作業前に `git fetch` → `git log --oneline origin/main` で実進捗を確認し、文書の記述を鵜呑みにしない（[dev-environment.md](dev-environment.md)「リポジトリ運用の注意」）。
- **フェーズの承認・着手でステータスが動くなら、たとえ「計画書のみ」の PR でも常駐文書（README / CLAUDE.md / mvp-task-runner / development-history）を同じ PR で同期する。「同期は実装着手時（次タスク）に」と先送りしない**（2026-06-10 実証：Phase 5 plan 起票 PR #95 で「plan のみ・同期は Task 47 で」と先送りしたところ、`origin/main` の README 進捗表が前フェーズ〔Task 44〜45 = #94〕分も含めて stale なままで「task 完了みたいなのに README 更新されてない」とユーザー指摘。さらに #94〔実装 PR〕自身も README 進捗表に Task 44/45 を入れ忘れており、同期漏れが 1 フェーズ分累積していた）。**実装 PR / 計画 PR を問わず、その PR でステータスが進むなら常駐文書同期を同コミット内で完了させる**のが原則。

関連：[[feedback-plan-docs-consistency]] / [[feedback-continuous-improvement]]
