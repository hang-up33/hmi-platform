---
name: project-widgetmodel-refactor-deferred
description: widgetModel の QAbstractListModel 化は Phase 3-B スコープ確定後に再評価する判断（2026-05-27 保留）
metadata: 
  type: project
---

Editor / Simulator の `widgetModel`（QML `var` 配列）を `QAbstractListModel` 派生に置き換える提案を、2026-05-27 に Plan エージェントで 5 PR 規模（Task 22〜26 構想）の計画書を立てた後、目的を見直して **保留** した。計画書（`Docs/phase3a-followup-widgetmodel.md`）も同日削除済み。

**Why:**
- 現状の Editor は MVP 規模（Widget 種別 = Button のみ、想定 widgets 数 10〜20 個）で `var` 配列でも実害が出ていない。
- 当初の動機「Phase 3-B（Runtime / 実機）でデータ量が増えた時にバグるかも」は仮想的な未来要件で、Runtime のスコープ次第で `widgetModel` 構造自体が変わる可能性がある。CLAUDE.md「Don't design for hypothetical future requirements」と整合させる判断。
- Phase 3-A の Spix 罠（「Repeater + var array model で setStringProperty 結果が巻き戻る」）は **テスト内部の規約（順序固定）で閉じている** のでプロダクト動作には影響なし。

**How to apply:**
- 「`widgetModel` をモデル化したい」「Spix 罠節の負債を解消したい」と再び提案 / 着手しようとする場合、**先に「Phase 3-B スコープが確定したか」を確認** する。
- 未確定なら再保留。確定していれば Runtime 側の要件と合わせて設計を立て直す（過去計画書は削除済みなので新規作成）。
- Phase 3-A E2E の順序固定規約は当面残置で問題なし。CLAUDE.md の Spix 罠節バレットも削らない。
- ユーザーが「あり」と即答した提案でも、Plan で規模が見えた時点（数 PR 規模になりそうな時）は **規模を提示して目的を再確認** する（今回はこのステップを踏んで保留に転じた成功事例）。
