---
name: progress-summary
description: 指定期間の実装状況・進捗を PR / タスクごとに列挙する標準ワークフロー。「6/6〜6/7の進捗教えて」「先週の実装状況まとめて」「最近のタスク列挙して」のような指示で発火。既定は機能だけの簡潔な箇条書き、求められたら PR 番号・タスク付きの詳細版も出す。
origin: hmi-platform
---

# Progress Summary — 期間ごとの実装状況まとめ

指定期間に何を実装したかを、**マージ済み PR / タスク単位**で振り返って列挙する標準手順。
週次の振り返り・関係者への共有・development-history 追記の下地づくりに使う。

## 適用タイミング（When to Use）

- 「<期間>の進捗 / 実装状況 / やったこと を教えて・まとめて・列挙して」
- 「最近のタスク / PR を一覧にして」
- development-history.md やレポート用に、ある期間の成果を整理したい時

## 既定の出力スタイル（重要）

**まず「機能だけの簡潔な箇条書き」を出す**（ユーザーの好み。冗長な説明・PR 番号の羅列は最初から付けない）。
詳細（PR 番号・ブランチ名・Codex 指摘対応・テスト結果など）は **求められてから** 足す。
書き物は日本語（[[user-language-japanese]]）。

## 手順（How It Works）

### Step 1: 期間内のコミット / マージを集める

```sh
# 日付は %m/%d で見やすく。--all で全ブランチのマージコミットも拾う
git log --since="<開始> 00:00" --until="<終了+1日> 00:00" \
  --pretty=format:"%h | %ad | %s" --date=format:"%m/%d %H:%M" --all
```

- `Merge pull request #N from <branch>` 行が PR 単位の区切り。これを基準にグルーピングする。
- ローカルが `origin/main` から遅れていることがある（[dev-environment.md] 参照）。
  正確を期すなら先に `git fetch origin` し、必要なら GitHub MCP（`mcp__github__list_pull_requests` を
  `state=closed` / `sort=updated`）でマージ済み PR を突き合わせる。

### Step 2: PR / タスクごとに「実装した機能」を 1 行で抽出

- 1 PR = 1 項目。コミットメッセージから **ユーザーに見える機能の変化**だけを拾う
  （`Task N: ...` 本体や `feat:` を優先。`Codex 指摘対応` `empty commit` `lint` などの過程コミットは既定では畳む）。
- docs/計画・CI・環境整備の PR も「機能」ではないが成果なので、簡潔版では **1 行に圧縮**して残す。

### Step 3: 既定＝機能だけ列挙して出す

```
- ボーダー＋角丸（borderColor / borderWidth / radius）の全レイヤ貫通
- フォント詳細（fontBold / fontItalic / fontFamily）の全レイヤ貫通
- Claude Code on the web での PC ビルド・テスト対応
- CI の Linux 主ゲート化（mac/win は必要時のみ）
```

「PR / タスクごとに」と明示されたら、PR 番号・ブランチ・タスク番号付きの詳細版に切り替える：

```
**PR #64** task/31-button-border-radius — Task 31: ボーダー＋角丸を全レイヤ貫通
- borderColor / borderWidth / radius を Schema→C++→delegate→HmiButton→インスペクタまで貫通
```

## 注意（罠）

- **過程コミットを機能として数えない**：`Codex #N P2 対応` / `empty commit` / `trigger CI` は成果の本体ではない。
- **粒度はユーザー指定に従う**：「長いので機能列挙だけ」と言われたら PR 番号もサマリも落として箇条書きのみにする。
- **マージされていない作業中ブランチを「実装済み」と書かない**：基準は **マージ済み PR**。

関連：[[user-language-japanese]] / development-history への記録は [Docs/development-history.md] が正。
