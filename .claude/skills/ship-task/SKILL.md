---
name: ship-task
description: 実装タスクを「done」まで一気通貫で仕上げる標準オーケストレータ。実装 → ビルド → テスト → kaizen → 進捗ドキュメント同期 → PR 作成 → Codex レビュー自走ループ → クリーン到達で完了報告、までを 1 本の「完了チェックリスト」として束ねる。「実装を完了させて」「タスクを仕上げて」「次を（最後まで）進めて」「PR まで出して」「done まで持っていって」のように、実装を最後まで届ける指示では必ずこの skill を使う（単に「次進めて」でも、完了まで走らせる文脈ならこれ）。個別工程の詳細は mvp-next-task / codex-pr / kaizen-close へ委譲する。Web/リモート（Claude Code on the web）・macOS ローカル・Windows ローカルの環境差もこの skill が吸収するので、環境を意識せず呼べる。
origin: hmi-platform
---

# ship-task — 実装を done まで届けるオーケストレータ

このプロジェクトの「タスクが完了した」は、ローカルでビルドが通ったことではない。**PR を出して Codex のクリーンレビュー（指摘 0 件）まで到達し、進捗ドキュメントが最新化された状態**を指す。本 skill は、実装着手からその状態までの一連の工程を **1 本のチェックリスト** として束ねる。各工程の細かい手順は既存 skill が持っているので、本 skill は「順序・抜け漏れ防止・環境差の吸収」に責任を持ち、詳細はポインタで委譲する。

## いつ使う（When to Use）

- 「実装を完了させて」「タスクを仕上げて」「PR まで出して」「done まで進めて」など、**実装を最後まで届ける**指示のとき。
- 「次のタスクを進めて」「次進めて」でも、**そのまま完了（PR + レビュー）まで走らせてよい文脈**ならこれを使う。実装の 1 歩だけで止めたい（PR を出さない）ことが明らかなら [mvp-next-task](../mvp-next-task/SKILL.md) 単体でよい。
- 既に実装済みで「あとは仕上げて出して」なら、**フェーズ 1（実装）だけ**を飛ばす。**フェーズ 2（ビルド + テスト）は飛ばさない**：`Docs/workflow.md` §1 が `cmake --build` 成功を完了基準にしており、現在の HEAD で一度もビルド/テストしていない変更を PR にすると「検証済み」を誤認する。直前のビルド/テストが**まさにこの HEAD** で緑だと確認できる場合を除き、フェーズ 2 から入って現在の HEAD を検証する。

## なぜオーケストレータが要るか

工程が多く、**忘れやすいのは実装そのものではなく「仕上げ」**（進捗表の同期、スクショ、Codex 自走ループ、クリーン到達前の早すぎる完了報告）だから。過去に「PR を作って URL を貼って終わり」「README 進捗が 1 フェーズ分 stale」「常駐ドキュメントが 11 タスク分古い」といった取りこぼしが繰り返し起きた。1 本の完了ゲートに集約して、報告の直前に必ず全工程を見返す。

## 完了の定義（Definition of Done）— 報告前に必ず自問

以下が **すべて** 満たされて初めて「完了」と報告する。1 つでも欠けたら報告しない。

- [ ] 対象タスクの実装が 1 タスク分きっちり終わっている（「ついで」の混入なし）
- [ ] `cmake --build` 成功、`ctest` 緑（新規テストが実際に走って PASS していることまで確認）
- [ ] **見た目 or GUI 挙動が変わる**タスクなら操作後状態の動作証跡スクショ（D&D・選択・入力反映など静止外観が不変でも撮る）。**恒常外観**が変わったら README ヒーローも同期（どちらも不変なら「不変」と一言）
- [ ] 進捗ドキュメントを **すべて** 同期（plan 進捗表〔正本〕/ README / CLAUDE.md / AGENTS.md / mvp-task-runner / development-history）
- [ ] kaizen（新たな罠・知見）を反映済み
- [ ] PR を ready-for-review で作成し、`@codex review` を投稿
- [ ] Codex（or CodeRabbit）のレビューが **指摘 0 件のクリーン** に到達
- [ ] マージはしていない（squash マージはユーザーの責務）

## フェーズ（順に実行）

### フェーズ 0 — 現在地の確定

