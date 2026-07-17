# 対象の取得 / Fetch the target（hmi-platform 版）

フェーズAの最初の一歩。**PR番号・コミットID・URL・ファイル指定 のいずれかで動く。** 本リポジトリ（`hang-up33/hmi-platform`, GitHub）はローカルにチェックアウト済みなので、取得はまず **ローカル git** で行う。git はオフラインかつ認証不要で、番号／ハッシュだけから差分を復元できる。

> **ブラウザ URL を直接 fetch しに行かない。** URL からは PR番号／コミットハッシュだけ取り出し、下記の git（または `gh` / GitHub MCP）で解決する。エージェントの Web 取得経路はログイン Cookie を共有せず、private リポでは 404 になりやすい。

## 0. 前提：この環境で GitHub をどう叩くか

- **ローカル開発機（母艦 / Mac）**: `gh` CLI が使える（CLAUDE.md「Codex 連携 / PR ワークフロー」でも全面的に `gh` を使う）。PR の取得は `gh pr view/diff/checkout` が最短。
- **Claude Code on the web / リモート環境**: `gh` は無い。**GitHub MCP tools**（`mcp__github__pull_request_read` / `get_file_contents` / `get_commit` / `list_commits` 等）を使う。まず `git` でローカル解決を試み、リモートにしか無い PR/コミットは MCP で引く。
- どちらでも **ローカル git が第一手**（オフラインで速い・差分が確実）。

## 1. コミットID（短縮 / 完全ハッシュ）

```bash
git show <id> --stat   # 変更ファイル一覧（概要把握）→ 理解度表の初期行になる
git show <id>          # 全差分
```

大規模コミットでは `git show <id>` の出力が長大になる。**まず `--stat` で全体を概観し、フェーズBで扱うファイルの差分だけをファイル単位で読む**（`git show <id> -- <file>`）。一度に全差分を抱え込まない。

## 2. PR 番号（#NNNN）

本リポジトリは原則 **Squash and merge** で main に取り込む（CLAUDE.md「マージ戦略」）。squash マージのコミットは件名末尾に `(#NNNN)` を含む（例: `Task 49: Label round-trip (#123)`）。ただし **過去には二親マージ（`Merge pull request #NNNN ...`）で取り込まれた履歴も混在する**（例: このリポジトリの `Merge pull request #142`）。**両形式を検索して取りこぼさない。**

```bash
# 両方のマージ形式を一度に検索（末尾 (#NNNN) の squash / "Merge pull request #NNNN" の二親マージ）
git log --all --oneline -E --grep "\(#NNNN\)" --grep "Merge pull request #NNNN"
```

ヒットしたコミットのマージ形式で経路を分ける（親の数で判定＝`git show <sha> --no-patch --format=%P` の親が 1 つか 2 つか）:

```bash
# (A) squash（親 1 つ）: そのコミットがそのまま PR の正味差分
git show <sha> --stat        # 変更ファイル概要
git show <sha>               # 差分（親 1 つなので一意）

# (B) 二親マージ（親 2 つ・"Merge pull request #NNNN"）: 取り込み先 → マージ後の正味を撮る
git show <merge> --stat -m   # -m で各親に対する差分を表示
git diff <merge>^1 <merge>   # 取り込み先(第1親) → マージ後の正味差分
```

**PR がまだ open（未マージ）／ローカルに無い場合**:

```bash
# ローカル機（gh あり）— まず「読むだけ」で完結させる（作業ツリーを切り替えない）:
gh pr view <NNNN>            # 概要・本文・レビュー
gh pr diff <NNNN>            # 差分（この2つで理解対象は揃う。既定はこちら）

# web / リモート（gh 無し → GitHub MCP）
#   mcp__github__pull_request_read（method: get / get_diff / get_files）で owner=hang-up33 repo=hmi-platform pullNumber=<NNNN>
```

> **⚠️ `gh pr checkout <NNNN>` を安易に使わない。** 現在の作業ツリーのブランチを切り替えるため、**未コミット変更があると失敗**し、成功しても**学習後に元ブランチへ戻し忘れる**（ユーザーが開発中のことが多い）。このスキルは読み取りが目的なので **`gh pr diff` を既定**にする。実装全体をファイル単位で読み込みたい時だけ、作業ツリーを汚さない **別 worktree** で開く:
> ```bash
> git fetch origin +pull/<NNNN>/head:pr-<NNNN>       # PR を専用ローカル ref に取得（先頭 + で force。rebase/force-push 後も最新 head に追従）
> git worktree add ../hmi-pr-<NNNN> pr-<NNNN>        # 別ディレクトリに展開（現ブランチは触らない）
> #   …読み終わったら: git worktree remove ../hmi-pr-<NNNN>
> ```
> どうしても同じツリーで `gh pr checkout` する場合は、事前に現ブランチ名を控え（`git branch --show-current`）、`git status` がクリーンなことを確認し、学習後に必ず元ブランチへ戻す。

## 3. URL（GitHub）

URL 末尾から **PR番号** または **コミットハッシュ** を取り出し、上の 1 / 2 を実行する。

- 例: `github.com/hang-up33/hmi-platform/pull/123` → `#123` を 2. へ
- 例: `github.com/hang-up33/hmi-platform/commit/43e3255...` → `43e3255` を 1. へ

## 4. ファイル / ディレクトリ指定（差分ではなく "このコード" を理解したい場合）

このスキルは差分に限らない。「この実装を理解したい」という依頼では、対象ファイル群をそのまま読む。本リポジトリの主要な読みどころ:

- `Shared/Schema/`（Widget/Screen/Project の型と JSON I/O ＝**唯一の真実**）
- `Shared/Widgets/qml/` / `Editor/` / `Simulator/`（QML と C++ ブリッジ）
- `Runtime/`（CMake glue のみ。実体は Simulator ソース共有）

