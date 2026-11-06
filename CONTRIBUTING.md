# Contributing / 貢献の手引き

Atlas（hmi-platform）への貢献を歓迎する。不具合の報告・要望・PR のどれでもよい。

> **English summary**: Bug reports, feature requests and pull requests are welcome. Please build with CMake and run `ctest` before opening a PR. Discussions and reviews are mainly in Japanese, but English is fine.

## 不具合の報告と要望

- GitHub の Issue で受け付ける。テンプレートに沿って書いてほしい。
- セキュリティに関わる不具合は Issue に書かず、[SECURITY.md](SECURITY.md) の方法で非公開で知らせてほしい。

## ビルドとテスト

必要なもの：Qt 6.8 以上、CMake 3.21 以上、C++17 対応のコンパイラ。手順の詳細は [README.md](README.md) にある。

```sh
cmake -S . -B build -DCMAKE_PREFIX_PATH=<Qt のインストール先>
cmake --build build
ctest --test-dir build --output-on-failure
```

- E2E テストは同じ通信ポートを使うので、`ctest -j` で並列に回すと失敗する。並列なしで回す。
- Modbus や OPC-UA の E2E テストは、Python のパッケージ（`pymodbus` / `asyncua`）が無いと自動で SKIP になる。
- OPC-UA の E2E テストは、Qt OPC UA が入っているときだけ登録される。
- Windows（MinGW）では E2E テストは既定で無効になる。
- 画面の操作を録画しながら主な流れを確かめる受け入れ試験もある（Linux のみ）。手順は [scripts/acceptance/README.md](scripts/acceptance/README.md) にある。

## PR の出し方

1. `main` からブランチを作る。名前は `fix/<内容>`・`feat/<内容>`・`docs/<内容>` のようにする。メンテナのタスクは [Docs/workflow.md](Docs/workflow.md) の別の規約で進めるが、外部からの PR はこの形でよい。
2. 1 つの PR には 1 つの目的だけを入れる。
3. ビルドと `ctest` が通ることを確かめてから PR を出す。
4. PR を出すと、自動のコードレビュー（Codex / CodeRabbit）が付くことがある。指摘への対応をお願いすることもある。
5. マージするかどうかは、メンテナが判断する。

## コードの書き方

- Widget・Screen・Project の型と JSON の読み書きは `Shared/Schema` にだけ書く。
- 新しい Widget を足すときの手順と罠は [Docs/architecture.md](Docs/architecture.md) と `.claude/rules/` にまとめてある。
- コミットメッセージは `<種類>: <何を変えたか>` の形にする（種類は `feat` / `fix` / `docs` / `refactor` / `test` / `chore`）。
- コミットに個人のメールアドレスを入れたくない場合は、GitHub の noreply アドレスを `git config user.email` に設定する。

## AI ツールの利用について

本プロジェクトは、Claude Code（Anthropic）を使って開発し、Codex でレビューしてきた。AI ツールを使った PR も受け付ける。

- 内容を自分で確かめてから出してほしい。ビルドとテストが通ることは必須。
- AI ツールを大きく使った場合は、PR の本文にその旨を一言書いてほしい。

リポジトリには Claude Code 用の設定（`CLAUDE.md`・`.claude/`）が入っている。Claude Code で作業すると、`.claude/settings.json` に登録したフック（スクリプト）が自動で動く。中身は `scripts/hooks/` で確認できる。

## 行動規範

参加する人は [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) を守ってほしい。

## ライセンス

PR で送ったコードは、本プロジェクトと同じ [MIT License](LICENSE) で公開されることに同意したものとする。
