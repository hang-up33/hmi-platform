# CLAUDE.md

このファイルは、本リポジトリで作業する Claude Code（claude.ai/code）への指針です。
**ユーザーは日本人のため、応答・ドキュメント・コミットメッセージは日本語を基本とします**（コード識別子は英語可）。

> **本プロジェクトの開発コードネームは「Atlas（アトラス）」**（プロジェクト全体のブランド別名・開発時の通称）。正式なリポジトリ名・CMake プロジェクト名・QML URI 等は従来どおり（`hmi-platform` / `hmi_*` / `Hmi*`）で、リネームはしない。Atlas はあくまで README 冒頭などで用いる愛称。由来はギリシャ神話で天空を支える巨神アトラス（Editor / Simulator / Runtime / Shared を束ねて支える基盤の含意）。

---

## プロジェクト概要

Yocto / i.MX8M Plus 向け Qt6 HMI ランタイムを対象に、HMI 作画ツール（Editor）・PC 試験環境（Simulator）・実機ランタイム（Runtime）・JSON スキーマ（Shared/Schema）・共有 Widget（Shared/Widgets）を統合した開発基盤。詳細は [README.md](README.md)。タスクごとの時系列まとめ（目的 / PR / 成果物 / 学び）は [Docs/development-history.md](Docs/development-history.md) — 第三者説明用で、タスク完了時に当該 Task のエントリを追記する運用候補。**苦労の多かったタスク／フェーズでは、事実だけでなく「奮闘記」（postmortem）も残す**：障害の連鎖を「どう乗り越えたか・その時の判断と心境」まで物語として `Docs/<phase>-journey.md` に記録する（役割分担＝事実・罠は development-history / dev-environment.md、"どう抜けたか・心境" は奮闘記。初出は [Docs/phase3b-runtime-journey.md](Docs/phase3b-runtime-journey.md)）。**開発環境の現状（ホスト構成・ディスク事情・WSL/Yocto ビルド環境・実機 i.MX8MP の状態）は [.claude/rules/dev-environment.md](.claude/rules/dev-environment.md) に集約**（`.claude/rules/` は git 管理＋毎セッション自動読込される Claude Code のメモリ機構。Claude の自動メモリ `~/.claude/projects/.../memory/` はマシンローカルで Windows ↔ Mac を跨がないため、マシン横断の環境知識はこちらを正とする）。

**現在のフェーズ**：**Phase 9 / OPC-UA クライアント着手中（2026-06-20 選択）。** Modbus（Phase 7）の「変数ソース」抽象に proto 2 本目を足し、`OpcUaController`（`QOpcUaClient` + MonitoredItem 購読 + 書込/接続状態/自動再接続）を Simulator 共有ソース（→Runtime 継承）に置く。Editor は `Qt6::OpcUa` 非リンク。**OP-1〔Schema + Editor UI〕#140 ／OP-2〔PC 読込/購読〕／OP-4〔書込 + 接続状態 + 自動再接続〕完了**（macOS ローカル：unit 13/13 + asyncua E2E `e2e_opcua_read` / `e2e_opcua_write` round-trip 緑。検証は `bash scripts/opcua/run-local-check.sh`）。**🔴 Qt OpcUa は aqtinstall 非同梱＝Web/CI 不可。macOS は qtopcua を Homebrew Qt にソースビルドでマージして解消済み**（手順・罠は [.claude/rules/dev-environment.md](.claude/rules/dev-environment.md)。Windows 母艦 / 実機 rootfs は別途未導入）。**次＝OP-3〔実サーバ読込確認〕/ OP-5〔実サーバ書込確認〕/ OP-6〔実機 Yocto〕＝いずれもローカル（実サーバ / 実機要）。** 進捗の正本は [Docs/phase9-opcua-plan.md](Docs/phase9-opcua-plan.md)「進捗」表。直近完了は Phase 8-B（Trend 拡張・複数系列 + 軸/凡例・PR #138 クローズ）。残る候補（履歴永続化・Gauge / Toggle・NumericField の step/decimals/unit）は引き続き未承認。<br>**Phase 7 / Modbus TCP** は MB-1〜MB-4（書込 + 接続状態 + 自動再接続・書込 E2E `tests/e2e/test_modbus_write.py` 込み・PR #119/#121/#122）完了。残る MB-5〔実 PLC 書込確認〕/ MB-6〔実機 Yocto〕はローカル専用で Web 不可（実 PLC・WSL2/実機が要る）。詳細は [Docs/phase7-modbus-plan.md](Docs/phase7-modbus-plan.md)「進捗」表。**ローカル Windows で Modbus をビルドするには Qt の SerialBus / SerialPort モジュール導入が要る**（[.claude/rules/dev-environment.md](.claude/rules/dev-environment.md)）。

