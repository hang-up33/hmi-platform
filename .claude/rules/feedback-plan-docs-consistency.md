---
name: feedback-plan-docs-consistency
description: 計画ドキュメント（Phase plan / 設計書）を書くときに踏むべき整合性・実装可能性ルール
metadata: 
  type: feedback
---

計画ドキュメント（`Docs/phase*-plan.md` 等）を新規作成・更新する際は、以下を必ず守る：

1. **実装側 API の制約を踏まえる**。CLI 仕様や CMake 設定を書くときは、`QCommandLineParser` / `add_test` などの実体の動作を確認してから書く。例：
   - `--e2e [<port>]` のような **optional value 表記は `QCommandLineParser` がサポートしない** → 真偽フラグ + 別の値オプションに分割する書き方にする
   - `add_test` の `DEPENDS` プロパティは **他テストの run-after 順序のみ**を制御し、ビルドターゲット依存は保証しない → ビルドは外側で担保する旨に書く
2. **未確認情報を断定形で書かない**。通信プロトコルなどライブラリ仕様は「Task X 着手時に最新 README / examples を確認」と明示的に保留する。例：Spix を「素の socket + JSON で十分」と断定したら実体は XML-RPC で、実装者が誤実装するリスクがあった
3. **複数アプリ／複数モジュールに同じ統合が必要なら Task 名に両方明記**。Editor / Simulator 等で同じ作業が要るなら「Editor 統合」だけ書くと片方が抜ける。**さらに新フェーズで新規アプリを足す時は、計画書の冒頭で「各アプリの動作環境（PC のみ / 実機のみ / 両方）」「ソース共有関係（独立 / 共有 / Shared 抽出）」を表で明文化する**。例：Phase 3-B v1（PR #36、クローズ）では「Editor JSON を i.MX8MP で描画」と書いたが「Editor 自体を i.MX に載せる」と誤読される表現だった。Editor=PC 専用、Runtime=実機専用、Simulator と Runtime はソース共有、という関係を最初に書いておけば防げた
4. **既定値（ポート / パス / バージョン番号）は plan の複数箇所で必ず揃える**。1 箇所更新したら他の箇所もまとめて確認する。Editor / Simulator のポート競合のように、同一マシン同時起動を考えるとき特に重要
5. **README の進捗表は plan 本体と同期させる**。plan の Task 名やスコープを更新したら README 進捗表も同時に更新

**Why:** PR #27（Phase 3-A plan 起票）で Codex から 4 ラウンド計 5 件の指摘を受けた（P1 ×2, P2 ×2, P3 ×1）。すべて上記のいずれかに該当する整合性・実装可能性の問題で、最初から守れば 1 ラウンドで通せていた内容。レビュー往復のコストを下げるため、計画 PR は実装 PR より丁寧に整合性を取る。

**How to apply:** `Docs/` 配下の計画系ドキュメントを書くとき。タスク表・設計指針（疑似コード含む）・ファイル配置・進捗表の **4 箇所を 1 セット**として常に整合性を確認する。実装制約に関する記述は、書く前に必要なら一度コードや Qt ドキュメントを確認してから書く。

関連：[[feedback-docs-style]] / PR ワークフローは [CLAUDE.md](../../CLAUDE.md)「Codex 連携 / PR ワークフロー」