```bash
git ls-files <dir>            # 対象ディレクトリのファイル一覧 → 理解度表の初期行
git log --oneline -- <file>   # そのファイルの変更履歴（意図をたどる補助）
```

## 5. ブランチ全体で「本当の実装状況」を捉える（重要）

コミット単体は "その時点のスナップショット" にすぎない。特に「仮実装」コミットは、同じフィーチャーブランチ上の後続コミットで **バグ修正・リネーム・作り直し** されていることが多い（本リポジトリは Codex 自走ループで 1 PR に複数の修正 push が積まれるため特に顕著）。古い版を100%理解しても現在の実装とズレていては意味がない。**理解の対象は、原則そのコミットを含むブランチの tip（＝仮実装ではなく、いま動くコード）に合わせる。**

> **⚠️ `HEAD` を対象ブランチの tip と決めつけない。** bare なコミットID だけを受け取った場合、いまチェックアウト中の `HEAD` は `main` や無関係な作業ブランチのことが多い。そのまま `<commit>..HEAD` を撮ると、対象 PR の後続修正は取れず、逆に現在ブランチの無関係コミットが混入して目的が逆転する。**まず「対象コミットを含むブランチの tip」を解決し、その ref を使う。**

対象コミットを受け取ったら、まず tip を解決してから後続を確認する。

```bash
# ① 対象コミットを含むブランチ tip を解決する（この <tip> を以降で使う。HEAD をそのまま使わない）
#   - PR番号がわかる → その head SHA を <tip> にするのが確実（作業ツリーは切り替えない）:
gh pr view <NNNN> --json headRefOid,headRefName   # head SHA/ブランチ名を取得 → <tip> に採用
#     web/リモート（gh 無し）: mcp__github__pull_request_read(method:get) の head.ref / head.sha を <tip> とする
#     （実装全体を読む時は上記「別 worktree」で開く。gh pr checkout での作業ツリー切替は避ける）
#   - コミットIDしか無い → それを含むブランチを探す:
git branch -a --contains <commit>   # 対象コミットを含むブランチ一覧
#       ⚠️ 採用してよいのは「フィーチャーブランチ」だけ。既にマージ済みで PR ブランチが
#          削除されていると、--contains は更新が進んだ base ブランチ（main 等）しか返さない。
#          それを <tip> に採ると、対象コミット後に main へ入った"無関係な"変更まで後続修正として混入する。
#       → 候補に base 以外のフィーチャーブランチがあればその tip を <tip> に採用。
#       → 候補が base ブランチ（main/master/develop 等）だけなら <commit> 自体を <tip> とみなす（後続は無しとして扱う）。
#   - PR の head SHA が取れる（gh / MCP）なら、それを含むブランチ tip を優先的に <tip> にする（最も確実）。

# ② tip が決まったら後続と差分を確認する（HEAD ではなく解決した <tip> を使う）
git log --oneline <commit>..<tip>   # そのコミット以降の後続コミット
git diff <commit> <tip> --stat      # 仮実装→現在で何が変わったか（変更行が多いファイルは"作り直された"サイン）
```

ブランチが分岐した基点からの正味差分（＝このブランチが持ち込んだ実装の全体。本リポジトリの base は原則 `main`）:

```bash
# base ref を先に決める。origin が無いローカル専用クローン（git remote -v が空）では
# origin/main が解決できず merge-base / diff が失敗するので、main へフォールバックする:
BASE=origin/main; git rev-parse --verify -q "$BASE" >/dev/null || BASE=main
git merge-base <tip> "$BASE"       # 基点を特定
git diff "$BASE"...<tip> --stat    # 3ドット。基点→tip の正味差分
```

> リモート名が `origin` でない・base ブランチが `master`／`develop` 等の場合は、`git remote` と `git branch` で実在するものに読み替える（`$BASE` に代入する ref を差し替えるだけ）。

進め方:

- 理解度表・全体図は **解決した tip の状態** で作る（仮実装ではなく、いま動くコード）。
- 後続コミットが直した箇所は、フェーズBで「仮実装ではこう書かれていたが、後で◯◯の理由で直された」と **差分そのものを学習材料** にする。*なぜ直したか*（＝Codex 指摘への対応）が最良の教材になる。
- 「仮実装だけ読んで満足」を防ぐため、後続コミットの有無と要点は必ずユーザーに伝える。

## 6. 見つからない / 取得できない時

```bash
git fetch --all --prune   # 最新のPR・コミットを取り込んでから再試行
```

- ローカルに無い PR/コミットは `gh`（ローカル機）か GitHub MCP（web）で引く（上の 2. 参照）。
- 作業ディレクトリが対象リポジトリでない場合は、対象リポジトリへ移動して再実行する（本スキルの既定対象は `hmi-platform`）。
- それでも解決できない場合に限り、ユーザーへ `git show` / `git diff` の **差分本文** の貼り付けを依頼する。最低限「変更ファイル一覧＋主要ハンク＋変更理由 1〜2 行」があれば学習を継続できる。
- 取得に失敗しても「理解不可」で終わらせない。未確定事項を明示し、手元にある材料で全体図と理解度表の初期化まで進める。

## 取得後にやること

1. `--stat` / `ls-files` で出たファイル一覧を、そのまま **理解度表の初期行**（理解度=`未着手`）にする。
2. 全体図（mermaid）を1枚描く材料として、主要ファイル間の呼び出し・データの流れを差分から拾う（本リポジトリなら「Schema 型 → JSON I/O → QML Widget 描画 → C++ ブリッジ」のような流れ）。
3. 差分本体は、フェーズBで「ユーザーに読ませる」ための教材として手元に置く（Claude が先に全部解説してしまわないこと）。
