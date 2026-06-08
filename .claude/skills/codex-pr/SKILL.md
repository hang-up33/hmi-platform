---
name: codex-pr
description: タスク完了時に Codex GitHub App によるレビューを前提とした PR を作成する標準ワークフロー。ブランチ作成 → コミット → push → gh pr create までを規約に沿って実施する。
origin: hmi-platform
---

# Codex 向け PR 作成ワークフロー

本プロジェクトのコードレビューは **Codex GitHub App** が担当する。本スキルはフェーズタスク（MVP / Phase 2 / Phase 3-A / Phase 3-B …）完了時に Codex がすぐレビューを開始できる形で PR を作る標準手順。

## 適用タイミング（When to Use）

- フェーズタスクの実装・ビルド検証・README 進捗反映・kaizen-close が完了し、PR にする段階
- ドキュメント・設定変更のみの場合は `task/<N>-...` ではなく `docs/<短い名>` ブランチで PR を作る運用も可（[CLAUDE.md](../../../CLAUDE.md)「ブランチ命名」節）
- 既存 PR への追加コミットではなく、**新規 PR を作る** とき

## 前提

- **ChatGPT Codex（Web 版）** を使用。chatgpt.com の Codex → Settings から `hang-up33/hmi-platform` を GitHub OAuth 連携済み（GitHub の Installed Apps 一覧には "ChatGPT" / "OpenAI Codex" などの名前で出現する。マーケットプレイス検索ではヒットしない）
- Codex 側の自動レビュー設定が有効で、`ready-for-review` で PR を push すれば手動操作なしに Codex が PR コメントでレビューを返す
- `gh` CLI で認証済み（`gh auth status` で確認）
- リモート `origin` が GitHub の本リポジトリを指していること

レビューは Claude が PR を `ready-for-review` で push した時点で **Codex が自動でレビューコメントを PR に投稿** する（Codex 側の自動レビュー設定が有効）。Claude 側は **PR をきれいに作るところまで** が責任範囲。ユーザーが Codex に URL を貼る手動操作は不要。

## 規約

| 項目 | 値 |
|---|---|
| ブランチ名 | `task/<N>-<短い名>`（例：`task/2-canvas`） |
| PR タイトル | `Task N: <短い説明>` |
| PR 状態 | **ready-for-review**（draft にしない — Codex に即レビューさせるため） |
| マージ戦略 | Squash and merge（Claude はマージしない、ユーザーが行う） |

## 手順（How It Works）

### 1. 現在ブランチ確認

```sh
git branch --show-current
```

- `main` 上にいる場合、または別の `task/...` ブランチにいる場合は、新ブランチに切り替えが必要
- 既に該当 `task/<N>-...` ブランチにいるならスキップ

### 2. ブランチ作成（未作成なら）

```sh
git checkout main
git pull --ff-only
git checkout -b task/<N>-<短い名>
```

### 3. コミット

```sh
git add <変更ファイルを明示的に列挙>
git commit -m "$(cat <<'EOF'
Task N: <短い説明>

<本文：何を、なぜ、どこに影響するか。1〜3 段落>

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

- `git add .` や `git add -A` は使わない（意図しないファイル混入防止）

### 4. push

```sh
git push -u origin task/<N>-<短い名>
```

### 5. PR 作成

**HEREDOC は必ず `'EOF'`（quoted）で書き、本文中のシェル展開を完全に止める**。可変値を本文へ差し込む場合はプレースホルダで書いておき、後で `sed` 置換 → `--body-file` で渡す（PR 本文に `$VAR` / `$(...)` / バッククォートが混ざっても安全な構成）。

```sh
# 本文テンプレートをファイルに書き出す（HEREDOC 内は完全リテラル）
cat <<'EOF' > /tmp/pr_body.md
## Summary
- <変更点の箇条書き 1>
- <変更点の箇条書き 2>

## Screenshot
<!-- private リポジトリのため raw.githubusercontent.com は 404 になる。インライン表示は user-attachments のみ。
     ↓ Docs/screenshots/task-<N>-<短い名>.png を PR 説明欄にドラッグ&ドロップしてインライン化する（詳細は screenshot-capture スキル） -->
撮影済み（コミット済み）: `Docs/screenshots/task-<N>-<短い名>.png`

## 設計書との対応
- Task N: <タスク名>（該当フェーズ：MVP / Phase 2 / Phase 3-A / Phase 3-B …）
- 完了基準: <ビルド成功・動作確認内容>

## Test plan
- [ ] `cmake --build build` 成功
- [ ] <UI 確認手順がある場合はそれ>
- [ ] README の進捗表が ✅ に更新されている

## Codex 向け補足
<重点的に見てほしい観点があれば箇条書きで。例：>
- Shared/Schema の API 設計が将来の Task M で破綻しないか
- QML の <X> がパフォーマンス的に問題ないか

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF

