# AGENTS.md

このファイルは **ChatGPT Codex（GitHub App / Codex CLI）** に対するリポジトリ共通の指示です。

---

## 1. 情報の正本（Single Source of Truth）

レビュー時や作業時は、次のドキュメントを正本として参照してください。

- **ドキュメント地図**: [DOCS-MAP.md](DOCS-MAP.md)
- **レビューガイドライン（詳細）**: [Docs/agents/review-guidelines.md](Docs/agents/review-guidelines.md)
- **現在のフェーズ・タスク進捗**: [Docs/phase-status.md](Docs/phase-status.md)
- **アーキテクチャ・モジュール構造**: [Docs/architecture.md](Docs/architecture.md)
- **開発ワークフロー・開発ルール**: [Docs/workflow.md](Docs/workflow.md)
- **開発経緯・PR 履歴**: [Docs/development-history.md](Docs/development-history.md)

---

## 2. レビューの出し方

- **言語**: レビューコメントはすべて日本語で書いてください。PR サマリ・提案文・コミット提案も日本語です。コード識別子・ファイルパス・引用は英語のままで構いません。
- **書き方**: 指摘ごとに「何が」「なぜ問題か」「どう直すべきか」を短く書き、ファイルと行を示してください。
- **重要度**: `[Blocker]` / `[Major]` / `[Minor]` / `[Nit]` / `[Future]` のどれかを付けてください。基準は [review-guidelines.md](Docs/agents/review-guidelines.md) の「2. 重要度の基準」です。
- **1 回で出し切る**: 見つけた指摘は 1 回のレビューですべて出してください。ユーザーの依頼で再レビューする場合も、前回の対応で決まった方針を別の角度から蒸し返さないでください。

レビュー依頼は 1 つの PR につき 1 回だけで、再レビューはありません。指摘はこの 1 回ですべて出してください。

---

## 3. スコープ

- 現在のフェーズと次のタスクは [Docs/phase-status.md](Docs/phase-status.md) を見てください。ここには書きません（二重管理で古くなるのを防ぐため）。
- 進行中のフェーズを外れる大きなリファクタリングの提案は、`[Future]` を付けて分けてください。
- フォルダ構成（`Editor/` `Simulator/` `Runtime/` `Shared/Schema/` `Shared/Widgets/` `Docs/`）を変える提案はしないでください。
  - 守りたいのはソースとビルドの構成です。`Docs/` の中の整理は、ユーザーが承認した場合に限り行います。
- qmake など CMake 以外のビルドシステムの導入は提案しないでください。

---

## 4. 重点的に見てほしい観点

- **`Shared/Schema` が JSON 入出力の唯一の実装か**: Widget / Screen / Project の型と JSON 入出力が、ほかの場所に漏れていないか。
- **QML モジュール URI と `loadFromModule()` の引数が一致しているか**: `HmiEditor` / `HmiSimulator` / `HmiWidgets`。
- **QtQuick 標準型と QML ファイル名がぶつかっていないか**: `Canvas.qml` / `Button.qml` のような名前は警告してください（`Hmi` プレフィックスが必須）。
- **共有 QML モジュールの構成**: `Shared/Widgets` を `MODULE_LIBRARY` で作っていないか（STATIC ビルド + plugin 直リンクが正しい構成）。
- **macOS の Qt バージョン**: `~/Qt/6.7.0/macos` を `CMAKE_PREFIX_PATH` に指定すると AGL のリンクエラーになるので警告してください。
