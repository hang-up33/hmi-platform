# AGENTS.md

このファイルは **ChatGPT Codex（GitHub App / Codex CLI）** に対するリポジトリ共通の指示です。
リポジトリの開発指針・アーキテクチャ・ビルド手順・ブランチ運用は [CLAUDE.md](CLAUDE.md) と [README.md](README.md) を参照してください。

---

## Review guidelines

Codex が PR レビューを行う際は、以下のルールに従ってください。

### 言語

- **レビューコメントはすべて日本語で記述してください**（コード識別子・ファイルパス・引用ブロックは英語のままで構いません）。
- PR サマリ・指摘・サジェスト本文・コミット提案など、Codex が生成する全ての自然言語出力を日本語にしてください。

### 指摘の書き方

- 指摘ごとに **「何が」「なぜ問題か」「どう直すべきか」** の 3 点を簡潔に書いてください。
- 該当ファイル・行番号を明示してください（GitHub の suggestion ブロックを使える場合は積極的に使用）。
- 重要度を `[Blocker]` / `[Major]` / `[Minor]` / `[Nit]` のいずれかでラベル付けしてください。

### スコープ

- 本リポジトリは **Phase 4 / Button 縦スライス（Task 25〜32）まで完了**（旧 Phase 4〔Task 25〜30〕＋旧 Phase 5〔Task 31〜32〕を 1 本に統合。Button 1 つを全レイヤ（Schema→Widgets→Editor→Simulator→Runtime→実機）で深く作り込み「Widget 追加テンプレ」を確立。選択・インスペクタ・リサイズ・削除・スタイル属性〔色・フォント・ボーダー・角丸〕の Schema 拡張・テスト/E2E 拡充・i.MX8MP 実機 styled 描画・macOS E2E 緑まで到達。Task 31〜32 マージ済み PR #64 / #66。[CLAUDE.md](CLAUDE.md) の「現在のフェーズ」参照）。**Phase 4 までで未着手のフェーズタスクは無い**。次の **Phase 5（Widget 種別の横展開 Label / Lamp 等・状態/アクション・静的スタイルの続き）は「候補」段階で未承認**のため、`Docs/phase4-button-slice-plan.md`「Phase 5 候補」のスコープをユーザーと確定・承認してから着手する（自動着手しない）。E2E 検証は macOS で実施（Windows MinGW は E2E 既定 OFF）。
  進行予定のフェーズスコープ（[Docs/phase4-button-slice-plan.md](Docs/phase4-button-slice-plan.md)）を逸脱する大規模リファクタ提案は控えめにし、必要であれば `[Future]` ラベルで分離してください。
- フォルダ構成変更（`Editor/ Simulator/ Runtime/ Shared/Schema/ Shared/Widgets/ Docs/`）は禁止です。提案しないでください。
- qmake その他の代替ビルドシステム導入は禁止です。CMake 前提でレビューしてください。

### 重点的に見てほしい観点

- **Shared/Schema が JSON I/O の唯一の真実か** — Widget / Screen / Project 型と JSON 入出力が `Shared/Schema` 以外に漏れていないか。
- **QML モジュール URI とアプリの `loadFromModule()` 引数の一致** — `HmiEditor` / `HmiSimulator` / `HmiWidgets`。
- **QtQuick 標準型との QML ファイル名衝突** — `Canvas.qml` / `Button.qml` / `Rectangle.qml` などのプレフィックス無し命名は要警告。
- **共有 QML モジュールの STATIC ビルド + plugin 直リンク構成** — `Shared/Widgets` を `MODULE_LIBRARY` で作っていないか。
- **macOS の Qt バージョン罠** — `~/Qt/6.7.0/macos` を `CMAKE_PREFIX_PATH` に指定する変更は AGL リンクエラーで破綻するので要警告。

---

## Codebase context

ビルド・実行・アーキテクチャの詳細は [CLAUDE.md](CLAUDE.md) を参照してください。Codex CLI が自律的にコードを編集する場合も、CLAUDE.md の「Must Always / Must Never」を遵守してください。