- `git fetch` → `git log --oneline origin/main` で **実際の**進捗を確認する。作業ツリーの CLAUDE.md / README は古いことがあり、鵜呑みにすると「次タスク」を誤認する（[dev-environment.md](../../rules/dev-environment.md)「リポジトリ運用の注意」）。**特にリモート/別マシンのセッションはローカルが大きく遅れていることがある**（実例：会話履歴では未着手のタスクが、main では既にマージ済み・後続フェーズまで進行していた）。
- 進捗の正本は [Docs/phase-status.md](../../../Docs/phase-status.md)（全体ステータス）＋各計画書（進行中 `Docs/phase*-plan.md` / 完了済み `Docs/archive/phase*-plan.md`）の「進捗」表（フェーズ詳細）。ここと merge 済みコミットを突き合わせて次タスクを特定する。進捗表自体が更新漏れ（merge 済みなのに「未着手」）のこともあるので、**コミット履歴を最優先**する。**ただし作業ツリーが古い（リモート/別マシン）ときは、判定に使う計画書も古い**：下の基点更新（in-place / 作り直し）を**先に**済ませて最新版で判定するか、更新前に読むなら `git show origin/main:Docs/phase-status.md` と `git show origin/main:Docs/phase-status.md` / `git show origin/main:Docs/<該当>-plan.md`（完了済みは `Docs/archive/` 配下）で**最新版を直接参照**して判定する（古い作業ツリーの計画書だと完了済みタスクの再選択や未承認候補への誤着手を招く）。
- **【Web/リモートの大前提 — 以下のブランチ操作すべてに優先する】使えるブランチはセッション指定の作業ブランチ 1 本だけ。新規ブランチ作成・別ブランチへの切替・別名 push は一切しない。** 下記のブランチ作成系の記述（mvp-next-task の `task/<N>-…`、stacked PR の `checkout -b`、マージ後の別名）は**すべてローカル（macOS/Windows）専用**。Web では「基点を更新する / 派生させる」意図を**指定ブランチに in-place で**適用する（`git merge origin/main` など**通常 push できる**方法）。それが force / 別名なしに不可能なら**独断で進めず中断してユーザーに相談**する（新しい指定ブランチをもらう or `--force-with-lease` を許可してもらう）。以下の各手順の「ブランチを作る / 別名にする」はこの大前提のもとで**ローカルのときだけ**読む。
- **指定作業ブランチの PR が既にマージ済みなら、その PR は再利用しない**。follow-up は最新 origin/main からブランチを作り直して新規 PR にする。マージ済み履歴の上に commit を積まない（マージ済み PR は追跡できない）。**ブランチ名の扱いに注意**：squash マージ後も旧リモートブランチが残っていると、その先端は新 origin/main の祖先でないため、**同名への通常 push は非 fast-forward で拒否され force が要る**（本セッションで実際に踏んだ）。旧リモートブランチが**消えていると確認できたときだけ同名で通常運用**。残っているなら扱いは環境で分ける：**ローカル環境**は新しい固有名の別ブランチにしてよい。**Web/リモートは「指定作業ブランチ以外へ push しない」制約がある**ので、別名へ独断で切り替えない — **新しい指定ブランチをもらうか `--force-with-lease` を許可するかをユーザーに確認して中断**する（下バレットの force-with-lease も要ユーザー確認）。
- **作業ブランチの基点を最新 `origin/main` に更新してから先へ進む**（「あとは仕上げて出して」で実装フェーズを飛ばす依頼でも、この基点更新は必ず行う＝だからフェーズ 0 に置く）。`git fetch` で「ローカルが大きく遅れている」と分かったら、古い基点の上に積まない（既にマージ済みの差分を PR に再混入させたり衝突を起こす。本セッションで実際に踏んだ）。**まだ push していない**なら自由に作り直す：固有の未マージコミットがあれば `git rebase origin/main`、無ければ `git checkout -B <branch> origin/main`。**既に origin へ push 済み**なら、rebase は SHA を書き換えて次の通常 push が非 fast-forward で拒否され、codex-pr が原則禁止する force-push が要る点に注意する — 原則は `git merge origin/main`（履歴を保って通常 push できる）。マージ済み履歴の載せ替え等でどうしても作り直しが要る場合だけ、レビュー開始前に**ユーザー確認のうえ** `git push --force-with-lease`（履歴書き換え＝取り消しにくい操作なので独断で行わない）。
  - **例外：stacked PR（直前 PR が未マージ）のときは `origin/main` へ載せ直さない**。`Docs/workflow.md` は「直前 PR が未マージなら、その依存ブランチから派生し依存ブランチを PR の base にする」運用を認めている。この場合 `origin/main` へ rebase / merge すると依存側コミットや main 側の無関係コミットが PR 差分へ混ざる。現在の PR base を確認し、依存 PR が未マージなら**依存ブランチを基点に保って更新**する。上記の「最新 `origin/main` へ載せ直す」は **main から直接派生するブランチだけ**に適用する。新タスクに着手するとき：**ローカル**は依存ブランチから新タスク用ブランチを作る（`git checkout -b <new> <dep-branch>`＝mvp-next-task の main 起点手順は使わず、PR base も依存ブランチ。1 単位 = 1 ブランチ = 1 PR を保つ）。**Web は上の大前提どおり別名 `checkout -b` を使わず**、指定ブランチを依存ブランチ基点へ in-place 更新する（不可能なら中断して相談）。**stacked PR では PR 作成時の base を依存ブランチにする**（`mcp__github__create_pull_request` の `base` に依存ブランチ名を渡す／ローカルは `gh pr create --base <dep>`）。`main` を base にすると未マージ依存 PR のコミットまで差分に混ざる。
