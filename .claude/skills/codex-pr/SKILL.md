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
Task N: <何を変えたか（40 字前後まで）>

<なぜ変えたか。1〜3 行。件名で十分なら省略>

<セッションの attribution 指示にある Co-Authored-By 行>
EOF
)"
```

- `git add .` や `git add -A` は使わない（意図しないファイル混入防止）
- レビュー対応の修正コミットは `fix: <何を直したか>` とし、件名に `(Codex 指摘)` を付けない（[user-writing-readability](../../rules/user-writing-readability.md)）

### 4. push

```sh
git push -u origin task/<N>-<短い名>
```

### 5. PR 作成

**HEREDOC は必ず `'EOF'`（quoted）で書き、本文中のシェル展開を完全に止める**。可変値を本文へ差し込む場合はプレースホルダで書いておき、後で `sed` 置換 → `--body-file` で渡す（PR 本文に `$VAR` / `$(...)` / バッククォートが混ざっても安全な構成）。

```sh
# 本文テンプレートをファイルに書き出す（HEREDOC 内は完全リテラル）
cat <<'EOF' > /tmp/pr_body.md
## 何を・なぜ
<2〜3 行。最初の 1 行で目的が分かるように>

## 変更点
- <変更の単位で 1 行ずつ。5 個まで>

## スクショ
<!-- GUI 変化があるときだけ。private リポジトリなので raw.githubusercontent.com は 404。
     Docs/screenshots/task-<N>-<短い名>.png を PR 説明欄にドラッグ&ドロップしてもらう（screenshot-capture スキル） -->
撮影済み: `Docs/screenshots/task-<N>-<短い名>.png`

## 確認したこと
- <`cmake --build` / `ctest` の結果、手動確認>

## レビューで見てほしい点
- <1〜3 個。なければ節ごと消す>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF

# --body-file で渡す（--body "$(...)" は使わない）
gh pr create --title "Task N: <短い説明>" --body-file /tmp/pr_body.md
```

- `--draft` を **付けない**（Codex がレビュー対象として扱いやすい状態にする）
- 文の書き方は [user-writing-readability](../../rules/user-writing-readability.md) に従う（1 文 1 事項、括弧の入れ子禁止）
- 不安な観点があれば `レビューで見てほしい点` を具体的に書く（汎用的な「全体的に見てほしい」より、特定の観点を 1〜3 個提示）
- `## スクショ` セクションは **GUI 変化があるタスクで必須**（純粋な Schema / docs / CMake のみのタスクは省略可）。撮影方法と運用の詳細は [screenshot-capture](../screenshot-capture/SKILL.md) スキルを参照。**本リポジトリは private のため `raw.githubusercontent.com` の URL は PR 本文で 404 になる**。インライン表示は user-attachments（PR 説明欄へ画像をドラッグ&ドロップ）でのみ可能で、これは Claude では自動化できない手動ステップ → PR 作成時はプレースホルダを置き、ユーザーにドラッグ&ドロップを依頼する（[screenshot-capture](../screenshot-capture/SKILL.md) スキル「ファイル配置と PR への埋め込み」）。
- **`gh pr create --body "$(cat <<EOF ... EOF)"` で unquoted HEREDOC を使うのは禁止**。本文中の `$VAR` / `$(...)` / バッククォートが全てシェルに展開されて意図しないコマンド実行・本文破壊を招く。可変値は必ずプレースホルダ + 後置換で扱う。

### 6. `@codex review` を 1 回だけ投稿する

`gh pr create` の直後に 1 回だけ投稿する。修正 push 後は投稿しない（[feedback-review-convergence](../../rules/feedback-review-convergence.md)）。

```sh
HEAD_SHA=$(git rev-parse HEAD)
SINCE=$(date -u +%Y-%m-%dT%H:%M:%SZ)     # 投稿の直前に採る
gh pr comment <PR番号> --body "@codex review"
```

- `HEAD_SHA` と `SINCE` は、必ず投稿の直前に採る。投稿の後に採ると、その間に届いた Codex の返信が `?since=` で除外され、届いているのに「返事がない」と誤判定する。
- 自動レビューだけに頼らず、コメントで明示的に依頼する。自動レビューは差分によって黙ることがある。
- 同じ HEAD に 2 回依頼しない。レビューが二重に走り、枠を余分に使う。

