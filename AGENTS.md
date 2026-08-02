# AGENTS.md

このファイルは **ChatGPT Codex（GitHub App / Codex CLI）** に対するリポジトリ共通の指示です。

---

## 1. 情報の正本（Single Source of Truth）

本リポジトリの開発指針、アーキテクチャ、タスク進捗、およびルールは以下のドキュメントを正本とします。
レビュー時や作業時には必ず該当ドキュメントを参照してください。

- **レビューガイドライン（詳細・観点）**: [Docs/review-guidelines.md](Docs/review-guidelines.md)
- **現在のフェーズ・タスク進捗**: [Docs/phase-status.md](Docs/phase-status.md)
- **アーキテクチャ・モジュール構造**: [Docs/architecture.md](Docs/architecture.md)
- **開発ワークフロー・開発ルール**: [Docs/workflow.md](Docs/workflow.md)
- **開発経緯・PR 履歴**: [Docs/development-history.md](Docs/development-history.md)

### 言語

- **レビューコメントはすべて日本語で記述してください**（コード識別子・ファイルパス・引用ブロックは英語のままで構いません）。
- PR サマリ・指摘・サジェスト本文・コミット提案など、Codex が生成する全ての自然言語出力を日本語にしてください。

### 指摘の書き方

- 指摘ごとに **「何が」「なぜ問題か」「どう直すべきか」** の 3 点を簡潔に書いてください。
- 該当ファイル・行番号を明示してください（GitHub の suggestion ブロックを使える場合は積極的に使用）。
- 重要度を `[Blocker]` / `[Major]` / `[Minor]` / `[Nit]` のいずれかでラベル付けしてください。

### スコープ