- **未承認フェーズ（「候補」段階）には自動着手しない**。先にスコープをユーザーと確定する。

### フェーズ 1 — 実装（1 タスクだけ）

> ブランチ基点の最新化はフェーズ 0 で済ませておく（「仕上げだけ」でフェーズ 1 を飛ばしても実行されるよう、あちらに置いた）。ここで飛ばしてよいのは **実装作業だけ**。

- 詳細は [mvp-next-task](../mvp-next-task/SKILL.md)。要点：1 タスクずつ / Shared/Schema が唯一の真実 / **フォルダ構成を変更しない・既存コードを削除しない**（既存 Schema・QML・C++ の編集は通常の実装で当然可） / 着手前に影響範囲を箇条書き。
  - **ブランチ作成は環境で分ける**：**Web/リモートはフェーズ 0 で用意した指定作業ブランチをそのまま使い、mvp-next-task の「`main` から `task/<N>-…` を作成」手順は省略する**（環境表のとおり指定ブランチ以外へ push しないため）。**ローカル（macOS/Windows）は mvp-next-task どおり `task/<N>-<短い名>` を作る**。**ただしフェーズ 0 で既に follow-up ブランチ（マージ済み PR の作り直し）や stacked PR の依存派生ブランチを作成/更新済みの場合は、そのブランチをそのまま使い、mvp-next-task の「`main` へ戻って `checkout -b` する」手順は省略する**（`main` 起点で作り直すと、フェーズ 0 で用意したブランチを捨てるか同名で `already exists` になる）。
- 新 Widget 種別など横展開の定番チェック（delegate 型分岐・`renameVariableReferences`・メタ・hero-demo）は [qml-module-conventions](../../rules/qml-module-conventions.md) に集約。該当ファイルを編集すると自動ロードされる。

### フェーズ 2 — ビルド + テスト

- 環境別のコマンドは下の「環境差分」表を見る。**新規テストが実際に走って PASS したか**を、集約 ctest だけでなくテスト名で確認する（緑でも自分のテストが登録漏れ・skip のことがある）。
- ビルド失敗は [cmake-build-resolver](../../agents/cmake-build-resolver.md) エージェントへ委譲してよい。

### フェーズ 3 — 仕上げ（ここが取りこぼしの本体）

1. **証跡スクショ / README ヒーロー同期** — 2 つを分けて判断する（[screenshot-capture](../screenshot-capture/SKILL.md) / [readme-screenshot-sync](../../rules/readme-screenshot-sync.md)）：
   - **タスク固有の動作証跡**：**GUI の「挙動」を変えたら撮る**。ドラッグ&ドロップ・選択・入力反映など、操作後にだけ状態が変わる変更は「静止時の見た目が変わらない」から省略、としてはいけない（`Docs/workflow.md` の GUI 変更時の動作証跡要件）。**操作後の状態**を撮って、変更した操作が実際に成功したことを PR で示す。**offscreen で実 D&D 等を撮れない環境なら、証跡は完了ゲート未達のまま勝手に省略しない** — 撮影可能なローカル / VNC 環境へ引き継ぐか、それが無理なら中断してユーザーに相談する（「代替検証で済ませる」を独自の例外にしない。省略を正式ルールにするなら正本 `Docs/workflow.md` 側の合意が要る＝この skill だけで緩めない）。
   - **README ヒーロー（editor.gif / simulator.png）**：**恒常的な外観**が変わったときだけ撮り直す。挙動だけ変えて静止外観が不変ならヒーローは省略してよい（「恒常外観 不変のため省略」と一言添える。Stop hook のリマインドはブロックではない）。
