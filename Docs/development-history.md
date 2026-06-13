# 開発ヒストリー

本リポジトリの開発を **タスク単位の時系列** で俯瞰するためのドキュメント。第三者（新規参加者・レビュアー・関係部署）が「どんな順序でどこまで作ってきたか」を 1 枚で把握できることを目的とする。

- 各 Task は **目的 / PR / 主な成果物 / 学び** の 4 行を基本とする（簡潔さ優先）。
- 詳細な計画・受け入れ基準は `Docs/phase*-plan.md` を参照。罠と回避策は [CLAUDE.md](../CLAUDE.md) に集約。
- 進捗状態（✅ 完了 / ⏳ 未着手）の一覧は [README.md](../README.md#フェーズ進捗) を参照。

## タイムライン俯瞰

```mermaid
timeline
  title HMI Platform 開発タイムライン
  section Phase 1 MVP (Editor / Simulator)
    Task 1 : Qt6 プロジェクト雛形
    Task 2 : キャンバス表示
    Task 3 : Widget データ構造
    Task 4 : Button 配置
    Task 5 : ドラッグ可能化
    Task 6 : JSON 保存
    Task 7 : JSON 読込
    Task 8 : Simulator 表示
  section Phase 2 テスト基盤
    Task 9  : Qt Test 基盤
    Task 10 : Schema JSON I/O テスト
    Task 11 : ファイル I/O テスト
    Task 12 : Qt Quick Test 基盤
    Task 13 : 共有 Widget テスト
    Task 14 : Editor QML テスト
    Task 15 : GitHub Actions CI
  section Phase 3-A E2E テスト導入
    Task 16 : Spix 取り込み
    Task 17 : E2E ハーネス + smoke
    Task 18 : 配置 + 座標反映 E2E
    Task 19 : 保存 → 読込ループ E2E
    Task 20 : Simulator 表示 E2E
    Task 21 : E2E を CI に追加
  section Phase 3-B Runtime / i.MX8MP (完了)
    Task 22 : Runtime CMake glue (完了)
    Task 23 : Yocto SDK クロスビルド (完了)
    Task 24 : 実機描画検証 (完了)
```

---

## Phase 1: MVP — Editor / Simulator の作画 → 保存 → 読込

**目標**：Editor で Widget を配置し、JSON で保存して Simulator が同じ JSON を描画できる最小ループを成立させる。
**計画書**：[phase1-mvp-plan.md](phase1-mvp-plan.md)（2026-05-30 に他フェーズと体裁を揃えて事後整理。Phase 1 は計画書化前に完了したため、本ヒストリーと各 PR を一次情報として遡って作成）

### Task 1: Qt6 プロジェクト雛形

- **目的**：CMake ルートと Editor / Simulator / Shared/Schema / Shared/Widgets の 4 サブプロジェクト構成を立ち上げる。
- **PR**：`f195a0c`（リポジトリ初期化期のため直接コミット、PR 番号なし）
- **成果物**：ルート `CMakeLists.txt`、各サブディレクトリの最小 `qt_add_executable` / `qt_add_qml_module` / `qt_add_library`。
- **学び**：macOS 14+ では同梱 Qt 6.7.0 が `AGL.framework` 不在でリンク不可。Homebrew Qt 6.8+ を `CMAKE_PREFIX_PATH` で指定する運用を確立。

### Task 2: キャンバス表示 ([PR #4](https://github.com/hang-up33/hmi-platform/pull/4))

- **目的**：Editor の中央に 1024×600 の編集領域（`EditorCanvas`）を描画する。
- **成果物**：`EditorCanvas.qml`、`HmiEditor` モジュールの起動経路（`loadFromModule("HmiEditor", "Main")`）。
- **学び**：QtQuick 標準型と同名の QML ファイルは衝突する（`Canvas.qml` 不可）。プレフィックス命名（`EditorCanvas`）で回避。

### Task 3: Widget データ構造定義 ([PR #6](https://github.com/hang-up33/hmi-platform/pull/6))

- **目的**：Widget / Screen / Project の型と JSON I/O を `Shared/Schema` に集約する。
- **成果物**：`hmi::schema::WidgetData` / `ScreenData` / `ProjectData`（struct + namespace スタイル）、各型に `toJson()` / `fromJson()`。
- **学び**：Schema は唯一の真実とし、Q_GADGET / Q_OBJECT は必要になるまで付けない。利用側で検証ロジックが散らないよう、後の Task 7 で `isValidJson()` も Schema 側に集約する設計を確立。

### Task 4: Button 配置 ([PR #7](https://github.com/hang-up33/hmi-platform/pull/7))

- **目的**：「ボタンを追加」操作で Canvas に Button widget を 1 つ生やす。
- **成果物**：`HmiButton.qml`（共有 Widget）、`EditableWidget.qml`、`widgetModel` の概念を導入。
- **学び**：共有 QML モジュール（`HmiWidgets`）は `STATIC` でビルドし利用側で `hmi_widgetsplugin` を直リンクする構成が Qt 6.11 で唯一安定。

### Task 5: ドラッグ可能化 ([PR #10](https://github.com/hang-up33/hmi-platform/pull/10))

- **目的**：配置済み Widget をマウスドラッグで移動可能にする。
- **成果物**：`EditableWidget.qml` の `MouseArea.drag.target` 設定、座標更新を `widgetModel` へ反映。
- **学び**：`var` 配列の `widgetModel` は in-place push でバインディング通知が出ないため、配列ごと差し替え（`concat`）する運用に。これは後の Task 19 E2E で「Repeater 再生成によるバインディング巻き戻し」の罠を呼ぶ伏線になる。

### Task 6: JSON 保存 ([PR #11](https://github.com/hang-up33/hmi-platform/pull/11))

- **目的**：Editor の状態を `ProjectData` に変換し JSON ファイルに保存する。
- **成果物**：`Editor::ProjectIo`（`setContextProperty("projectIo", ...)` で QML 公開）、FileDialog 経由の保存 UI。
- **学び**：`FileDialog.selectedFile` は `file://` 形式の `QUrl` なので `toLocalFile()` で OS パス化。書き込みは `QSaveFile.commit()` で原子的に。

### Task 7: JSON 読込 ([PR #14](https://github.com/hang-up33/hmi-platform/pull/14))

- **目的**：保存済み JSON を Editor で再オープンし状態を復元する。
- **成果物**：`ProjectIo::load()`、`ProjectData::isValidJson()` を含む階層的バリデーション API。
- **学び**：`fromJson()` はキー欠落を既定値で埋める緩い設計のため、読込側は必ず `isValidJson()` を先に通す規約を確立。AppleScript で Qt QML のボタンを自動クリックする手段は事実上ない（後の E2E で Spix 採用の根拠に）。

### Task 8: Simulator 表示 ([PR #16](https://github.com/hang-up33/hmi-platform/pull/16))

- **目的**：Editor が出した JSON を Simulator（読み取り専用）が同じレイアウトで描画する。
- **成果物**：`Simulator::ProjectLoader`、`--open <path>` CLI、`HmiSimulator` モジュール。
- **学び**：起動時自動ロードは `QCommandLineParser` + `setContextProperty("initialJsonUrl", ...)` で軽量に実装可能。Editor と Simulator で同等の load() ロジックが重複するが、責務が違うので Shared に統合せず両方に独立保持する判断を確立。

---

## Phase 2: テスト基盤導入

**目標**：Qt Test（C++ ユニット）・Qt Quick Test（QML 振る舞い）・CI を整備し、退行を機械的に検出できる土台を作る。
**計画書**：[Docs/phase2-testing-plan.md](phase2-testing-plan.md)

### Task 9: Qt Test 基盤構築 ([PR #18](https://github.com/hang-up33/hmi-platform/pull/18))

- **目的**：`ctest` で C++ ユニットテストを走らせる仕組みを入れる。
- **成果物**：ルート `enable_testing()`、`tests/unit/` ディレクトリ、smoke テスト 1 件。
- **学び**：`find_package(Qt6 ... Test)` は `BUILD_TESTING` で条件化（Codex 指摘）。これでテスト無効ビルド時の不要依存を回避。

### Task 10: Schema JSON I/O テスト ([PR #21](https://github.com/hang-up33/hmi-platform/pull/21))

- **目的**：`hmi_schema` の `toJson()` / `fromJson()` / `isValidJson()` をユニットテストで担保。
- **成果物**：`tests/unit/SchemaTest.cpp`、Widget / Screen / Project 3 層分のラウンドトリップテスト。
- **学び**：JSON I/O テストは Schema が唯一の真実である以上、ここで仕様変更の retro 影響を可視化する。

### Task 11: ファイル I/O テスト（ProjectIo / ProjectLoader） ([PR #22](https://github.com/hang-up33/hmi-platform/pull/22))

- **目的**：Editor の保存と Simulator の読込が実ファイル経由で対称であることを保証。
- **成果物**：`ProjectIoTest` / `ProjectLoaderTest`、一時ディレクトリ経由の保存→読込ラウンドトリップ。
- **学び**：FileDialog を介さない API レベルのテストとして整理。「Editor / Simulator の load() は重複を許容」の決定が、ここで両方独立にテストする方針に整合。

### Task 12: Qt Quick Test 基盤構築 ([PR #23](https://github.com/hang-up33/hmi-platform/pull/23))

- **目的**：QML 側の振る舞いを `tst_*.qml` で書ける土台を入れる。
- **成果物**：`tests/quick/` の `qt_add_test` 経路、smoke QML テスト。
- **学び**：`add_test` には `-platform offscreen` を明示（Codex 指摘）。CI / ローカル両環境で display 依存を排除。

### Task 13: 共有 Widget テスト（HmiButton） ([PR #24](https://github.com/hang-up33/hmi-platform/pull/24))

- **目的**：`HmiWidgets` モジュールの最小コンポーネントを QML テストで担保。
- **成果物**：`tst_HmiButton.qml`、`Shared/Widgets` の plugin リンク経路の検証。
- **学び**：共有モジュールを `STATIC` plugin として使う構成がテスト側でも素直に通る（=実アプリと同じリンクパターン）。

### Task 14: Editor QML テスト（Canvas / EditableWidget） ([PR #25](https://github.com/hang-up33/hmi-platform/pull/25))

- **目的**：Editor の Canvas / EditableWidget の生成・配置ロジックを QML テストで担保。
- **成果物**：`tst_EditorCanvas.qml`、Repeater delegate 生成完了の `tryVerify` 待ち。
- **学び**：Repeater delegate は次の event loop で生成されるため `tryVerify` で待つ（Codex P2 Major 指摘）。Task 19 で踏む「再生成によるバインディング巻き戻し」と同根の問題系。

### Task 15: CI 整備（GitHub Actions） ([PR #26](https://github.com/hang-up33/hmi-platform/pull/26))

- **目的**：macOS / Windows の matrix で `cmake --build` と `ctest` を自動実行する。
- **成果物**：`.github/workflows/ci.yml`、`jurplel/install-qt-action@v4` 経由の Qt 6.10.0 インストール、Tools 階層キャッシュ。
- **学び**：CI 用 Qt はローカル開発バージョン（6.11.x）を追従しない方が安定。aqtinstall は最新リリースに mirror 同期遅延があり 6.11.0 で `Failed to locate XML data` で落ちた → 1〜2 マイナー下げた 6.10.0 で安定取得。

---

## Phase 3-A: E2E テスト導入

**目標**：Editor 配置 → JSON 保存 → Simulator 表示までの cross-app 動作を `ctest -L e2e` で自動検証する。
**計画書**：[Docs/phase3-e2e-plan.md](phase3-e2e-plan.md)

### Task 16: Spix 取り込み + Editor / Simulator 統合 ([PR #28](https://github.com/hang-up33/hmi-platform/pull/28))

- **目的**：E2E フレームワーク Spix（OSS / MIT、`faaxm/spix` v0.14）を導入し、`--e2e` フラグで Spix サーバを起動可能にする。
- **成果物**：FetchContent で Spix + AnyRPC を取得、`Editor/src/main.cpp` / `Simulator/src/main.cpp` に `--e2e` / `--e2e-port` を追加（既定 9876 / 9877）。
- **学び**：AnyRPC は upstream 未メンテで罠の宝庫（`CMAKE_POLICY_VERSION_MINIMUM`、`CMAKE_SOURCE_DIR` 誤動作、`SpixCoreTargets` 同梱、MinGW での `std::recursive_mutex` 衝突）。Windows MinGW では `HMI_ENABLE_E2E` 既定 OFF で opt-out 運用。詳細罠リストは [e2e-spix](../.claude/skills/e2e-spix/SKILL.md) スキルへ集約。

### Task 17: E2E ハーネス雛形 + smoke 1 件 ([PR #29](https://github.com/hang-up33/hmi-platform/pull/29))

- **目的**：Python テストランナー（`tests/e2e/harness.py`）と最初の smoke E2E（アプリ起動 → Spix サーバ応答確認）を入れる。
- **成果物**：`harness.py`（`urllib.request` で XML-RPC を直接 POST する実装）、`subprocess` でアプリ起動／終了する contextmanager、smoke ケース 1 件。
- **学び**：Homebrew Python 3.14 の `_pyexpat` が macOS の libexpat と非互換で `xmlrpc.client` が落ちる → urllib + 文字列マッチで回避し全環境で同じ実装を使う。`QT_QPA_PLATFORM=offscreen` を harness 側で `setdefault` し display 非依存。

### Task 18: Editor 配置 + 座標反映 E2E ([PR #30](https://github.com/hang-up33/hmi-platform/pull/30))

- **目的**：Editor を Spix から操作して widget を配置し、座標変更が JSON に乗ることを検証。
- **成果物**：`tests/e2e/test_editor_place.py`、`widget_<id>` objectName 規約、`setStringProperty(path, "x", "<n>")` による座標変更。
- **学び**：Spix の `mouseBeginDrag` / `mouseEndDrag` は item 中央間の drag&drop モデルしか持たず、offscreen 環境では drag 閾値判定にも届かない → 座標変更は `setStringProperty` で代替。実マウスドラッグの検証は Phase 3-B 以降の手動 / 別タスク扱い。

### Task 19: JSON 保存 → 読込ループ E2E ([PR #31](https://github.com/hang-up33/hmi-platform/pull/31))

- **目的**：Editor 配置 → 保存 → 再起動 → 復元のラウンドトリップを E2E 化。
- **成果物**：`Main.qml` の `saveTo(path)` 関数化（FileDialog を介さない E2E ハンドル）、Editor `--open` CLI（Simulator と命名統一）、`invokeMethod` 配列引数対応。
- **学び**：FileDialog は Spix から自動操作不可 → Window 直下に `Q_INVOKABLE` 相当の関数を生やし `invokeMethod` で呼ぶパターンを確立。Repeater 再生成で座標が巻き戻る事故 → 「Repeater サイズ変更 → 全 widget 座標変更」の順序固定で防御。

### Task 20: Simulator 表示 E2E ([PR #32](https://github.com/hang-up33/hmi-platform/pull/32))

- **目的**：Editor が出した JSON を Simulator が起動して描画するまでを cross-app で検証。
- **成果物**：Editor=`hmiEditorWindow` / Simulator=`hmiSimulatorWindow` の objectName 規約、`spix_app` contextmanager を 2 段重ねで順次起動するパターン。
- **学び**：Editor を terminate してから Simulator を起動する設計で「今どちらが落ちたか」のデバッグが容易に。中間 JSON は `tempfile.mkstemp` → finally で `os.unlink`。

### Task 21: E2E ジョブを GitHub Actions に追加 ([PR #33](https://github.com/hang-up33/hmi-platform/pull/33))

- **目的**：`ctest -L e2e` を CI で常時走らせる。
- **成果物**：`.github/workflows/ci.yml` に E2E ステップ追加、`actions/setup-python@v5` の明示インストール。
- **学び**：Windows MinGW では `HMI_ENABLE_E2E=OFF` のため `add_test` 自体が登録されず `ctest -L e2e` は warning で exit 0 → matrix を OS で分けずに 1 ジョブで「macOS は 4 件走る／Windows はスキップ」を両立。

---

## Phase 3-B: Runtime / i.MX8MP 対応

**目標**：Simulator と同じ JSON 描画機能を i.MX8MP 実機（Yocto / Wayland or EGLFS）で動かす Runtime を導入する。
**計画書**：[Docs/phase3b-runtime-plan.md](phase3b-runtime-plan.md)（v2、PR [#37](https://github.com/hang-up33/hmi-platform/pull/37) で策定）
**方針**：Simulator/ のソースを共有して `hmi_runtime` バイナリを生成し、3 バイナリ構成（hmi_editor / hmi_simulator / hmi_runtime）を維持。開発ホストは Windows 母艦 + WSL2 で、Yocto SDK クロスビルドは **WSL2 内**で実施。実機 image が Qt6 非対応（zeus 5.4、2026-05-30 判明）のため、Task 23 は新 BSP（scarthgap）で `imx-image-full` をビルドして実機更新 → 同一 BSP から SDK 生成、に拡張（詳細は計画書 §「実機 image 調査結果と更新方針」）。

### Task 22: Runtime CMake glue ([PR #39](https://github.com/hang-up33/hmi-platform/pull/39))

- **目的**：Simulator の QML module を `STATIC` library 化し、`Runtime/CMakeLists.txt` の glue だけで `hmi_runtime` バイナリをホストビルド可能にする。
- **成果物**：`hmi_simulator_qmlplugin`（STATIC、`Simulator/CMakeLists.txt`）、共通 function `hmi_add_simulator_like_executable`、`Runtime/CMakeLists.txt`（C++ ソースは Simulator/ を `CMAKE_CURRENT_FUNCTION_LIST_DIR` 経由で参照）、ホスト起動スクショ `Docs/screenshots/task-22-runtime-host.png` / `task-22-simulator-host.png`。
- **学び**：Qt の `qt_add_qml_module` を実行ファイル直結にすると別バイナリから共有できない → STATIC plugin + 直リンクが必須（`Shared/Widgets` と同パターン）。C++ ソース共有は CMake 関数 + `CMAKE_CURRENT_FUNCTION_LIST_DIR` でディレクトリを跨いだ参照が成立。Runtime/ には `.cpp` / `.qml` / `.h` を置かない原則を維持。hmi_simulator / hmi_runtime の PC ビルドが同一 JSON で完全一致のレイアウトを描画することを目視確認。

### Task 23: Yocto SDK で hmi_runtime をクロスビルド ([PR #48](https://github.com/hang-up33/hmi-platform/pull/48))

- **目的**：`hmi_runtime` を aarch64 ELF として生成。**前提変更（2026-05-30）**：実機の現行 image が Qt6 非対応（NXP zeus 5.4）と判明したため、WSL2 内で NXP 新 BSP（scarthgap, `imx-6.6.52-2.2.2`）の `imx-image-full` をビルドして実機 image を更新し、同一 BSP から生成した SDK でクロスビルドする。
- **成果物**：[`scripts/yocto/cross-build.sh`](../scripts/yocto/cross-build.sh)（env source → toolchain file 明示渡し → `-DHMI_ENABLE_E2E=OFF -DBUILD_TESTING=OFF` → `--target hmi_runtime` → `file` で aarch64 ELF 検証、を固定）+ [`scripts/yocto/README.md`](../scripts/yocto/README.md)。生成物 `~/build-yocto/Runtime/hmi_runtime`（`ELF 64-bit LSB ... ARM aarch64`、Qt 6.8.1 依存）。
- **学び**：(1) SDK は `imx-image-full -c populate_sdk`（フル SDK）だと ML 系（`onnxruntime-dbg` 692MB）の dpkg 展開で詰まるため、**`bitbake meta-toolchain-qt6`（Qt6 だけの軽量 SDK）に切替**。(2) SDK の env スクリプト名は NXP tune の都合で **`environment-setup-armv8a-poky-linux`**（`aarch64` ではない）。(3) 非対話では cmake alias が効かず toolchain file の明示渡しが必須。(4) `imx-image-full` フルビルドは tmp/work が巨大化するため **`INHERIT += "rm_work"`** で peak を抑制、E ドライブ枯渇は **`diskpart compact vdisk`**（管理者）で回収。(5) **crates.io が wget 既定 UA を 403（CloudFront）で弾く**ため `FETCHCMD_wget` に `--user-agent` を付与。GitHub 並列 fetch のスロットル（git exit 128）は retry で解消。詳細は [.claude/rules/dev-environment.md](../.claude/rules/dev-environment.md)。

### Task 24: i.MX8MP 実機で hmi_runtime を起動し JSON 描画 ([PR #48](https://github.com/hang-up33/hmi-platform/pull/48))

- **目的**：実機に配布し、Editor が出した JSON 形状を実機画面で描画する。
- **成果物**：実機描画の動作証跡 [`Docs/screenshots/task-24-runtime-imx.jpg`](screenshots/task-24-runtime-imx.jpg)（weston 上に「HMI Simulator」ウィンドウ + 3 widget が描画）。`scripts/yocto/README.md` に実機デプロイ手順を記載。
- **学び**：(1) 実機 boot は **microSD（SW4=0011、0010=eMMC）**。(2) `imx-image-full` の sshd は **socket-activated**（`sshd.socket` enabled、`sshd.service` は無い）。(3) 新しい OpenSSH の scp は SFTP 既定で、実機側に sftp-server が無いと失敗 → **`scp -O`**（旧プロトコル）必須。(4) LAN 直結だと **link-local（169.254.x.x）** になり、WSL は NAT 越しで届きにくいので **Windows 母艦から scp** する。(5) weston は **root（uid 0）** で動作、socket は `/run/user/0/wayland-1` → `XDG_RUNTIME_DIR=/run/user/0` `WAYLAND_DISPLAY=wayland-1` `QT_QPA_PLATFORM=wayland` で起動。Runtime は Simulator のソース共有のためウィンドウタイトルは "HMI Simulator" のまま（意図どおり）。

---

## Phase 4: Button 縦スライス（Task 25〜32）+ 拡張（Task 33〜43）

**目標**：Widget 種別を横に増やす前に、Button 1 つを全レイヤ（Schema→Widgets→Editor→Simulator→Runtime→実機）で深く作り込み「Widget 追加テンプレ」を確立する。
**計画書**：[Docs/phase4-button-slice-plan.md](phase4-button-slice-plan.md)（タスク内容・完了基準・進捗の正本）

- **コア縦スライス（Task 25〜32）**：✅ 完了。選択 / インスペクタ / リサイズ / 削除 / スタイル属性（色・フォント・ボーダー・角丸）の全レイヤ貫通・テスト/E2E 拡充・i.MX8MP 実機 styled 描画まで（Task 31〜32 は PR [#64](https://github.com/hang-up33/hmi-platform/pull/64) / [#66](https://github.com/hang-up33/hmi-platform/pull/66)）。
- **拡張（Task 33〜43・2026-06-07 承認）**：✅ 完了（PR #69〜#87 + 実機撮影）。A=フォント詳細 / 配置 / opacity、C=グリッドスナップ / 複数選択・整列 / コピペ / undo-redo、B=変数ストア / アクション編集 / Simulator・Runtime 実行 / 状態別スタイル / アクション round-trip E2E + 実機（i.MX8MP）アクション動作撮影（`vnc-click-capture.py`）。

> 各 Task の詳細エントリ（目的 / 成果物 / 学び）は未追記。タスク別の要点は計画書の「進捗」表セル、状態一覧は [README.md](../README.md#フェーズ進捗) を参照。

---

## インスペクタ UX 改善（Task 44〜46）

**目標**：横展開（新 Widget 種別）で同じ散らかりが各 Widget へ波及する前に、テンプレ＝右側インスペクタを綺麗にしてから増やす。
**計画書**：[Docs/inspector-ux-plan.md](inspector-ux-plan.md)

- **Task 44〜45**：✅ 完了（PR [#94](https://github.com/hang-up33/hmi-platform/pull/94)）。`InspectorSection`（折りたたみヘッダ + Column）を導入し平坦な約 20 項目を 6 セクション（基本 / 文字 / 背景・枠 / 状態 / 動作 / 詳細）＋変数定義へ再編、分かりづらいラベルを言い換え（`チェック可能`→`トグルボタンにする` 等）＋ hover ツールチップ。**スキーマ・round-trip・objectName は不変**で unit 10 + e2e 6 = 16/16 緑。
- **Task 46（任意）**：✅ 完了。背景色 / 文字色 / ボーダー色の hex TextField の隣に **色スウォッチ**（現在色プレビュー。未指定は Widget 種別の resolved 既定色を表示）を追加し、クリックで共有 `ColorDialog` → `#RRGGBB` を live Item + TextField へ書き戻す（明示 beginEdit/commitEdit で 1 件 undo）。手入力欄・objectName は不変。
  - **学び（undo/redo の潜在バグ修正）**：検証中に「色変更 → undo で巻き戻らない」を発見。原因は **同数の配列を `widgetModel` に再代入しても Repeater が既存 delegate を再利用することがあり**、インスペクタの命令的書き込み（`selectedItem.widget* = value`）でバインディングが切れたプロパティへ復元値が届かないこと。undo/redo で **一度空配列を挟んで delegate を確実に全再生成**して修正（Windows の Win32 クリック注入で色変更→undo→redo の round-trip を実証）。tst_canvas の既存 undo テストは JS 配列リテラル由来のモデルで再現せず素通りしていた。

---

## Phase 5: 横展開（新 Widget 種別・最初は Label）

**目標**：Phase 4 で固めたテンプレで Widget 種別を横に増やす。**最初の Widget = Label（文字表示）**。
**計画書**：[Docs/phase5-widget-expansion-plan.md](phase5-widget-expansion-plan.md)（Task 47〜49）

- 🟦 着手（計画起票）。Label は既存スキーマで足りるため **Schema / C++ ブリッジ無改変**で、横展開で唯一新しい **delegate の「型分岐の足場」**（`type` で HmiButton / HmiLabel を描き分ける）を導入する。binding は全 Widget・action は対話 Widget のみ＝**Label は表示専用**。後続 Widget（Lamp / Gauge 等）は Label 完了後に別途承認。
- **Task 47（型分岐の足場 + HmiLabel 描画）完了**（2026-06-11）。
  - **目的**：横展開で唯一新しい「型分岐機構」を最小コストで導入し、後続 Widget の雛形にする。
  - **成果物**：①`Shared/Widgets/qml/HmiLabel.qml`（表示専用 Widget。HmiButton と同じ resolved\* フォールバック方式。**Button と違う既定＝背景透明 / 文字色 #1d3557 / hAlign 左寄せ / ボーダーなし**。選択中継用 `signal clicked(int modifiers)` + MouseArea を持ち、checkable/checked・ボーダー・runClickActions は持たない）②`Shared/Widgets/CMakeLists.txt` の `QML_FILES` に登録 ③Editor `Canvas.qml` / Simulator `SimulatorCanvas.qml` の delegate に **`type` 分岐（`Loader` + inline `Component` の 2 分岐。`type:"Label"`→HmiLabel、それ以外→HmiButton）** を導入。各 Component は外側スコープの `wrapper`(id) 経由でメタへバインドし、clicked を選択要求 / アクションへ中継。Label は binding（text / textColor / backgroundColor / visible）追従のみで click action は非結線（表示専用）④新規 unit：HmiLabel 単体 5 件（resolved 既定・明示値・text 反映・clicked）＋ delegate 型分岐（Editor 3 件＝Button/Label を描き分け・type 切替で追従、Simulator 2 件＝Button/Label を描き分け・Label の text binding 追従）。
  - **完了基準**：`cmake --build` 成功 + Web `ctest`（unit 10 + e2e 6 = 16/16）緑。`type:"Label"` でも EditableWidget の選択枠・リサイズハンドルは効く（wrapper 側の機構で、描く中身に依らない）。**Schema / C++ ブリッジは無改変**（`type` 値域が "Button"/"Label" に増えるだけで JSON 構造・`isValidJson`・round-trip は不変＝旧 JSON 後方互換）。
  - **学び**：Loader が loaded item の `parent` を Loader 自身に設定するため、Component 内 root の `anchors.fill: parent` がそのまま container 全面へ追従する。inline Component は定義位置の外側 id（`wrapper`）を捕捉できるため、従来 HmiButton をインライン結線していたパターンと同形のまま型分岐へ移行できた。次は **Task 48**（Editor の Label 追加 UI + インスペクタ型対応）。
- **Task 48（Editor で Label 作成 + インスペクタの型対応）完了**（2026-06-11）。
  - **目的**：横展開で増えた Widget 種別（Label）を Editor 上で作成でき、インスペクタを選択 Widget の種別に合わせて出し分ける（テンプレ＝インスペクタを型対応へ拡張）。
  - **成果物**：①Editor `Canvas.qml` の `addWidget()` を **`addWidget(type)`** へ一般化（省略時は後方互換で Button。Label は既定文字 "Label"・背景未指定＝HmiLabel が透明にフォールバック）②ツールバーに「ラベル追加」ボタン（objectName `addLabelButton`）を追加し、既存「追加」を「ボタン追加」へ明確化（objectName `addWidgetButton`・挙動〔Button 追加〕は据え置き＝既存 E2E 互換）③`Main.qml` に `readonly property bool selectedIsLabel`（= `canvas.selectedItem.widgetType === "Label"`）を足し、Label 選択時に**インスペクタの無関係セクション / 項目を `visible` で隠す**（状態セクション全体・クリックアクション編集〔見出し/操作/対象変数/値/区切り線〕・ボーダー色/太さ/角丸を非表示。背景色・不透明度・**バインディング編集**・基本・文字・詳細は表示）④新規 unit（Canvas）：`addWidget()` 既定 Button / `addWidget("Label")` で Label 型 + HmiLabel 描画 + 既定文字 "Label" / Label 追加の undo。
  - **完了基準**：`cmake --build` 成功 + Web `ctest`（unit 10 + e2e 6 = 16/16）緑。README `editor.png` を Label 配置シーン（`Docs/samples/task-48-label-demo.json`：Label 3 + Button 2）で撮り直し + キャプション更新（ツールバーの「ボタン追加 / ラベル追加」、Label の透明描画、型対応インスペクタを反映）。**objectName・編集ロジック・Schema は不変＝表示（`visible`）切替のみ**。
  - **学び**：インスペクタの型対応は、セクション / 項目を構造的に分けず**既存の平坦な子へ `visible: !selectedIsLabel` を足すだけ**で実現でき、objectName・2 本立て編集ロジック・round-trip を一切変えずに済んだ（既存 E2E が参照する objectName を温存）。`selectedItem` は単一選択時のみ非 null なので、`selectedIsLabel` は複数 / 未選択で自然に false になり、単一編集フォーム（`selectedItem !== null`）の内側だけで完結する。ヘッドレス `--screenshot` は Widget 選択を伴わないため、型対応インスペクタの「選択時の出し分け」自体は editor.png には写らない（キャンバスの Label 描画 + ツールバーの新ボタンで証跡とし、出し分けは文章で補足）。
- **Task 49（Label round-trip + binding + E2E + simulator.png）完了**（2026-06-12）＝**Phase 5（Label 横展開）クローズ**。
  - **目的**：Label が Editor の保存経路を通って Simulator まで届き `HmiLabel` として描画される（静的 + binding 追従）ことを cross-app E2E で固定し、見た目を `simulator.png` に同期する。
  - **成果物**：①新規 cross-app E2E `tests/e2e/test_label_roundtrip.py`（`e2e_label_roundtrip`、CMake 登録で E2E 6→7 本）。Label 2 件（静的 `lbl_title` + binding `lbl_status`）＋変数を持つ JSON を Editor に `--open`→`saveTo` で round-trip → 保存 JSON を直接 assert（`type:"Label"` / `text` / `textColor` / bindings / variables）→ Simulator を `--open` で起動し `HmiLabel`（objectName `hmiLabel`）の静的描画（text/textColor）と **text バインディングの変数追従**（"BOUND"）を `getStringProperty` で確認。Button 用 test_style_roundtrip / test_action_roundtrip の Label 版。②README `simulator.png` を Label 含むシーン（`Docs/samples/task-48-label-demo.json`）で撮り直し + キャプション更新（Label が Button と並んで描画 / Label も text・textColor・visible を変数バインド可）。
  - **完了基準**：`cmake --build` 成功 + Web `ctest` unit 10 + e2e 7 = 17/17 緑。**Schema / C++ ブリッジは無改変**（Label round-trip は既存 `WidgetData` の往復で成立）。
  - **学び**：Task 47 で delegate に Loader を挟んだが、Spix の objectName パス解決（`widget_<id>/hmiLabel`）は Loader を跨いで子孫に届く（既存 `hmiButton` E2E が Loader 化後も緑だったことで裏付け済み）。Label は表示専用＝クリックアクションを持たないため、E2E は test_action_roundtrip のような実クリック遷移は見ず、**binding の「読み」（変数 → text 追従）だけ**を検証する。これで横展開テンプレ（HmiXxx 新設 → delegate 型分岐 → 追加 UI → インスペクタ型対応 → unit + E2E + スクショ）が 1 周し、後続 Widget は同手順で足せる。

---

## Phase 6: 入力 Widget（最初は NumericField / 数値入力）

**目標**：Phase 5 で確立した横展開テンプレ（型分岐の足場）に乗りつつ、**初めて「ユーザー入力 → 変数へ書き込む（write）」相互作用を持つ入力 Widget** を導入する。**最初の入力 Widget = NumericField（数値入力）**。
**計画書**：[Docs/phase6-input-widget-plan.md](phase6-input-widget-plan.md)（Task 50〜52）

- 🟦 着手（計画起票）。Label が binding の「読み」（変数 → 表示の追従）だけだったのに対し、NumericField は **読み（表示）+ 書き（入力確定で変数更新）の両用 binding** を担う初の入力 Widget。
  - **設計の核**：write は **既存 `bindings` を読み書き両用に使う**（表示=`boundValue("value")` の読み、入力確定=同じ変数へ `setValue(coerce(...))` の書き）ことで実現し、**Schema / C++ ブリッジは無改変**（新キー・新トリガを足さない。後方互換）。`HmiNumericField` は Shared/Widgets が初めて QtQuick.Controls（TextField + IntValidator）に依存する（import のみ。i.MX8MP rootfs の plugin 同梱は要確認 TODO）。MVP は **int 変数のみ**（real 型・min/max は Schema 連鎖するため別承認）。
  - **タスク**：Task 50（型分岐の足場 + HmiNumericField 描画。`editable` で Editor=読取専用 / Simulator=live 編集を出し分け）/ 51（write 経路〔Simulator delegate に `writeBoundValue`〕+ Editor 追加 UI + インスペクタ型対応〔`selectedIsNumericField`〕）/ 52（cross-app E2E `e2e_numeric_input` + スクショ）。
  - **罠（計画段階で織り込み）**：Spix は実テキスト入力（editingFinished）を発火できないため、確定は公開メソッド `commitValue()` を `invokeMethod` で模す。TextField が Editor 選択のフォーカス/入力を奪う問題は `editable:false` + 選択用 MouseArea を上に重ねて回避。binding 表示とユーザー編集の競合（カーソル飛び）は `activeFocus` 中の表示抑止で回避。
- **Task 50（型分岐の足場 + HmiNumericField 描画）完了**（PR #104）：`HmiNumericField.qml`（Controls TextField + IntValidator + resolved\* + `editable` + `commitValue()`/`valueCommitted`）新設、Editor/Simulator delegate に 3 分岐目（`numericComponent`）追加。Task 50 は read-only 表示（両アプリ `editable:false`）で write は未結線。
- **Task 51（write 経路 + Editor 追加 UI + インスペクタ型対応）完了**（本タスク）：
  - **write 経路**：Simulator delegate の wrapper に `boundValue` の書き版 `writeBoundValue(prop, raw)` を追加し、NumericField を `editable:true` に切替え `onValueCommitted` を結線。入力確定で binding `{property:"value"}` の指す変数へ `setValue(coerce(type, text))` 書き戻し → 同変数を読む他 binding（例：追従 Label の `text`）も追従（読み書き両用 binding。Schema/C++ ブリッジ無改変）。binding 無しは no-op。
  - **HmiNumericField**：入力中はユーザー入力で `text: root.text` バインドが切れる → フォーカス喪失時に `Qt.binding` で貼り直して変数の確定値へ表示復帰（編集中は抑止＝カーソル飛び対策、Task 26 パターン）。
  - **Editor UI**：`addWidget` ホワイトリストに `"NumericField"`（既定文字 "0"）、ツールバーに「数値入力追加」（`addNumericButton`）。
  - **インスペクタ**：`selectedIsNumericField` + 派生 `selectedSupportsClickAction`（= Button のみ）で状態・クリックアクションを非表示（背景・枠は表示）、binding プロパティ ComboBox に `"value"` 追加、色スウォッチの fallback を NumericField 既定（背景 #ffffff / 文字 #1d3557）に対応。
  - **テスト**：Simulator に write 追従 + 無 binding no-op の 2 件、Editor に addWidget("NumericField") + undo の 2 件を追加。Web `ctest` unit 10 + e2e 7 = 17/17 緑。`editor.png`/`simulator.png` を NumericField 含むシーン（`Docs/samples/task-51-numeric-demo.json`）へ同期。
  - **Codex レビュー（PR #105）対応 — P2 ×2**：①`HmiNumericField` のフォーカス取得時に `text: root.text` 宣言バインドを**外す**よう修正（編集中に外部 action / 別入力が同変数を更新しても入力中の値が上書きされない。フォーカス喪失で `Qt.binding` 貼り直し＝確定値へ再同期）。②NumericField で「状態」セクションを丸ごと隠すと `enabled:false` を含む JSON を Editor で有効へ戻せず詰むため、**「有効」チェックだけは表示**（トグル/初期オンは Button 専用のまま）。CodeRabbit はクリーン（🎉 No actionable comments）。
  - **次は Task 52**（cross-app E2E `e2e_numeric_input` + スクショ最終同期）。**後続の入力 Widget（Gauge スライダ / Toggle 等）・real 型・数値範囲は未承認＝別途スコープ確定**。

---

## 番外: 開発コードネーム「Atlas」決定（2026-05-30）

フェーズタスクとは別に、プロジェクト全体の**開発時の通称（ブランド別名）**を決めた経緯。

- **きっかけ**：Yocto 5.0 にコードネーム（scarthgap）があることに着想し、本プロジェクトにも愛称を付けるか検討。
- **要件の確定**：対話で次の 4 点に整理 — ①**ブランド名（恒久・1 個）**、②由来のアンカーは**マキャベリ**「積極果敢に行動する者に味方する」（正確にはラテン語 *Audentes Fortuna iuvat* はウェルギリウス由来、マキャベリ『君主論』25 章はその思想を *impeto / virtù* で展開）、③**別名のみ**（リポジトリ名・CMake・QML URI はリネームしない）、④**被り可・開発時のみ**使用（商標/一意性チェックは不要）。
- **候補の遍歴**：マキャベリ軸のラテン/伊語（Audentia → Audax → Audens → Impeto / Virtù）→ 天体・神話系（Impeto / Atlas / Helios / Polaris）→ 4 語の造語（Impelios / Imathelaris 等）→ 最終的に短く据わりの良い **Atlas** に決定。
- **決定**：**Atlas（アトラス）**。由来はギリシャ神話で天空を支える巨神アトラス（Editor / Simulator / Runtime / Shared を**束ねて支える基盤**の含意）。マキャベリ由来からは離れたが、製品の「基盤」性格との比喩適合と語感を優先。
- **成果物**：[README.md](../README.md) 冒頭と [CLAUDE.md](../CLAUDE.md) 冒頭に一文ずつ追記（コミット `69acc83`）。**リネームは一切なし**（`hmi-platform` / `hmi_*` / `Hmi*` は従来どおり）のため CI / Codex 連携スコープ / スクショ URL 等の依存は無傷。
- **学び**：恒久ブランド名は「不可読性」より「読める・呼びやすい・由来を語れる」を優先軸にすべき、という整理に落ち着いた（Yocto 式の“回すコードネーム”とは設計目的が異なる）。被り可・別名運用に割り切ると、一意性検証のコストをかけずに決められる。

---

## 関連ドキュメント

- [README.md](../README.md) — 進捗表（状態のみ）・ビルド手順・スクリーンショット
- [CLAUDE.md](../CLAUDE.md) — Claude Code 向けの作業指針・既知の罠の集約
- [AGENTS.md](../AGENTS.md) — Codex GitHub App 向けのレビュー指針
- [Docs/phase2-testing-plan.md](phase2-testing-plan.md) — Phase 2 計画書
- [Docs/phase3-e2e-plan.md](phase3-e2e-plan.md) — Phase 3-A 計画書
- [Docs/phase3b-runtime-plan.md](phase3b-runtime-plan.md) — Phase 3-B 計画書 v2
- [Docs/phase4-button-slice-plan.md](phase4-button-slice-plan.md) — Phase 4 計画書（コア縦スライス + 拡張）
- [Docs/phase3b-runtime-journey.md](phase3b-runtime-journey.md) — Phase 3-B 奮闘記（Task 23/24 をどう乗り越えたか・心境の記録）
- [Docs/qml-canvas-structure.md](qml-canvas-structure.md) — Canvas.qml の構造解説