### 7. レビューを待ち受けて直す

`gh pr create` の直後に完了報告して放置するのは禁止。ユーザーの指示を待たず、次の手順を 1 回だけ行う。

1. **待機**：`sleep 180`〜`sleep 240`。Codex は通常 1〜5 分で返す。30 分返らなければユーザーに報告する。
2. **取得**：3 種類すべてを取る（Codex は指摘の有無で投稿先 API が変わる）。`SINCE` と `HEAD_SHA` は手順 6 で採った値を使う。
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
   #    拾うと、最新 HEAD のレビューが未完了でも完了と誤判定する。
   gh api --paginate "repos/<owner>/<repo>/issues/<N>/comments?since=${SINCE}" \
     --jq '.[] | select(.user.login == "chatgpt-codex-connector[bot]") | {created_at, body}'
   ```
3. **判定**：当該 HEAD の指摘を重要度で分ける。P0〜P3 の読み替えと格下げの条件は [feedback-review-convergence](../../rules/feedback-review-convergence.md) に従う。
   - Blocker / Major（`[Blocker]` / `[Major]` / P0〜P2）がある → 手順 4 へ。`state` が `CHANGES_REQUESTED` でも、中身が Minor 相当なら理由を返信して次の分岐へ進む。
   - `[Minor]` / `[Nit]` / `[Future]` / P3 だけ → すぐ直せるものだけ直して手順 5 へ。`[Future]` は計画書の未決事項に追記する。
   - `Didn't find any major issues` などクリーンの文言 → 手順 6 へ。
   - まだ何も届いていない → 手順 1 に戻って待つ。
4. **修正**：該当箇所を直す。同じ種類の問題をほかの箇所でも `grep` で探して一緒に直す。コード変更なら `cmake --build` と `ctest` を通す。修正したファイルを明示して `git add` し、`fix: <何を直したか>` でコミットする。
5. **push と確認**：`git push` する（force-push はしない）。修正の差分をサブエージェントに読み取り専用で確認させ、出た指摘を直す（[feedback-subagent-review](../../rules/feedback-subagent-review.md)）。`@codex review` の再依頼はしない。
6. **完了報告**：手順 8 へ。

待機中の中間報告は不要。次の場合だけ、途中でユーザーに相談する。

- 方針そのものを差し戻す指摘（タスク分割のやり直し、設計書にないフレームワークの導入など）
- 修正が設計の変更になる（直す前に相談する）
- ビルドが通らない、テストが赤いまま直らない
- 30 分待っても Codex が返らない（GitHub App の障害などの可能性）

ユーザーが再レビューを頼んだときだけ、手順 6 からもう一度行う。

### 8. 完了報告

PR の URL と、直した指摘・残した指摘を報告する。指摘がなかった場合もそう書く（例：「Major 2 件を修正、Minor 1 件は残した」）。

マージはユーザーが行う（Claude はマージしない）。

## やってはいけないこと（Must Never）

- `main` に直接 push / コミットする
- PR を draft で作る（Codex のレビュー開始が遅れる）
- PR を Claude 側でマージする（マージはユーザーの責任）
- `git add .` / `git add -A` で広く取り込む
- 既にレビュー中の PR を勝手に force-push して履歴を書き換える（追加コミットで対応する）
- ユーザーに頼まれていないのに `@codex review` を再投稿する

## 過去の PR に新しい指摘が付いたら

マージ待ちの PR に、あとから新しい指摘が付いた場合の手順。

1. 指摘を取得する。`gh pr view <番号> --comments` と `gh api repos/.../pulls/<N>/comments` で inline コメントも取る。PR に無く ChatGPT の画面にしか出ていない場合だけ、ユーザーに貼ってもらう。
2. 当該ブランチに `git checkout` する。
3. 手順 7 の 3〜5（判定・修正・push と確認）を行う。再依頼はしない。
4. 手順 8 の完了報告をする。