# --body-file で渡す（--body "$(...)" は使わない）
gh pr create --title "Task N: <短い説明>" --body-file /tmp/pr_body.md
```

- `--draft` を **付けない**（Codex がレビュー対象として扱いやすい状態にする）
- 不安な観点があれば `Codex 向け補足` セクションを具体的に書く（汎用的な「全体的に見てほしい」より、特定の観点を 1〜3 個提示）
- `## Screenshot` セクションは **GUI 変化があるタスクで必須**（純粋な Schema / docs / CMake のみのタスクは省略可）。撮影方法と運用の詳細は [screenshot-capture](../screenshot-capture/SKILL.md) スキルを参照。**本リポジトリは private のため `raw.githubusercontent.com` の URL は PR 本文で 404 になる**。インライン表示は user-attachments（PR 説明欄へ画像をドラッグ&ドロップ）でのみ可能で、これは Claude では自動化できない手動ステップ → PR 作成時はプレースホルダを置き、ユーザーにドラッグ&ドロップを依頼する（[screenshot-capture](../screenshot-capture/SKILL.md) スキル「ファイル配置と PR への埋め込み」）。
- **`gh pr create --body "$(cat <<EOF ... EOF)"` で unquoted HEREDOC を使うのは禁止**。本文中の `$VAR` / `$(...)` / バッククォートが全てシェルに展開されて意図しないコマンド実行・本文破壊を招く。可変値は必ずプレースホルダ + 後置換で扱う。

### 6. `@codex review` コメントで明示的にレビュー依頼

`gh pr create` 直後と、Codex 指摘修正の `git push` 直後の **両方** で必ず実行：

```sh
gh pr comment <PR番号> --body "@codex review"
```

- Codex の自動レビュートリガ（Open / Ready / `@codex review` コメント）のうち、最後のコメント方式を毎回明示的に発火させる。
- 自動レビューに任せると、push の差分内容によっては Codex が再レビューを判断せず黙ることがあるため、push のたびに必ずコメントを入れて取りこぼしを防ぐ。

### 7. Codex レビュー自走ループ（指摘 0 件まで自走で繰り返す）

**`gh pr create` 直後に完了報告して放置するのは禁止**。ユーザーから「Codex 指摘を修正して」と再指示を待たず、Claude 側が自走で Codex のレビュー結果をポーリングし、指摘があれば修正コミット → push → `@codex review` 再依頼 を繰り返す。

**ループ前の確定（毎ラウンド必須）**：直前の `git push` と `gh pr comment <N> --body "@codex review"` を **投稿し終えた直後** に、以降のラウンド全体で使う基準時刻を確定する：

```sh
SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)   # 例: 2026-05-25T04:20:00Z
HEAD_SHA=$(git rev-parse HEAD)
```

`SINCE` を待機後（手順 2 内）に取得すると、待機中に Codex が投稿したクリーン文言を `?since=` で除外してしまい「シグナルなし」と誤判定して 30 分無反応扱いになる。**必ず待機の前に確定**する。

ループ手順：

1. **待機**：`sleep 180`〜`sleep 240`（Codex は通常 1〜5 分でレビューを返す）
2. **取得**：3 種類すべてを取る（Codex は指摘の有無で投稿先 API が変わる）。`SINCE` と `HEAD_SHA` はループ前に確定した値を使う。
   ```sh
   # 1) reviews API：指摘ありの review summary が来る（state / 本文）。commit_id で絞る
   gh api --paginate repos/<owner>/<repo>/pulls/<N>/reviews \
     --jq '.[] | select(.commit_id == "<HEAD-SHA>") | {state, body}'
   # 2) review comments API：inline コメント本体（指摘の中身）。
   #    **必ず original_commit_id で絞る（commit_id ではない）**。inline コメントの
   #    `commit_id` は、指摘行が新コミットでも存在し続けると GitHub に **最新 HEAD へ
   #    re-anchor（付け替え）される**ため、commit_id で絞ると前ラウンドの古い指摘が
   #    新 HEAD のものとして再マッチし「同じ指摘がまた来た」と誤検出する（PR #52 で実害）。
   #    `original_commit_id` は投稿時コミット固定なので、当該 HEAD への **新規** inline
   #    だけを正しく拾える。created_at >= SINCE の併用でさらに堅い。
   gh api --paginate repos/<owner>/<repo>/pulls/<N>/comments \
     --jq '.[] | select(.original_commit_id == "<HEAD-SHA>") | {path, line, body}'
   # 3) issue comments API：PR 会話タブのコメント。Codex は **指摘なしのときここに
   #    "Didn't find any major issues" を投稿する** ことが多く、reviews API に
   #    クリーン文言が載らないラウンドがあるため必ず併せて見る。
   #    **commit_id を持たないので必ず時刻で絞る**。過去ラウンドのクリーン文言を
   #    拾うと、最新 HEAD のレビューが未完了でもループを誤終了する。
   gh api --paginate "repos/<owner>/<repo>/issues/<N>/comments?since=${SINCE}" \
     --jq '.[] | select(.user.login == "chatgpt-codex-connector[bot]") | {created_at, body}'
   ```
   - `--paginate` を必ず付ける：gh api の per_page 既定値は 30 で、指摘が多い PR では先頭ページ以外を取りこぼし「指摘なし」と誤判定してループが早期終了する恐れがある
   - issue comments の `?since=...` は `updated_at >= since` のフィルタとして GitHub 側で適用される。`--jq 'select(.created_at >= "<SINCE>")'` で同等のクライアント側絞り込みも可（両方付けて二重防御するのが堅い）
   - 全文長い場合は `--jq '.[] | "[\(.path):\(.line)]\n\(.body)\n---"'` 等で整形
   - 件数だけ確認したいときも `gh api --paginate ... --jq 'length'` ではなく `... | wc -l` 等で全ページ通算する（`--jq 'length'` はページ単位の長さを各ページごとに出力する点に注意）