2. **進捗ドキュメント同期** — [feedback-phase-status-sync](../../rules/feedback-phase-status-sync.md) の同期対象表を全部あたる。正本（plan 進捗表）を更新し、常駐ドキュメント（README / CLAUDE.md / AGENTS.md / mvp-task-runner / development-history）は「短いステータス + ポインタ」に留める（積み増して肥大化させない）。**計画のみの PR でもステータスが動くなら同コミットで同期**（先送りしない）。
3. **kaizen** — [kaizen-close](../kaizen-close/SKILL.md)。今回踏んだ罠・工夫を CLAUDE.md / rules / README / 設定のどこかに 1 か所反映する。コード領域固有の規約は path-scoped rule（`.claude/rules/` + `paths:`）へ。

### フェーズ 4 — PR + Codex 自走ループ

- 手順の本体は [codex-pr](../codex-pr/SKILL.md)。PR は **ready-for-review**（draft 禁止）、タイトル `Task N: <説明>`、本文に Summary / 変更点 / Test plan / Codex 向け補足。
- **PR 作成直後と、修正 push 直後の両方**で `@codex review` を投稿（[feedback-codex-review-comment](../../rules/feedback-codex-review-comment.md)）。
- **指摘 0 件のクリーンレビューまで、ユーザー指示を待たず自走**で「待機 → 判定 → 修正 → **フェーズ 2 を現 HEAD で再実行** → push → 再依頼」を繰り返す（[feedback-codex-auto-loop](../../rules/feedback-codex-auto-loop.md)）。判定は state 優先（`CHANGES_REQUESTED` / inline あり → 修正、`Didn't find any major issues` → 脱出、シグナル無し → まだレビュー中で待機継続）。
- **各修正 push の前に、環境別フェーズ 2（ビルド + テスト）を必ず現在の HEAD で再実行する**。codex-pr の委譲手順はビルドだけを想定しているが、テスト対象の挙動を変える修正だと**ビルドだけでは最終 HEAD のテスト緑を保証できない**。テストを走らせず前回結果を流用すると、最終 HEAD が赤でも完了条件を満たした扱いになる（docs のみ変更のラウンドは再テスト不要だが、その判断は毎回明示する）。
- **判定は必ず「その回の HEAD」に絞る**（旧ラウンドの指摘を再処理したり、過去のクリーン文言で最新レビューを誤終了しないため）。**`HEAD_SHA` / `SINCE` は `@codex review` を送る「直前」に確定する**（送信「後」に取ると、投稿〜取得の隙間に来た Codex 応答の `created_at` が `SINCE` より前になり時刻フィルタから恒久除外され、実はクリーンでも「無反応」と誤判定してループが中断する。codex-pr「ループ前の確定」と同じ）。reviews は `commit_id`、inline は `original_commit_id`（新コミットへ re-anchor される `commit_id` では旧指摘が再マッチする）、issue コメントは投稿時刻（`SINCE` 以降）+ bot 名で絞る。Web の GitHub MCP でも `pull_request_read` の各コメントの `commit_id`/`original_commit_id`、`issue_read` の `created_at` で同様に絞る。詳細は [codex-pr](../codex-pr/SKILL.md)「Codex レビュー自走ループ」の「ループ前の確定」。
- **修正がフェーズ 3 の前提を変えたら、フェーズ 3 の該当項目も再実行する**。フェーズ 2 だけ回してフェーズ 3 を据え置くと、見た目を変える修正で証跡スクショ / README ヒーローが古いまま、タスク範囲や新たな知見が変わったのに進捗の正本 / kaizen が未更新のまま最終ゲートを通ってしまう。各修正の影響（見た目・範囲・学び）を見て該当項目だけ更新し、**完了報告の前に最終 HEAD とスクショ・進捗文書・kaizen の整合を確認する**。
- Codex が利用上限で沈黙したら CodeRabbit のレビューにフォールバックする（[feedback-coderabbit-fallback](../../rules/feedback-coderabbit-fallback.md)）。
- 待機は `sleep` をバックグラウンドで回し、完了通知で再開する（前景の長い sleep はブロックされる）。

