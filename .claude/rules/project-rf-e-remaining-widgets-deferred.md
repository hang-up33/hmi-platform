Task RF-E（Editor/Simulator の delegate 重複を Shared/Widgets へ集約）は、Button / Label / SimpleButton の3種（表示専用 + binding 読取のみ）を対象に方式 (a)（型別ホスト QML：`ButtonHost.qml` / `LabelHost.qml` / `SimpleButtonHost.qml`）で実装した（PR #178）。**NumericField（読み書き両用 binding）/ Trend・Meter（読み取り binding は `boundValue("value")` で持つが、系列・目盛りなど多プロパティ）は非対称性の吸収コストが見合わないと判断し対象外**とし、別途後日検討とした（2026-09-20 ユーザー判断）。

## 参考資産：孤立ブランチ `origin/claude/next-what-p9ky05`（コミット `b0b7743`）

2026-08-22 に別セッションが、RF-E を **6種類全部**（Button/Label/NumericField/Trend/Meter/SimpleButton）を1つの統合ホスト `Shared/Widgets/qml/HmiWidgetHost.qml` に集約する形で実装していたが、PR 化されずレビューもされず放置されていた。2026-09-20 に技術検証した結果：

- ビルド・`ctest` はほぼ全緑（30件中1件の一過性フレークのみ、単体再実行で解消。実装側の回帰ではない）
- objectName パス（`widget_<id>/hmiButton` 等）は無傷。E2E（Spix）も通る
- 見た目・ロジックは不変（Loader+6 inline Component → HmiWidgetHost 1個の呼び出しへの機械的置換で、値の渡し方自体は一字一句同じ）
- 設計は妥当：NumericField の read/write 非対称性、Trend の複数系列、SimpleButton の二重トグル回避などの型固有の難所は delegate 側に正しく残置され、ホスト側で無理な一般化をしていない
- **PR #178 の分離型（種別ごとに `XxxHost.qml`）と比較すると、統合型（`HmiWidgetHost.qml` 1本 + `metaValue(jsonKey)` で JSON キー⇄Hmi\* 入力名マッピングを一元化）の方が保守性で優れると評価**（新種別追加時にマッピングを書く箇所が1箇所で済む）
- ただし PR #178 とはツリー構造が異なるため**単純 cherry-pick は不可**

## How to apply（RF-E の残り種別に再着手する時）

1. まずこのメモと [refactoring-plan.md](../../Docs/refactoring-plan.md) の RF-E 行を確認する。
2. 孤立ブランチ `origin/claude/next-what-p9ky05`（`b0b7743`）がまだ存在するか確認し、存在すれば `Shared/Widgets/qml/HmiWidgetHost.qml` と `Shared/Widgets/tests/tst_hmi_widget_host.qml` を参考実装として読む価値が高い（特に NumericField/Trend の非対称性吸収パターン）。
3. ユーザーと設計方針を選び直す：(a) PR #178 の分離型パターンに合わせて `NumericFieldHost.qml` / `TrendHost.qml` / `MeterHost.qml` を新規に書く、(b) 統合型 `HmiWidgetHost` パターンを採用し、Button/Label/SimpleButton もそちらへ吸収し直す。どちらも再実装（現行 main への単純適用は不可）が必要な点をユーザーに明示してから着手する。
4. 孤立ブランチ自体は将来の参考のため削除しない（採用しないと決まった場合はユーザー確認の上で削除を検討）。

**Why:** 検証を後から繰り返さないため。孤立実装の存在に気付かず、次回また同じ調査（自己申告の再現性確認・設計評価）をゼロからやり直すコストを避ける。

関連：[[project-widgetmodel-refactor-deferred]]（同種の「保留・再評価条件つき」メモの前例）
