---
name: feedback-codex-auto-loop
description: PR 作成後は Codex のレビューを自走で待ち受け、Blocker / Major を直して push する（再依頼はしない）
metadata: 
  type: feedback
---

PR 作成 + `@codex review` 投稿の後は、ユーザーからの追加指示を待たず、Codex のレビュー結果を Claude 側で能動的にポーリングし、指摘が返ってきたら自走で修正コミット → push する。Blocker / Major を直して push し、サブエージェントで確認したら完了報告する。依頼は 1 PR につき 1 回で、修正後に再依頼しない。詳細は [[feedback-review-convergence]] に従う。

**Why:** Task 7（PR #14）でこの自走を実演したところ、ユーザーが「いいね、これを次から標準にして」と明示承認した。Codex の指摘 1 件ごとに「指摘修正して」とユーザーが叩く必要がない方が速く回せるし、ユーザーは寝てる間 / 別作業中でも PR が green まで進む。

**How to apply:** PR ワークフロー（[CLAUDE.md](../../CLAUDE.md)「Codex 連携 / PR ワークフロー」）/ [[feedback-codex-review-comment]] と組み合わせて、`codex-pr` スキル実行時に：

1. `gh pr create` 直後に `gh pr comment <N> --body "@codex review"` を投げる
2. **バックグラウンドポーリング**で Codex のレビュー到着を待つ。`sleep 180s` の一括待機より、30 秒間隔の polling のほうが反応が速く、レート制限にも当たらない（GitHub API 認証済み = 5000 req/h）。`run_in_background: true` で Bash に投げて、`task-notification` で完了を受ける：

   ```sh
   LAST_ISSUE=$(gh api repos/hang-up33/hmi-platform/issues/<N>/comments --jq 'sort_by(.created_at) | last | .created_at')
   LAST_INLINE=$(gh api repos/hang-up33/hmi-platform/pulls/<N>/comments --jq 'sort_by(.created_at) | last | .created_at // ""')
   for i in $(seq 1 20); do
     sleep 30
     NEW_ISSUE=$(gh api repos/hang-up33/hmi-platform/issues/<N>/comments --jq 'sort_by(.created_at) | last | .created_at')
     NEW_INLINE=$(gh api repos/hang-up33/hmi-platform/pulls/<N>/comments --jq 'sort_by(.created_at) | last | .created_at // ""')
     if [ "$NEW_ISSUE" != "$LAST_ISSUE" ] || [ "$NEW_INLINE" != "$LAST_INLINE" ]; then
       echo "新規コメント検出"; break
     fi
   done
   ```

3. レビュー検出後、`gh api repos/<owner>/<repo>/pulls/<N>/comments` で inline 指摘、`gh api repos/<owner>/<repo>/issues/<N>/comments` で全体コメントを取得
4. Blocker / Major あり → 修正 → ビルドと `ctest`（コード変更時）→ push → サブエージェントに修正を確認させて完了報告。再依頼はしない（[[feedback-review-convergence]]）
5. 指摘なし（"Codex Review: Didn't find any major issues"）、または Minor / Nit だけ → ループ脱出、ユーザーに完了報告（[[feedback-review-convergence]]）

> **取りこぼし注意（実体験：PR #62）**：**指摘 0 件のクリーンレビュー「Didn't find any major issues」は issue コメント（`issues/<N>/comments`）として来る**。一方、指摘がある回は inline コメント（`pulls/<N>/comments`）＋ review オブジェクト（`pulls/<N>/reviews`、`state=COMMENTED`）として来る。**よって検出は必ず issue コメントを主対象に含める**（上記スクリプトの `LAST_ISSUE` が要）。`pulls/<N>/reviews` ＋ inline だけをポーリングすると、クリーン回は review オブジェクトが増えないため**永久に検出できず空振りタイムアウトする**（PR #62 で実際に踏んだ。クリーンは出ていたのに 20 分空振りした）。**上記スクリプトを勝手に簡略化・改変しない**（reviews だけにしない・issue コメント監視を外さない）こと。

ループ中はユーザーに途中報告は不要（待機 + 修正コミットを淡々と進める）。クリティカルな設計判断が要る指摘（大規模な方針差し戻し）に当たった場合だけ、自走を中断してユーザーに相談する。

ポーリングのタイムアウト目安：30 秒 × 20 回（10 分）で返らない場合だけユーザーへ状況報告して指示を仰ぐ（Codex は通常 3〜10 分で返る。docs PR や小修正なら 5 分以内）。

最終的にマージするかどうかは従来通り PR ワークフロー（[CLAUDE.md](../../CLAUDE.md)「マージ戦略」）に従いユーザーの責務（Claude 側でマージはしない）。