### フェーズ 5 — 完了報告（ゲート）

- 上の「完了の定義」を全項目満たしてから報告する。**PR URL を貼っただけ・クリーン未到達での完了報告は禁止**。
- **「ctest 緑」は最終 HEAD の結果であること**を確認する。自走ループで最後に入れた修正の後にフェーズ 2 を回していなければ、完了報告の前にもう一度回す（前回ラウンドの緑を流用しない）。
- 報告には「何ラウンドで指摘を解消したか」を添える（例：Codex 指摘 4 件を 3 ラウンドで解消、最終レビュー指摘なし）。
- 敬語なし・3 行以内が基本（[user-response-style](../../rules/user-response-style.md)）。マージはユーザーが squash で行う旨を添える。

## 環境差分（コマンドはここを見る）

同じオーケストレーションを 3 環境で回す。**まず環境を判定**する（この 3 択で列を選ぶ。「remote 以外＝macOS」と決めつけない — Windows 母艦もローカルにある）：

1. `CLAUDE_CODE_REMOTE=true` → **Web / リモート**（Claude Code on the web）
2. それ以外で OS が macOS（`uname` = Darwin） → **macOS ローカル**
3. それ以外で OS が Windows（PowerShell・`$IsWindows` 等） → **Windows ローカル**

| 工程 | Web / リモート | macOS ローカル | Windows ローカル |
|---|---|---|---|
| Qt / ビルド前提 | `scripts/web/setup.sh`（初回のみ・`Full` ネット）→ `CMAKE_PREFIX_PATH=/opt/Qt/<ver>/gcc_64`（SessionStart hook `session-env.sh` が設定。未設定なら `/opt/hmi-web-qt-prefix` を読む） | `-DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt`（Qt 6.8+。AGL 罠回避は [qt6-build](../qt6-build/SKILL.md)） | Qt 6.11.0 MinGW + Ninja。`. .\scripts\windows\setup-env.ps1`（PATH をドットソースで設定） |
| configure / build | `cmake -S . -B build -DCMAKE_PREFIX_PATH="${CMAKE_PREFIX_PATH:-$(cat /opt/hmi-web-qt-prefix)}" && cmake --build build -j4`（`CMAKE_PREFIX_PATH` は通常 SessionStart hook が export 済みだが、`setup.sh` を手動実行した回はマーカー `/opt/hmi-web-qt-prefix` にしか書かれず親シェルへ export されないので、フォールバックで読む） | `cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt && cmake --build build -j4`（keg-only Homebrew Qt なので `-DCMAKE_PREFIX_PATH` を明示しないと `find_package(Qt6)` が失敗する。[qt6-build](../qt6-build/SKILL.md)） | `.\scripts\windows\build.ps1`（configure+build。再 configure は `-Reconfigure`）。出力は `build-mingw\hmi_*.exe`（`.app` ではない） |
| テスト | `cd build && QT_QPA_PLATFORM=offscreen ctest --output-on-failure`（unit + e2e）。個別確認はテストバイナリを直接叩いてテスト名で PASS 確認 | 同左（offscreen 可） | `ctest --test-dir build-mingw --output-on-failure`（unit）。**ビルド先が `build-mingw` なので必ず `--test-dir` で指す**（リポジトリ直下で素の `ctest` は 0 件 = `Total Tests: 0` でも成功扱いになり未検証を「緑」と誤認する）。実行件数が期待どおり（0 でない）かを確認。**罠：過去に `deploy.ps1` を実行した `build-mingw` を増分再利用すると、配備済み `platforms\qwindows.dll` が Qt 本体の `qoffscreen.dll` を隠して QML テストが失敗/ハングする**（[qt6-build](../qt6-build/SKILL.md) 既知の罠）→ ctest 前に `QT_QPA_PLATFORM_PLUGIN_PATH` を Qt 本体の `plugins\platforms` に向けるか、`build.ps1 -Reconfigure` でクリーンなテスト用ビルドを作る。**E2E は MinGW で既定 OFF**（`CMakeLists.txt` が MINGW 時 `HMI_ENABLE_E2E=OFF`）＝E2E 完了基準のタスクは macOS/Web で回す。GUI exe の起動→終了待ちは `Start-Process -Wait -PassThru` |
| ブランチ | セッション指定の作業ブランチ（例 `claude/<slug>`）へ push。**指定があればそれを厳守**（task/<N>- ではない） | `task/<N>-<短い名>`（[codex-pr](../codex-pr/SKILL.md) 規約） | 同 macOS（`task/<N>-<短い名>`） |
| PR 作成 | GitHub MCP ツール（`mcp__github__create_pull_request`）。`gh` CLI は無い | `gh pr create`（[codex-pr](../codex-pr/SKILL.md)） | 同 macOS（`gh pr create`） |
| `@codex review` | `mcp__github__add_issue_comment`（issue_number = PR 番号） | `gh pr comment <N> --body "@codex review"` | 同 macOS |
| レビュー取得 | `mcp__github__pull_request_read`（`get_reviews` / `get_review_comments`）+ `mcp__github__issue_read`（`get_comments`）。**クリーンは issue コメント、指摘は inline + reviews state** に来る。**必ず現 HEAD に絞って判定する**（下記） | `gh api .../pulls/<N>/reviews` `.../pulls/<N>/comments`（original_commit_id で絞る）`.../issues/<N>/comments?since=` | 同 macOS |
| スクショ | `scripts/capture-app-screenshot-linux.sh`（offscreen + `--screenshot`、Xvfb 不要） | `scripts/capture-app-window.sh <proc> <out.png>`（画面収録権限） | `scripts\windows\capture-app-window.ps1`（詳細は [screenshot-capture](../screenshot-capture/SKILL.md)） |

