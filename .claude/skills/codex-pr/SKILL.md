---
name: codex-pr
description: タスク完了時に Codex GitHub App によるレビューを前提とした PR を作成する標準ワークフロー。ブランチ作成 → コミット → push → gh pr create までを規約に沿って実施する。
origin: hmi-platform
---

# Codex 向け PR 作成ワークフロー

本プロジェクトのコードレビューは **Codex GitHub App** が担当する。本スキルは MVP タスク完了時に Codex がすぐレビューを開始できる形で PR を作る標準手順。

## 適用タイミング（When to Use）

- MVP タスクの実装・ビルド検証・README 進捗反映・kaizen-close が完了し、PR にする段階
- 既存 PR への追加コミットではなく、**新規 PR を作る** とき

## 前提

- **ChatGPT Codex（Web 版）** を使用。chatgpt.com の Codex → Settings から `hang-up33/hmi-platform` を GitHub OAuth 連携済み
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

```sh
gh pr create --title "Task N: <短い説明>" --body "$(cat <<'EOF'
## Summary
- <変更点の箇条書き 1>
- <変更点の箇条書き 2>

## 設計書との対応
- MVP Task N: <タスク名>
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
)"
```

- `--draft` を **付けない**（Codex がレビュー対象として扱いやすい状態にする）
- 不安な観点があれば `Codex 向け補足` セクションを具体的に書く（汎用的な「全体的に見てほしい」より、特定の観点を 1〜3 個提示）

### 6. PR URL を完了報告に含める

`gh pr create` の戻り値の URL をユーザーへの完了報告に貼る。

## やってはいけないこと（Must Never）

- `main` に直接 push / コミットする
- PR を draft で作る（Codex のレビュー開始が遅れる）
- PR を Claude 側でマージする（マージはユーザーの責任）
- `git add .` / `git add -A` で広く取り込む
- 既にレビュー中の PR を勝手に force-push して履歴を書き換える（追加コミットで対応する）

## Codex の指摘が付いたら

ユーザーから「Codex の指摘を修正して」と指示が来たら：

1. 指摘内容を取得：
   - 基本は `gh pr view <番号> --comments`（Codex は自動レビューで PR コメントに残す）
   - もし PR コメントに無く ChatGPT の chat 画面にしか出ていない場合のみ、ユーザーから貼ってもらう
2. 当該ブランチに `git checkout`
3. 指摘ごとに修正コミットを追加し、`git push`（force-push は基本しない）
4. 完了したらユーザーに「Codex 指摘 N 件を修正、再レビュー依頼可能」と報告