- **完了済み**：Phase 1〜3-B（MVP / テスト基盤 / E2E / Runtime・i.MX8MP 実機描画。Task 1〜24）、**Phase 4 / Button 縦スライス + 拡張**（Task 25〜43。色・フォント・ボーダー・配置・不透明度・状態/アクションを全レイヤ貫通させ「**Widget 追加テンプレ**」を確立、実機アクション動作撮影まで）、**インスペクタ UX 改善**（Task 44〜46。PR #94 / #99）、**Phase 5 / 横展開（Label）**（Task 47〜49 / PR #97・#98・#102。delegate の「型分岐の足場」を導入し横展開テンプレを確立。Label は表示専用＝binding の「読み」のみ）。
- **Phase 6（入力 Widget・NumericField）完了**：[Docs/phase6-input-widget-plan.md](Docs/phase6-input-widget-plan.md)（Task 50〜52）。Label が binding の「読み」だけだったのに対し、NumericField は **読み（表示）+ 書き（入力確定で変数更新）の両用 binding** を担う初の入力 Widget。Simulator write 経路〔`writeBoundValue`〕+ Editor ツールバー「数値入力追加」+ インスペクタ型対応 + cross-app E2E〔`e2e_numeric_input`〕まで完了（int 変数のみ）。
- **Phase 6-B（NumericField 拡張・real 型 + min/max）完了**：[Docs/phase6b-numeric-extend-plan.md](Docs/phase6b-numeric-extend-plan.md)（Task 53〜55）。Phase 6 で保留した real（浮動小数）型と数値範囲を実装する。**real は変数スコープ**（`VariableData.type="real"`、NumericField は bound 変数型から `isReal` 導出）／**min/max は Widget スコープ**（`WidgetData.minValue/maxValue`、**負値が正当なので presence フラグ方式＝数値センチネル不可**）。**Task 53（real 変数型・PR #112）/ 54（数値範囲 min/max・PR #113）/ 55（cross-app E2E〔real typed-write + clamp〕+ スクショ・PR #114）完了＝Phase 6-B クローズ**。**step / decimals / unit / 後続入力 Widget（Gauge / Toggle）/ Phase 7 Modbus は非スコープ＝別承認**（自動着手しない。次フェーズは先にユーザーとスコープ確定）。
- **Phase 6 設計の要点**：write は **既存 `bindings` を読み書き両用に使う**（表示=読み・入力確定=書き）ことで実現し **Schema / C++ ブリッジ無改変**。`HmiNumericField` は Shared/Widgets が初めて QtQuick.Controls（TextField + IntValidator）に依存（import のみ。i.MX8MP rootfs の plugin 同梱は要確認 TODO）。MVP は **int 変数のみ**。Spix は実入力を発火できないため確定は公開メソッド `commitValue()` を `invokeMethod` で模す。
- **Phase 7（Modbus TCP）着手中**：[Docs/phase7-modbus-plan.md](Docs/phase7-modbus-plan.md)。`hmi_simulator`/`hmi_runtime` が **QtSerialBus（`QModbusTcpClient`）で Modbus マスタ**になり PLC レジスタを周期ポーリング/書込→既存の変数ストア + binding 経路へ流す。**通信は Simulator 共有ソース（→Runtime 継承）に置き、Editor は `Qt6::SerialBus` 非リンク**（接続定義を JSON に書くだけ）。MB-1〜2/4 は Web 可（実 PLC は pymodbus ソフトスレーブで E2E）、MB-3/5/6 はローカル。機能バックログ・要求仕様は [Docs/requirements.md](Docs/requirements.md)。
- **進捗の正本 / 詳細**：各 plan の「進捗」表（[phase6](Docs/phase6-input-widget-plan.md) / [phase5](Docs/phase5-widget-expansion-plan.md) / [phase4](Docs/phase4-button-slice-plan.md) / [inspector-ux](Docs/inspector-ux-plan.md)）。**タスクごとの経緯・PR・学びは [development-history.md](Docs/development-history.md)**、環境の現状（CI / Yocto / 実機 / E2E プラットフォーム差）は [.claude/rules/dev-environment.md](.claude/rules/dev-environment.md) と各 skill。**この「現在のフェーズ」には最新ステータスのみ残し、完了タスクの詳細は積まない**（履歴は development-history.md へ。[memory](https://code.claude.com/docs/en/memory) のベストプラクティス）。

---

## コア原則

1. **1 タスクずつ完結** — 設計書のフェーズタスク順（MVP / Phase 2 / Phase 3-A / Phase 3-B …）を厳守し、各タスクは `cmake --build` 成功を完了基準とする。
2. **Shared/Schema が唯一の真実** — Widget / Screen / Project に該当する型・JSON 入出力はここにのみ定義。
3. **継続的改善（kaizen）の遵守** — タスク完了報告の前に、得た知見を CLAUDE.md / README / メモリ / 設定のいずれかに反映する（[kaizen-close](.claude/skills/kaizen-close/SKILL.md) スキルで標準化）。
4. **既存資産の保護** — フォルダ構成変更禁止・既存コード削除禁止（例外は明示されたプレースホルダーのみ）。
5. **計画してから実装** — 複雑なタスクはエージェントに計画させてから手を動かす。

---

## ビルドと実行

全コマンド・既知の罠（macOS AGL / Windows PATH・BOM・exe ロック・deploy / CI aqtinstall）は [qt6-build](.claude/skills/qt6-build/SKILL.md) スキルに集約。要点のみ：

```sh
# macOS（Qt 6.8+ を指す。6.7 以前は macOS 14+ で AGL リンク不可）
cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt
cmake --build build      # 個別: --target hmi_editor / hmi_simulator / hmi_runtime / hmi_schema / hmi_widgets
./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor
```

```powershell
# Windows（Qt 6.11.0 MinGW kit + 付属 MinGW 13.1 + Ninja 前提。MSVC kit 未使用）
.\scripts\windows\build.ps1          # configure+build → build-mingw\ に出力
. .\scripts\windows\setup-env.ps1    # 新シェルは dot-source してから起動
.\build-mingw\hmi_editor.exe
```

`setup-env.ps1` が Qt 付属ツールチェインを PATH 先頭に挿入し VS `cl.exe` / 別 MinGW を回避する。Explorer ダブルクリック起動には `scripts/windows/deploy.ps1`（windeployqt）で DLL 同梱が必要。3 つの exe には Atlas ブランドアイコンが埋め込まれる（`scripts/windows/generate-icon.ps1` で再生成。仕組みの詳細は [qt6-build](.claude/skills/qt6-build/SKILL.md) スキル）。テスト・lint・フォーマッタは未整備。

---

## アーキテクチャ

ルート `CMakeLists.txt` から 4 つのサブプロジェクトを統合：

| モジュール | ターゲット名 | 種類 | URI | 役割 |
|---|---|---|---|---|
| Shared/Schema | `hmi_schema` | STATIC lib | — | プロジェクト JSON の**唯一の真実**。Widget/Screen/Project の型と JSON I/O |
| Shared/Widgets | `hmi_widgets` | QML module | `HmiWidgets` | Editor/Simulator で共有する Widget 部品 |
| Editor | `hmi_editor` | アプリ | `HmiEditor` | 作画アプリ。`loadFromModule("HmiEditor", "Main")` で起動 |
| Simulator | `hmi_simulator` | アプリ | `HmiSimulator` | 読み取り専用の試験アプリ。同じ JSON を描画 |
| Runtime | `hmi_runtime` | アプリ（Simulator のソース共有） | `HmiSimulator`（再利用） | i.MX8MP / Yocto 向け。**Simulator/ のソースを共有して `hmi_runtime` バイナリを生成**（Runtime/ は CMake glue のみ）。Task 22〜24 完了（ホスト PC ビルド + Yocto SDK aarch64 クロスビルド + i.MX8MP 実機描画）。詳細は [Docs/phase3b-runtime-plan.md](Docs/phase3b-runtime-plan.md) |

JSON 入出力は `QJsonDocument`（外部依存なし）。Editor / Simulator の widget リストの現状実装は **QML の `var` 配列ベース**（Task 5 で確立、`widgetModel = widgetModel.concat([...])` で配列丸ごと差し替えて Repeater をリトリガする）。`QAbstractListModel` 化は Phase 3-B スコープ確定後に再評価予定（[.claude/rules/project-widgetmodel-refactor-deferred.md](.claude/rules/project-widgetmodel-refactor-deferred.md) 参照、現状は deferred）。

---

## 利用可能なエージェント

能動的に手を動かす作業は専門エージェントへ委譲する（Agent ツール経由）。

| エージェント | 役割 | 呼ぶタイミング |
|---|---|---|
| [mvp-task-runner](.claude/agents/mvp-task-runner.md) | フェーズタスク（MVP / Phase 2 / Phase 3-A / Phase 3-B …）の次タスクを 1 つだけ実装 | 「次のタスクを進めて」「Task N をやる」 |
| [cmake-build-resolver](.claude/agents/cmake-build-resolver.md) | CMake/Qt ビルドエラー解決 | `cmake --build` 失敗時 |

独立したタスクは並列起動して効率化する。

### コードレビューの担当分け

本プロジェクトの **コードレビューは ChatGPT Codex（GitHub App）** が担当する。Claude 側でレビュー専用エージェント / スキル（読み取り＋指摘のみのもの）は作らない。実装・ビルド修正・ドキュメント更新など **能動的な作業** に限ってエージェント化する。

---

## Codex 連携 / PR ワークフロー

レビューは **Codex GitHub App** が担当。フェーズタスク・docs 変更ともすべて **PR 経由で main に取り込む**（main 直 push 禁止）。Codex 向けの永続指示はリポジトリ直下 [AGENTS.md](AGENTS.md) に書く（`## Review guidelines` で日本語化。**全 PR に効かせたい指示は CLAUDE.md でなく AGENTS.md 側に追記**）。

**ブランチ命名**：フェーズタスク = `task/<N>-<短い名>`（例 `task/2-canvas`）、ドキュメント・設定 = `docs/<短い名>`。1 単位 = 1 ブランチ = 1 PR、原則 main 派生。**例外**：直前 PR が未マージのまま次に着手する時のみ依存ブランチから派生し `gh pr create --base <依存>`（マージ後 `git fetch origin && git rebase --onto main <依存> task/<N>-...` で main へ、`gh pr edit <N> --base main` で base も切替）。

**PR 作成・Codex 自走ループの全手順は [codex-pr](.claude/skills/codex-pr/SKILL.md) スキルに集約**。要点（Must）：

- PR は **ready-for-review**（draft 禁止 — 即レビューさせるため）。タイトル `Task N: <短い説明>`、本文に Summary / 変更点 / Test plan / Codex 向け補足。GUI 変化があれば動作証跡スクショを添付（[screenshot-capture](.claude/skills/screenshot-capture/SKILL.md) スキル）。
- `gh pr create` 直後と修正 push 直後の **両方**で `gh pr comment <N> --body "@codex review"` を投稿（[.claude/rules/feedback-codex-review-comment.md](.claude/rules/feedback-codex-review-comment.md)）。
- Codex レビューを **ユーザー指示を待たず自走でポーリング**し、**指摘 0 件のクリーンレビュー（`Didn't find any major issues. 👍`）まで** 修正→push→再依頼を繰り返す（[.claude/rules/feedback-codex-auto-loop.md](.claude/rules/feedback-codex-auto-loop.md)）。**0 件になって初めて完了報告**する（PR URL 提示だけでは完了扱いしない）。大きな方針差し戻しは新タスク化をユーザーに相談。
- マージは **Squash and merge でユーザーが行う**（Claude はマージしない）。

---

## 利用可能なスキル

| スキル | 用途 |
|---|---|
| [mvp-next-task](.claude/skills/mvp-next-task/SKILL.md) | フェーズタスクの次を進める標準ワークフロー（MVP / Phase 2 / Phase 3-A / Phase 3-B …） |
| [codex-pr](.claude/skills/codex-pr/SKILL.md) | Codex レビュー前提の PR 作成手順 |
| [qt6-build](.claude/skills/qt6-build/SKILL.md) | Qt6 + CMake セットアップ・ビルド手順と既知の罠（macOS AGL / Windows / CI aqtinstall） |
| [e2e-spix](.claude/skills/e2e-spix/SKILL.md) | Spix（E2E）+ AnyRPC 統合・ctest -L e2e の罠と回避策 |
| [screenshot-capture](.claude/skills/screenshot-capture/SKILL.md) | 動作証跡スクショ撮影（macOS / Windows）・PR 埋め込み・README 同期 |
| [hero-demo](.claude/skills/hero-demo/SKILL.md) | README ヒーローをリッチな HMI ダッシュボードに保つ（ショーケース demo の組み立て技法 + 撮影）。新 Widget 種別追加時にデモを育てる |
| [kaizen-close](.claude/skills/kaizen-close/SKILL.md) | タスク完了直前に学びをドキュメントに反映する手順 |
| [progress-summary](.claude/skills/progress-summary/SKILL.md) | 指定期間の実装状況を PR / タスクごとに列挙する（既定は機能だけの簡潔版） |

---

## ルール（Must Always / Must Never）

### Must Always

- **現フェーズのタスク順を守る**：1 タスクずつ（[mvp-next-task](.claude/skills/mvp-next-task/SKILL.md)）進め、**複数フェーズタスクを 1 回でまとめて実装しない**。**未承認フェーズ（「候補」段階）には自動着手せず、先にスコープをユーザーと確定する**。現在地・完了済み・次タスクは上の「現在のフェーズ」節と各 plan の「進捗」表を正とする（経緯は [development-history.md](Docs/development-history.md)）。E2E 検証は macOS / Linux（CI・Web）で実施する（Windows MinGW は E2E 既定 OFF のため緑を満たせない）。
- Widget / Screen / Project 型と JSON I/O は `Shared/Schema` にのみ実装。
- 完了報告の直前に [kaizen-close](.claude/skills/kaizen-close/SKILL.md) を実行し、得た知見を反映する。
- QML モジュール URI とアプリの `loadFromModule()` 引数を一致させる。
- 出力（応答・ドキュメント・コミットメッセージ）は日本語を基本とする。**チャット応答は敬語なし（常体）・3 行以内を基本**とし、やむを得ない時のみ超過する（[.claude/rules/user-response-style.md](.claude/rules/user-response-style.md)）。
- 環境固有の事実（開発ホスト構成・ディスク事情・WSL/Yocto ビルド環境・実機 i.MX8MP の状態・シリアル設定等）が変わったら、[.claude/rules/dev-environment.md](.claude/rules/dev-environment.md) を更新する。これは git 管理＋自動読込される Claude Code のルール（`.claude/rules/`）で、マシンローカルな自動メモリと違い Windows ↔ Mac を跨いで共有されるため、マシン横断で必要な環境知識はここを唯一の真実とする。
- **新しい知見・好み・方針はマシンローカルの自動メモリ（`~/.claude/projects/.../memory/`）ではなく、git 管理＋自動読込される `.claude/rules/` に保存する**（2026-05-30 ユーザー指示）。理由は自動メモリが Windows ↔ Mac を跨がないため。1 知見 = 1 ファイル（小文字＋ハイフン区切り、frontmatter は `name` / `description` / `metadata.type` のみ。`node_type` / `originSessionId` のようなマシンローカル項目は付けない）で配置し、[.claude/rules/memory-index.md](.claude/rules/memory-index.md) に 1 行追記する。**コードの特定領域に紐づく規約は frontmatter に `paths:`（glob）を足して path-scoped rule にし、該当ファイルを編集する時だけロードさせる**（毎セッション常時ロードされる本ファイルや無条件 rule を肥大化させないため。例：[.claude/rules/qml-module-conventions.md](.claude/rules/qml-module-conventions.md) は `paths: ["**/*.qml", ...]`）。**`paths` は規約が言及する全ファイルをカバーすること**：ルート `CMakeLists.txt` の `add_subdirectory` 順序のような cross-cutting な制約を含むなら `**/CMakeLists.txt` も足す（カバー漏れのファイルだけを編集すると、CLAUDE.md 常駐時は常に見えていた注意がロードされず抜ける。PR #55 で Codex 指摘）。ただし CLAUDE.md / `Docs/*.md` に書ける「プロジェクト事実・設計判断」はそちらを正とし、二重メンテを避ける（rules に残すのは作業の進め方・好み等）。
- **CLAUDE.md 本体は < 200 行を保つ**（公式推奨。長いほど常時ロードのコスト増＋遵守率低下）。**複数ステップの手順・特定領域でしか要らない罠は skill（オンデマンド）か path-scoped rule へ出し、CLAUDE.md にはポインタだけ残す**。`@import` はコンテキスト削減にならない（launch 時に全量ロードされる）ため分割手段にしない。常時必要な「always do X」・アーキ表・ビルドコマンド・命名規約だけを本体に置く。

### Must Never

- 複数のフェーズタスク（Phase 1 / Phase 2 / Phase 3）を 1 回で実装する。
- フォルダ構成を変更する（`Editor/ Simulator/ Runtime/ Shared/Schema/ Shared/Widgets/ Docs/` を維持）。
- 既存コードを削除する（例外：後述のプレースホルダー 2 件のみ）。
- qmake その他の代替ビルドシステムを導入する。
- main ブランチに直接 push / コミットする。タスクは必ず `task/<N>-<短い名>` ブランチ + PR で取り込む。
- 設計書未承認のフレームワーク / ライブラリを独断で追加する。
- Claude Code on the web で **Yocto SDK クロスビルド / i.MX8MP 実機描画** を伴う作業を進める（WSL2・実機が要るため不可）。PC ビルド・ユニット・E2E は `Full` ネットワーク + `scripts/web/setup.sh` で Web でも可能（「Claude Code on the web」節 / [Docs/claude-web-dev.md](Docs/claude-web-dev.md) 参照）。

---

## ビルド・E2E・環境の罠（skill / rule に集約）

繰り返し踏む罠は、毎セッション常時ロードされる本ファイルに置かず、手順ごとオンデマンドの skill / 環境 rule に集約した。着手時に該当を開く：

| 領域 | 行き先 |
|---|---|
| Qt6/CMake ビルド・macOS の AGL 罠・Windows（PATH / BOM / exe ロック / deploy）・CI aqtinstall バージョン | [qt6-build](.claude/skills/qt6-build/SKILL.md) スキル |
| Spix（E2E）統合・AnyRPC configure・XML-RPC・offscreen drag・Windows MinGW opt-out・cross-app E2E | [e2e-spix](.claude/skills/e2e-spix/SKILL.md) スキル |
| 動作証跡スクショ撮影・PR 埋め込み・README 同期 | [screenshot-capture](.claude/skills/screenshot-capture/SKILL.md) スキル |
| Yocto / 実機 i.MX8MP / WSL2 の現状 | [.claude/rules/dev-environment.md](.claude/rules/dev-environment.md) |

---

## 削除可能なプレースホルダー（タスク到達時のみ削除）

削除可能なプレースホルダーは現在ありません（`Shared/Schema/src/schema_placeholder.cpp` は Task 3、`Shared/Widgets/qml/Placeholder.qml` は Task 4 で削除済み）。

実ソース追加と同時に対応する `CMakeLists.txt` の `QML_FILES` / ソース一覧を更新し、スタブを削除する。

---

## プロジェクト規約（path-scoped rules）

コードの特定領域に紐づく詳細規約は、該当ファイルを編集する時だけ自動ロードされる **path-scoped rule**（`.claude/rules/` + `paths:` frontmatter）に分割した。毎セッション常時ロードされる本ファイルを肥大化させず、必要な時だけ規約をコンテキストに載せるため（[Claude Code メモリ仕様](https://code.claude.com/docs/ja/memory) 準拠）。

| 規約 | rule ファイル | ロード条件（`paths`） |
|---|---|---|
| Schema 型・JSON I/O 実装規約（struct + namespace、`toJson`/`fromJson`/`isValidJson`） | [.claude/rules/schema-conventions.md](.claude/rules/schema-conventions.md) | `Shared/Schema/**` |
| QML モジュール規約（URI・命名衝突回避・STATIC plugin 共有・EditableWidget の選択/編集/リサイズ結線・C++ ヘルパー公開・Simulator/Runtime ソース共有・ルート CMake の `add_subdirectory` 順序制約） | [.claude/rules/qml-module-conventions.md](.claude/rules/qml-module-conventions.md) | `**/*.qml` / `Editor/**` / `Simulator/**` / `Runtime/**` / `Shared/Widgets/**` / `**/CMakeLists.txt` |
| README スクショ同期（見た目が変わったら `editor.png`/`simulator.png` とキャプションを同コミットで撮り直す。Stop hook `scripts/hooks/check-readme-screenshots.sh` と二段構えで強制） | [.claude/rules/readme-screenshot-sync.md](.claude/rules/readme-screenshot-sync.md) | `**/*.qml` / `Editor/**` / `Simulator/**` / `Runtime/**` / `Shared/Widgets/**` / `README.md` / `Docs/screenshots/**` |

---

## ファイル命名規約

- 小文字 + ハイフン区切り（例：`mvp-task-runner.md`, `qt6-build/SKILL.md`）
- エージェント：`.claude/agents/<name>.md`（YAML frontmatter に `name` `description` `tools` `model`）
- スキル：`.claude/skills/<name>/SKILL.md`（YAML frontmatter に `name` `description` `origin`）
- コミットメッセージ：`Task N: <短い説明>` を基本フォーマットとする

---

## 対象プラットフォーム

開発・動作確認は **macOS と Windows の両方**で実施（Editor / Simulator / Runtime PC ビルドともに GUI 起動確認済み）。**Phase 3-B / Task 22〜24 で 3 バイナリ構成（hmi_editor / hmi_simulator / hmi_runtime）に拡張済み**（Simulator のソースを共有して `hmi_runtime` バイナリを生成）。Task 23（Yocto SDK でのクロスビルド）・Task 24（i.MX8MP 実機 scp + 起動）も完了し、**実機（scarthgap / weston / Qt6 6.8.1）で Editor 由来 JSON の描画を確認済み**。詳細は [Docs/phase3b-runtime-plan.md](Docs/phase3b-runtime-plan.md)。

### Claude Code on the web（条件付きで PC ビルド・テスト可。実機は不可）

かつて「Web 版は非対応」としていたが、**原因は環境の既定ネットワークポリシー `Trusted` が `download.qt.io` を遮断していた点**であり、**ポリシーを `Full`（または `Custom` + `*.qt.io`）にすれば CI と同じ `aqtinstall` で Qt6 を導入でき、Web コンテナ（Ubuntu 24.04）でも `cmake --build` とユニット + E2E（`-platform offscreen`）が通る**ことを実証済み（2026-06-07、Qt 6.10.0 / unit 8 + e2e 5 = 13/13 緑）。GUI ディスプレイは offscreen / vnc で不要。**手順は [Docs/claude-web-dev.md](Docs/claude-web-dev.md)**（`scripts/web/setup.sh` を環境の Setup script に設定 → `scripts/web/session-env.sh` が SessionStart hook で `CMAKE_PREFIX_PATH` を通す）。

- **PC ビルド・ユニット・E2E（macOS 相当）は Web でも可能**になった。
- **GUI スクショも Web で可能**：アプリ内蔵 `--screenshot`（`-platform offscreen` + `QQuickWindow::grabWindow()`、Xvfb 不要）を `scripts/capture-app-screenshot-linux.sh` で叩く（[Docs/claude-web-dev.md](Docs/claude-web-dev.md)「GUI スクショ（ヘッドレス）」）。実機 VNC キャプチャとは別経路。
- ただし **Yocto SDK クロスビルド / i.MX8MP 実機描画は Web では不可**（WSL2 / 実機が要るため従来どおりローカル）。
- かつての遮断理由（記録）：apt の Qt は 6.4.2 止まり、aqtinstall は既定 `Trusted` で Qt ミラーが `host_not_allowed` (HTTP 403) になる。ネットワークを `Full` にするとこれが解消する。
- **前提**：環境ネットワーク = `Full`、Setup script に `bash scripts/web/setup.sh` を設定（初回のみ実行されスナップショットにキャッシュされる）。これらは Web UI でのみ設定でき、人手が必要。