> Windows 固有の罠（PowerShell の BOM・`$` 変数展開・GUI exe の待受）は [qt6-build](../qt6-build/SKILL.md) と [dev-environment.md](../../rules/dev-environment.md)「Windows 母艦の詳細」を見る。判定した OS に**対応する列が無い / 手順が未整備**なら、無理に別 OS の手順へ流さず中断してユーザーに相談する。

> **Yocto SDK クロスビルド / i.MX8MP 実機描画は Web では不可**（WSL2・実機が要る）。実機工程を含むタスクはローカル（Windows 母艦の WSL2 等）で回す（[CLAUDE.md](../../../CLAUDE.md)・[dev-environment.md](../../rules/dev-environment.md)）。

## 中断してユーザーに相談する例外

自走を止めて相談すべきは、レビューの往復では収束しない類：

- 大規模な方針差し戻し（タスク分割・設計書外ライブラリ導入を要求される）
- Codex が同じ指摘を 3 回連続で返す（修正が意図に合っていない疑い）
- ビルド / テストが赤いまま固着する
- 30 分待っても Codex / CodeRabbit が無反応（GitHub App 障害の疑い）
- 未承認フェーズへの着手を求められている

## やってはいけないこと（Must Never）

- クリーンレビュー未到達で「完了」と報告する（PR URL 提示だけで済ませる）。
- 進捗ドキュメントの同期を「次タスクで」と先送りする（ステータスが動く PR は同コミットで同期）。
- main へ直接 push / コミットする。**Web/リモートではセッション指定の作業ブランチ以外へ push しない**（ローカルは規約どおり作成した `task/<N>-<短い名>` / `docs/<短い名>` ブランチへ push してよい＝この禁止は Web/リモート限定）。
- PR を Claude 側でマージする（squash マージはユーザー）。
- 複数タスクを 1 回でまとめて実装する / `git add -A` で無関係ファイルを巻き込む。

## 例（Example）

```
ユーザー: 次進めて（完了まで）
あなた  : フェーズ0  git fetch → plan 進捗表と merge 済みを突合 → 次タスク = W-D を特定
                    → 作業ブランチを最新 origin/main に更新（push 前なので checkout -B）
         フェーズ1  Canvas/SamplePalette を W-D 分だけ実装（影響範囲を先に列挙）
         フェーズ2  cmake --build → QT_QPA_PLATFORM=offscreen ctest → 26/26 緑
                    （新規テストをテスト名で PASS 確認）
         フェーズ3  D&D は GUI 挙動変更→操作後（ドロップ後）状態のスクショを撮る。
                    恒常外観は不変なので README ヒーローだけ省略を一言 / plan 進捗表 +
                    README + CLAUDE.md + AGENTS.md + mvp-task-runner を同期 / kaizen を rule に追記
         フェーズ4  作業ブランチへ push → MCP で PR 作成 → @codex review
                    → 自走ループ（指摘4件を3ラウンドで解消）→ クリーン到達
         フェーズ5  完了報告（指摘4件を3ラウンドで解消・最終レビュー指摘なし・
                    マージは squash でユーザー）
```
