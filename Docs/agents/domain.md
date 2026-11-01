# Domain Docs

engineering skills がこのリポジトリのコードを探索する前に読むべきドメイン資料と、その扱い方。

## 探索前に読む

このリポジトリには `CONTEXT.md` / `CONTEXT-MAP.md` は無い。代わりに以下を読む:

- **`Docs/architecture.md`** — モジュール構造（Editor / Simulator / Runtime / Shared）
- **`Docs/requirements/`**（索引 `README.md`）— 用語・機能の定義（Widget 種別名、変数、アクション等）
- **`.claude/rules/schema-conventions.md`** — Shared/Schema の型・JSON I/O 規約
- **`.claude/rules/qml-module-conventions.md`** — QML モジュール・結線規約
- 触る領域に対応する計画書の設計判断
  - **進行中フェーズ** … `Docs/phase*-plan.md`（現在は `phase7-modbus-plan.md` と `refactoring-plan.md`）
  - **完了済みフェーズ** … `Docs/archive/phase*-plan.md`（Phase 1〜11 の大半はここ。一覧は [Docs/archive/README.md](../archive/README.md)）
  - どのファイルが人間向け / AI 向け・現行 / アーカイブかは [DOCS-MAP.md](../../DOCS-MAP.md) を見る

ADR（アーキテクチャ決定記録）の正式な置き場（`Docs/adr/`）はまだ無い。
無いことを問題として報告しない。決定が実際に固まった時点で `/domain-modeling` が作る。
設計判断の実質的な履歴は `Docs/development-history.md` にある。

## 用語はプロジェクトの語彙に合わせる

出力（PR タイトル・リファクタ提案・仮説・テスト名）でドメイン概念に触れるときは、
`Docs/requirements/` で定義された用語を使う（`SimpleButton` などの Widget 種別名、
開発コードネーム「Atlas」など）。勝手な同義語・造語に流れない（`.claude/rules/user-no-coined-terms.md`）。

必要な概念が `Docs/requirements/` に無ければ、それは兆候: 造語しているなら見直す。
本当に欠けているなら `/domain-modeling` 用にメモする。

## 既存の設計判断と矛盾したら明示する

出力が `Docs/development-history.md` や計画書（`Docs/*-plan.md` / `Docs/archive/*-plan.md`）の既存判断と矛盾する場合、
黙って上書きせず明示的に指摘する（例: 「archive/phase9-opcua-plan.md の方針と矛盾するが、
〜のため再検討の価値あり」）。