- 本リポジトリは **Phase 4 / Button 縦スライス（Task 25〜32）まで完了**（旧 Phase 4〔Task 25〜30〕＋旧 Phase 5〔Task 31〜32〕を 1 本に統合。Button 1 つを全レイヤ（Schema→Widgets→Editor→Simulator→Runtime→実機）で深く作り込み「Widget 追加テンプレ」を確立。選択・インスペクタ・リサイズ・削除・スタイル属性〔色・フォント・ボーダー・角丸〕の Schema 拡張・テスト/E2E 拡充・i.MX8MP 実機 styled 描画・macOS E2E 緑まで到達。Task 31〜32 マージ済み PR #64 / #66。[CLAUDE.md](CLAUDE.md) の「現在のフェーズ」参照）。続く **Phase 4 拡張（Task 33〜43、2026-06-07 承認）も完了（Task 33〜43 完了 + 実機アクション動作撮影。PR #69〜#87）**（①静的スタイルの続き〔フォント詳細 / 配置 / opacity〕→②編集体験の強化〔グリッドスナップ / 複数選択・整列 / コピペ / undo-redo・Editor のみ〕→③状態 / アクション〔変数ストア + アクション + 状態別スタイル + 実機。全 Widget 横断サブシステムだが Button 駆動・Widget 非依存設計＝トラック B〕の 3 トラック。詳細・進捗の正本は `Docs/phase4-button-slice-plan.md`「Phase 4 拡張」「進捗」）。さらに **インスペクタ UX 改善（Task 44〜46）も完了**（横展開前にテンプレ＝インスペクタをセクション化・整理 + 色入力に色スウォッチ/ColorDialog〔undo/redo の delegate 再利用バグ修正込み〕。PR #94 / #99。`Docs/inspector-ux-plan.md`）。**ここから Phase 5 / 横展開（新 Widget 種別）に着手 — 最初の Widget = Label（承認済み）。** Label は既存スキーマで足りるため **Schema / C++ ブリッジは無改変**で、横展開で唯一新しい **delegate の「型分岐の足場」**（`type` で HmiButton / HmiLabel を描き分ける）を導入する（binding は全 Widget・action は対話 Widget のみ＝Label は表示専用）。**Task 47（型分岐の足場 + HmiLabel 描画）完了**（`HmiLabel.qml` 新設 + Editor/Simulator delegate に `type` 分岐〔Loader + 2 Component〕導入。Schema/C++ ブリッジ無改変）。**Phase 5（Label 横展開）完了（Task 47〜49）**：T47 型分岐の足場 + HmiLabel、T48 Editor で Label 作成 + インスペクタ型対応、T49 round-trip + binding + E2E `e2e_label_roundtrip` + simulator.png（Web `ctest` unit 10 + e2e 7 = 17/17 緑）。タスク分割・進捗の正本は `Docs/phase5-widget-expansion-plan.md`。**続いて Phase 6 / 入力 Widget に着手 — 最初の入力 Widget = NumericField（数値入力・承認済み）。** NumericField は **読み（表示）+ 書き（入力確定で変数更新）の両用 binding** を担う初の入力 Widget で、**既存 `bindings` を読み書き両用に使うため Schema / C++ ブリッジは無改変**（MVP は int 変数のみ。real 型・数値範囲は別承認）。`HmiNumericField` は Shared/Widgets が初めて QtQuick.Controls（TextField + IntValidator）に依存する（import のみ）。**Phase 6（Task 50〜52）完了**（int 変数のみ）— 描画 / Simulator write 経路〔`writeBoundValue`〕/ Editor 追加 UI「数値入力追加」/ インスペクタ型対応 / cross-app E2E〔`e2e_numeric_input`〕。タスク分割・進捗の正本は `Docs/phase6-input-widget-plan.md`。**続いて Phase 6-B / NumericField 拡張（real 型 + 数値範囲 min/max）（承認済み）。** real は変数スコープ（`VariableData.type="real"`、NumericField は bound 変数型から `isReal` 導出 → `DoubleValidator`）、min/max は Widget スコープ（`WidgetData.minValue/maxValue`。**負値が正当なので presence フラグ方式＝数値センチネル禁止**）で確定時に clamp。**Phase 6-B 完了（Task 53 real・PR #112 / 54 min/max・PR #113 / 55 cross-app E2E + スクショ・PR #114）。** タスク分割・進捗の正本は `Docs/phase6b-numeric-extend-plan.md`。**続いて Phase 7 / Modbus TCP 通信に着手（2026-06-16 承認）。** `hmi_simulator`/`hmi_runtime` が QtSerialBus（`QModbusTcpClient`）で Modbus マスタになり PLC レジスタを周期ポーリング/書込→既存の変数ストア + binding 経路へ流す。**通信は Simulator 共有ソース（→Runtime 継承）に置き、Editor は `Qt6::SerialBus` 非リンク**（接続定義を JSON に書くだけ）。**MB-1〔変数ソース Schema（`ConnectionData` + `VariableData.source`）+ Editor 接続編集 UI〕完了（PR #119）。MB-2〔PC 読込ポーリング：`Simulator/src/ModbusController`（`QModbusTcpClient` + `QTimer`）が PLC レジスタを周期読込→`variableUpdated`→`VariableStore.setValue`→既存 binding 経路。Simulator/Runtime のみ `Qt6::SerialBus` リンク・Editor 非リンク〕完了（PR #121）。MB-3〔実 PLC 読込確認〕ローカル達成（2026-06-16：実 AutomationDirect CLICK ＠192.168.1.2 へ接続し holding/coil 読込確認）。MB-4〔書込 + 接続状態 + 自動再接続。書込 E2E `tests/e2e/test_modbus_write.py` 込み〕完了（PR #122）。**MB-1〜MB-4（Web 可）完了、残る MB-5〔実 PLC 書込確認〕/ MB-6〔実機 Yocto〕はローカル専用＝Web 不可。** タスク分割・進捗の正本は `Docs/phase7-modbus-plan.md`「進捗」表。**続いて Phase 8 / トレンドグラフ（Trend・ライブ折れ線）完了（2026-06-16 承認）。** 新 Widget 種別「Trend」を Phase 5/6 の横展開テンプレに乗せた。**描画は QML `Canvas` 自描画で新 Qt モジュール依存ゼロ**（QtCharts 不使用＝i.MX8MP rootfs にそのまま載る）。サンプル源は既存 `bindings` の「読み」を再利用するため **Schema / C++ ブリッジは無改変**。T-A〔Schema 拡張〕/ T-B〔HmiTrend 描画 + 型分岐の足場 4 分岐目〕/ T-C〔Editor 追加 UI + インスペクタ型対応〕/ T-D〔cross-app E2E `e2e_trend_live`〔公開 `sampleCount`/`lastValue` でサンプル取り込みを観測〕+ スクショ〕完了。タスク分割・進捗の正本は `Docs/phase8-trend-plan.md`「進捗」表。**続いて Phase 8-B / Trend 拡張（複数系列 + 軸目盛り/凡例）完了（2026-06-20 クローズ）。** 単系列 Trend を ①複数系列（{変数/線色/凡例ラベル}の `series`）②軸目盛り/凡例（グリッド線・Y 軸目盛りラベル・系列名凡例）へ拡張した。**Phase 8 の「新 Qt モジュール依存ゼロ（QML `Canvas` 自描画のみ）」を維持**し**単系列 JSON は無改変で動く**（後方互換）。8B-A〔Schema 拡張〕#132 ／8B-B〔HmiTrend N 系列描画〕#136 ／8B-C〔軸/凡例描画（既定 OFF）〕／8B-D〔Editor 系列エディタ + 軸/凡例トグル〕／8B-E〔cross-app E2E `e2e_trend_multi` + スクショ〕すべて完了（Web ctest 25/25 緑）。タスク分割・進捗の正本は `Docs/phase8b-trend-extend-plan.md`「進捗」表。**Phase 9 / OPC-UA クライアント完了（2026-06-27 OP-6 クローズ）。OP-1〔#140〕〜OP-6〔実機 Yocto：i.MX8MP で OPC-UA ライブ値を VNC キャプチャで確認〕すべて完了。計画書 `Docs/phase9-opcua-plan.md`。** **現フェーズ＝Phase 10 / メーター（Meter・車のスピードメーター風）完了（M-A〜M-D クローズ）。** 新 Widget 種別「Meter」を横展開テンプレ（Phase 5/6/8）に乗せた。**円弧（アーク）＋針の QML `Canvas` 自描画で新 Qt モジュール依存ゼロ**（Trend と同じく実機 rootfs にそのまま載る）。読み取り専用表示で値源は既存 `bindings` の「読み」を再利用＝**Schema 4 メソッド追加のみで C++ ブリッジ無改変**。M-A〔Schema 拡張〕/ M-B〔HmiMeter 描画 + 型分岐 5 分岐目〕/ M-C〔Editor 追加 UI/インスペクタ〕/ M-D〔cross-app E2E `e2e_meter_live`〔変数変化→針追従を公開 `displayValue`/`needleAngle` で観測〕+ スクショ〕すべて完了（Web `ctest` 26/26 緑）。進捗の正本は `Docs/phase10-meter-plan.md`「進捗」表。**Phase 11 / Widget サンプルパレット（ドラッグ&ドロップ追加）＋ 初号「シンプルボタン」完了（2026-07-12 承認、W-A〜W-E クローズ）。** issue #155「シンプル・イズ・ベスト版 HMI ボタン（ベゼル無し）」を新 Widget 種別 `SimpleButton`（`HmiSimpleButton.qml`）として QML で忠実再現し、**見た目そのままの Widget サンプルをインスペクタに並べてキャンバスへ D&D で追加**する汎用パレット UX を新設した（将来他 Widget もパレット化）。Canvas 自描画で新 Qt 依存ゼロ（Meter/Trend 同方針）。W-A〔Schema 拡張〕/ W-B〔HmiSimpleButton 描画 + delegate 6 分岐目〕/ W-C〔サンプルパレット〕/ W-D〔パレット→キャンバス D&D 追加〕/ W-E〔インスペクタ型対応（シンプルボタン詳細＝形状 / テーマ / 差し色 / 長押し時間。クリックアクションは checked binding 経路へ一本化のため非対応）+ cross-app E2E `e2e_simple_button_live` + スクショ同期〕すべて完了（Web `ctest` 27/27 緑）。**次フェーズは未承認候補から選定（自動着手しない）。** タスク分割（W-A〜W-E）・進捗の正本は `Docs/phase11-widget-palette-plan.md`「進捗」表。残る候補（履歴永続化、step / decimals / unit、後続入力 Widget〔Toggle〕・複数メータースタイル / 色帯・他 Widget のプリセット拡充）は未承認＝先にユーザーとスコープ確定（自動着手しない）。E2E 検証は macOS / Linux（CI・Web）で実施（Windows MinGW は E2E 既定 OFF）。
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

## 2. Review Guidelines 要約

Codex が PR レビューを行う際は、[Docs/review-guidelines.md](Docs/review-guidelines.md) の指示に従ってください。

- **言語**: **レビューコメントはすべて日本語で記述してください**（コード識別子・ファイルパス・引用ブロックは英語可）。
- **指摘フォーマット**: 「何が」「なぜ問題か」「どう直すべきか」の 3 点を明記し、重要度（`[Blocker]` / `[Major]` / `[Minor]` / `[Nit]`）を付けてください。
- **制約事項**: フォルダ構成の変更提案、qmake の導入提案、および現在進行中フェーズを逸脱する大規模リファクタ提案は禁止です。
- **重点観点**:
  - `Shared/Schema` が JSON I/O の唯一の真実であること
  - QML モジュール URI と `loadFromModule()` の一致
  - QtQuick 標準型との QML ファイル命名衝突回避（`Hmi` プレフィックス必須）
  - 共有 QML モジュール (`Shared/Widgets`) の STATIC ビルド構成
  - macOS での Qt バージョン罠（`~/Qt/6.7.0/macos` 指定の禁止）
