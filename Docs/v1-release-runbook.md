# v1.0 公開当日の手順（2026-11-08）

計画書は [v1-release-plan.md](v1-release-plan.md)。Linux の検証は 11/5 に一度済ませたが、それ以降も不具合修正を main に入れるので、当日にもう一度回す。

| ファイル | 置き場所 | 中身 |
|---|---|---|
| `rewrite-history.sh` | [scripts/release/](../scripts/release/rewrite-history.sh) | main の履歴からメールとセッション URL を消し、確認まで行うスクリプト |
| `mailmap.txt` | **リポジトリの外**（ユーザーの手元） | 作者とコミッターの置き換え表。個人のメール入り |
| `msg-replace.txt` | **リポジトリの外**（ユーザーの手元） | コミットメッセージの置き換え表。個人のメール入り |

スクリプトを使うときは、`rewrite-history.sh` と 2 つの置き換え表を同じフォルダに置く。

必要なもの：`git` と `git-filter-repo`（`pip install git-filter-repo`）。

---

## 前半：V1-7 公開前検証

### 1. Linux（Claude が Web で行う）

```sh
git clone https://github.com/hang-up33/hmi-platform.git v1check && cd v1check
cmake -S . -B build -G Ninja -DCMAKE_PREFIX_PATH=<Qt のパス>
cmake --build build
ctest --test-dir build --output-on-failure   # -j を付けない（E2E のポートがぶつかる）
```

### 2. macOS（ユーザー）

```sh
git clone https://github.com/hang-up33/hmi-platform.git v1check && cd v1check
cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt
cmake --build build
ctest --test-dir build --output-on-failure
./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor --version   # hmi_editor 1.0.0
```

### 3. Windows（ユーザー）

```powershell
git clone https://github.com/hang-up33/hmi-platform.git v1check; cd v1check
.\scripts\windows\build.ps1
. .\scripts\windows\setup-env.ps1
ctest --test-dir build-mingw --output-on-failure
```

- `post_..._printsProjectVersion` の 3 本が、ダイアログを出さずに通ることを確かめる。止まったら Claude に知らせる。

### 4. Go / No-Go

計画書 `Docs/v1-release-plan.md` の「Go / No-Go 判定」をすべて確かめる。1 つでも ❌ なら公開しない。

---

## 後半：V1-8 公開作業

順番を守る。特に **1 と 2 は名前を変える前**に行う。

| # | やること | 誰が | 確かめること |
|---|---|---|---|
| 1 | 今のリポジトリの main へのマージを止める | ユーザー | 開いている PR が 0 件 |
| 2 | 今のリポジトリの self-hosted runner を削除する（Settings → Actions → Runners → Remove）。runner のコンテナを停止する | ユーザー | Runners の一覧が空 |
| 3 | `bash rewrite-history.sh https://github.com/hang-up33/hmi-platform.git ./hmi-platform-public` を実行する | ユーザーか Claude | 最後に「結果: OK」と出る |
| 4 | 置き換えた main の先頭にタグを打つ：`cd hmi-platform-public && git tag -a v1.0.0 -m "v1.0.0"` | 同上 | `git log -1 --format=%s` が #189 の内容 |
| 5 | 今のリポジトリの名前を `hmi-platform-archive` に変える（Settings → General → Repository name） | ユーザー | 旧 URL を開くと archive に転送される |
| 6 | 新しいリポジトリ `hang-up33/hmi-platform` を **private** で作る。README などは付けない（空で作る） | ユーザー | 空のリポジトリができる |
| 7 | `git remote add public https://github.com/hang-up33/hmi-platform.git` → `git push public main v1.0.0` だけを送る。`--mirror` と `--all` は使わない | ユーザーか Claude | GitHub 上に main とタグ v1.0.0 だけがある |
| 8 | 新しいリポジトリの中身を見る。README が表示される、コミットの作者に個人のメールが出ない、Runners が空 | ユーザー | — |
| 9 | Settings で設定する：Actions の「外部の fork PR は承認が必要」、Private vulnerability reporting を有効、Issues を有効、About の説明とトピック | ユーザー | — |
| 10 | 新しいリポジトリを **public** にする（Settings → General → Danger Zone → Change visibility） | ユーザー | ログインせずに開ける |
| 11 | ブランチ保護：main への直接 push を禁止し、linux CI の緑を必須にする | ユーザー | — |
| 12 | Codex と CodeRabbit の GitHub App を新しいリポジトリに入れる。ChatGPT Codex の Settings で連携先を変える | ユーザー | — |
| 13 | GitHub Release を作る（タグ v1.0.0、本文は CHANGELOG.md の 1.0.0 の節） | ユーザー | Release ページが出る |
| 14 | 公開後の確認：ログインせずにクローンしてビルドできる。新しいリポジトリの CI（linux・macOS・Windows）が緑 | Claude | — |
| 15 | 今のリポジトリ（archive）を Archive にする（Settings → General → Archive this repository） | ユーザー | 読み取り専用になる |

### 公開後の各マシンの片付け

- Mac・Windows・WSL の古いクローンは、`git remote set-url origin https://github.com/hang-up33/hmi-platform-archive.git` で archive に向け直す。古いクローンから新しいリポジトリへ push しない。
- 新しいリポジトリの作業は、新しくクローンして始める。
- 各マシンで `git config --global user.email "152175189+hang-up33@users.noreply.github.com"` を設定する。
- GitHub のアカウント設定（Settings → Emails）で「Block command line pushes that expose my email」を有効にする。
- Claude Code on the Web の環境を、新しいリポジトリに向け直す。

---

## 困ったとき

- `rewrite-history.sh` が「NG」を出したら、公開しない。出力をそのまま Claude に見せる。
- 7 で間違えて別のブランチを送ったら、新しいリポジトリはまだ private なので、リポジトリごと消して 6 からやり直せばよい。
