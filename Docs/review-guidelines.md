# レビューガイドライン (Review Guidelines)

本ドキュメントは、ChatGPT Codex（GitHub App / Codex CLI）および AI Agent が本リポジトリで **PR レビューおよびコードレビューを行う際のガイドライン** です。

---

## 1. 言語

- **レビューコメントはすべて日本語で記述してください**（コード識別子・ファイルパス・引用ブロックは英語のままで構いません）。
- PR サマリ・指摘・サジェスト本文・コミット提案など、エージェントが生成する全ての自然言語出力を日本語にしてください。

---

## 2. 指摘の書き方

- 指摘ごとに **「何が」「なぜ問題か」「どう直すべきか」** の 3 点を簡潔に書いてください。
- 該当ファイル・行番号を明示してください（GitHub の suggestion ブロックを使える場合は積極的に使用）。
- 重要度を以下のラベルで指定してください：
  - `[Blocker]`: ビルド破壊・機能不全・重度のバグなど、マージ不可な問題
  - `[Major]`: 設計違反・パフォーマンス劣化・仕様不一致など
  - `[Minor]`: リファクタリング提案・軽微な改善点
  - `[Nit]`: 軽微なタイポやスタイルの指摘

---

## 3. レビュー時の制約事項・禁止事項

- **スコープの遵守**: 計画中のフェーズスコープ（[Docs/phase-status.md](Docs/phase-status.md)）を逸脱する大規模リファクタ提案は控えめにし、必要であれば `[Future]` ラベルで分離してください。
- **フォルダ構成変更の禁止**: フォルダ構成（`Editor/`, `Simulator/`, `Runtime/`, `Shared/Schema/`, `Shared/Widgets/`, `Docs/`）を変更する提案は禁止です。
- **代替ビルドシステム導入の禁止**: qmake その他の代替ビルドシステム導入提案は禁止です。CMake 前提でレビューしてください。

---

## 4. 重点的に確認すべき観点

1. **Shared/Schema が JSON I/O の唯一の真実か**
   - Widget / Screen / Project 型と JSON 入出力が `Shared/Schema` 以外に漏れていないか。
2. **QML モジュール URI とアプリの `loadFromModule()` 引数の一致**
   - `HmiEditor` / `HmiSimulator` / `HmiWidgets` の一致を確認。
3. **QtQuick 標準型との QML ファイル名衝突**
   - `Canvas.qml` / `Button.qml` / `Rectangle.qml` などのプレフィックス無し命名がないか（`HmiButton.qml` のように `Hmi` プレフィックス必須）。
4. **共有 QML モジュールの STATIC ビルド + plugin 直リンク構成**
   - `Shared/Widgets` を `MODULE_LIBRARY` で作っていないか確認。
5. **macOS の Qt バージョン罠**
   - `~/Qt/6.7.0/macos` を `CMAKE_PREFIX_PATH` に指定する変更は AGL リンクエラーで破綻するので要警告。