3. **判定**：以下を **state 優先** で評価する。「badge / 文言の有無」だけで判断すると、本文に badge が付かない `CHANGES_REQUESTED` を取りこぼしてループが早期終了する。
   - reviews API の `state` が `CHANGES_REQUESTED` → **必ず** 修正フロー (4) へ。badge や文言は見ない
   - `state` が `COMMENTED` でも review comments（inline）が当該 HEAD-SHA で 1 件以上ある → 修正フロー (4) へ
   - inline 0 件で、reviews 本文 / inline 本文に P0〜P3 / Major / Minor / `[Major]` / `[Minor]` 等の指摘 badge が含まれる → 修正フロー (4) へ
   - 上のいずれにも該当せず、かつ Codex が当該 HEAD 以降に issue comments / reviews のどちらかへ `"Didn't find any major issues"` 等のクリーン文言を投稿 → ループ脱出して完了報告
   - **どのシグナルも出ていない**（reviews も inline も issue comment もまだ無い）→ Codex がまだレビュー中。手順 1 の待機に戻る（ループは脱出しない）
4. **修正**：該当箇所を編集 → `cmake --build build` 成功確認 → 修正ファイルを明示的に `git add` → コミット
5. **push**：`git push`（force-push は基本しない、追加コミットで対応）
6. **再依頼**：`gh pr comment <N> --body "@codex review"`
7. **「ループ前の確定」に戻る** — `SINCE` と `HEAD_SHA` を **必ず再取得** してから手順 1 の待機へ。再取得しないと旧ラウンドの値で判定して誤動作する

ループ中の中間報告は不要（ユーザーは「次のレビュー結果が来るまでに何度修正したか」を後で PR の commit 履歴で確認できる）。

**自走を中断してユーザーに相談すべき例外**：

- 大規模な方針差し戻し（タスク分割を要求される、設計書外のフレームワーク導入を提案される 等）
- Codex が同じ指摘を 3 回連続で返してくる（修正が指摘の意図に合っていない可能性）
- ビルドが通らない / テストが赤いまま固着する
- 30 分待っても Codex が無反応（GitHub App 障害等の可能性 → ユーザー報告）

### 8. PR URL を完了報告に含める

クリーンレビュー到達後、`gh pr create` の戻り値の URL とともに、何ラウンドで収束したかをユーザーへの完了報告に含める（例：「Codex 指摘 2 件を 2 ラウンドで解消、最終レビュー：指摘なし」）。

マージは従来通りユーザーが行う（Claude はマージしない）。

## やってはいけないこと（Must Never）

- `main` に直接 push / コミットする
- PR を draft で作る（Codex のレビュー開始が遅れる）
- PR を Claude 側でマージする（マージはユーザーの責任）
- `git add .` / `git add -A` で広く取り込む
- 既にレビュー中の PR を勝手に force-push して履歴を書き換える（追加コミットで対応する）

## Codex の指摘が付いたら（自走ループ運用）

新規 PR の流れでは **手順 7 の自走ループ** がそのまま指摘修正を処理する。ユーザーから「Codex の指摘を修正して」と指示が来るのを待たない（Task 7 / PR #14 で承認された運用）。

**過去 PR への追加レビュー対応**（既にユーザーがマージ判断保留中の PR に新しい指摘が付いた場合のみ）：

1. 指摘内容を取得：
   - 基本は `gh pr view <番号> --comments` + `gh api repos/.../pulls/<N>/comments` で inline コメントも取る
   - PR コメントに無く ChatGPT の chat 画面にしか出ていない場合のみ、ユーザーから貼ってもらう
2. 当該ブランチに `git checkout`
3. 指摘ごとに修正コミットを追加 → `git push`（force-push は基本しない）
4. 手順 7 のループに再合流（`@codex review` 再依頼 → 待機 → 判定）
