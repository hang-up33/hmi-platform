# Issue トラッカー: このリポジトリ独自のワークフロー

このリポジトリ（Atlas / hmi-platform）は、GitHub Issues を自分たちの課題管理には使わない。
代わりに Docs 配下の 2 種類のドキュメントで管理する。

v1.0 の公開後は、外部の人から不具合報告と要望を受け付ける窓口として Issues を有効にする。
受け付けた Issue のうち対応するものは、`Docs/requirements/` の REQ か、進行中の計画書のタスクに書き写してから着手する。

## 課題・要求が住んでいる場所

| 層 | 場所 | 役割 |
|---|---|---|
| 機能バックログ（中長期） | `Docs/requirements/` | 関心別の要求仕様書（REQ/ACC 管理表付き）。優先度 P0/P1/P2。 |
| 実装タスク（いま作る1件） | `Docs/phase*-plan.md` | バックログから切り出した **進行中** フェーズの計画。**各ファイルの「進捗」表が進捗の正本**。 |
| 完了済みフェーズの計画 | `Docs/archive/phase*-plan.md` | 完了フェーズの実装指示書（Phase 1〜11 の大半）。一覧は [Docs/archive/README.md](../archive/README.md)。 |
| 全フェーズ横断の状態 | `Docs/phase-status.md` | どのフェーズまで終わったかのスナップショット。 |

> **現行と完了済みでパスが違う**点に注意：進行中は `Docs/` 直下、完了済みは `Docs/archive/` 配下。
> 文書全体の区分は [DOCS-MAP.md](../../DOCS-MAP.md) を見る。

`Docs/requirements/README.md` のとおり「フェーズ計画はここから切り出して起票する」。

## デリバリ

- ブランチ: `task/<N>-<短い名>`（フェーズタスク）/ `docs/<短い名>`（ドキュメント・設定）
- `main` 直 push 禁止。PR 経由。
- レビュー: Codex GitHub App（上限時は CodeRabbit にフォールバック）。依頼は 1 PR 1 回。Blocker / Major を直して push し、再依頼しない。
- マージはユーザーが行う（Claude はマージしない）。
- 詳細は CLAUDE.md「PR ワークフロー」/ `.claude/rules/feedback-codex-*.md`。

## skill が「issue トラッカーに publish しろ」と言ったら

新しい機能アイデアなら `Docs/requirements/` の該当する仕様書の「要件」表に REQ を追加する。
それを実際に着手する段階なら `Docs/` 直下に `Docs/phase*-plan.md` を新規作成（または既存の進行中フェーズ計画に追記）し、
進捗表を更新する。GitHub issue は作らない。新規作成は必ず `Docs/` 直下で、`Docs/archive/` には置かない。

## skill が「関連チケットを fetch しろ」と言ったら

対象領域の `Docs/requirements/` の該当仕様書と、対応する計画書（進行中なら `Docs/phase*-plan.md`、
**完了済みなら `Docs/archive/phase*-plan.md`**）を進捗表込みで読む。完了フェーズの設計判断は archive 側にしかない。

## skill が「issue の一覧が欲しい」と言ったら

`Docs/phase-status.md` と、各計画書（`Docs/phase*-plan.md` / `Docs/archive/phase*-plan.md`）の「進捗」表を読む。
未着手の候補は `Docs/requirements/` の優先度 P0/P1 で状態が「未実装」の REQ。
