# 開発ヒストリー

本リポジトリの開発を **タスク単位の時系列** で俯瞰するためのドキュメント。第三者（新規参加者・レビュアー・関係部署）が「どんな順序でどこまで作ってきたか」を 1 枚で把握できることを目的とする。

- 各 Task は **目的 / PR / 主な成果物 / 学び** の 4 行を基本とする（簡潔さ優先）。
- 詳細な計画・受け入れ基準は計画書（進行中 `Docs/phase*-plan.md` / 完了済み `Docs/archive/phase*-plan.md`）を参照。罠と回避策は [CLAUDE.md](../CLAUDE.md) に集約。
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
**計画書**：[phase1-mvp-plan.md](archive/phase1-mvp-plan.md)（2026-05-30 に他フェーズと体裁を揃えて事後整理。Phase 1 は計画書化前に完了したため、本ヒストリーと各 PR を一次情報として遡って作成）

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
**計画書**：[Docs/archive/phase2-testing-plan.md](archive/phase2-testing-plan.md)

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
**計画書**：[Docs/archive/phase3-e2e-plan.md](archive/phase3-e2e-plan.md)

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
**計画書**：[Docs/archive/phase3b-runtime-plan.md](archive/phase3b-runtime-plan.md)（v2、PR [#37](https://github.com/hang-up33/hmi-platform/pull/37) で策定）
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
**計画書**：[Docs/archive/phase4-button-slice-plan.md](archive/phase4-button-slice-plan.md)（タスク内容・完了基準・進捗の正本）

- **コア縦スライス（Task 25〜32）**：✅ 完了。選択 / インスペクタ / リサイズ / 削除 / スタイル属性（色・フォント・ボーダー・角丸）の全レイヤ貫通・テスト/E2E 拡充・i.MX8MP 実機 styled 描画まで（Task 31〜32 は PR [#64](https://github.com/hang-up33/hmi-platform/pull/64) / [#66](https://github.com/hang-up33/hmi-platform/pull/66)）。
- **拡張（Task 33〜43・2026-06-07 承認）**：✅ 完了（PR #69〜#87 + 実機撮影）。A=フォント詳細 / 配置 / opacity、C=グリッドスナップ / 複数選択・整列 / コピペ / undo-redo、B=変数ストア / アクション編集 / Simulator・Runtime 実行 / 状態別スタイル / アクション round-trip E2E + 実機（i.MX8MP）アクション動作撮影（`vnc-click-capture.py`）。

> 各 Task の詳細エントリ（目的 / 成果物 / 学び）は未追記。タスク別の要点は計画書の「進捗」表セル、状態一覧は [README.md](../README.md#フェーズ進捗) を参照。

---

## インスペクタ UX 改善（Task 44〜46）

**目標**：横展開（新 Widget 種別）で同じ散らかりが各 Widget へ波及する前に、テンプレ＝右側インスペクタを綺麗にしてから増やす。
**計画書**：[Docs/archive/inspector-ux-plan.md](archive/inspector-ux-plan.md)

- **Task 44〜45**：✅ 完了（PR [#94](https://github.com/hang-up33/hmi-platform/pull/94)）。`InspectorSection`（折りたたみヘッダ + Column）を導入し平坦な約 20 項目を 6 セクション（基本 / 文字 / 背景・枠 / 状態 / 動作 / 詳細）＋変数定義へ再編、分かりづらいラベルを言い換え（`チェック可能`→`トグルボタンにする` 等）＋ hover ツールチップ。**スキーマ・round-trip・objectName は不変**で unit 10 + e2e 6 = 16/16 緑。
- **Task 46（任意）**：✅ 完了。背景色 / 文字色 / ボーダー色の hex TextField の隣に **色スウォッチ**（現在色プレビュー。未指定は Widget 種別の resolved 既定色を表示）を追加し、クリックで共有 `ColorDialog` → `#RRGGBB` を live Item + TextField へ書き戻す（明示 beginEdit/commitEdit で 1 件 undo）。手入力欄・objectName は不変。
  - **学び（undo/redo の潜在バグ修正）**：検証中に「色変更 → undo で巻き戻らない」を発見。原因は **同数の配列を `widgetModel` に再代入しても Repeater が既存 delegate を再利用することがあり**、インスペクタの命令的書き込み（`selectedItem.widget* = value`）でバインディングが切れたプロパティへ復元値が届かないこと。undo/redo で **一度空配列を挟んで delegate を確実に全再生成**して修正（Windows の Win32 クリック注入で色変更→undo→redo の round-trip を実証）。tst_canvas の既存 undo テストは JS 配列リテラル由来のモデルで再現せず素通りしていた。

---

## Phase 5: 横展開（新 Widget 種別・最初は Label）

**目標**：Phase 4 で固めたテンプレで Widget 種別を横に増やす。**最初の Widget = Label（文字表示）**。
**計画書**：[Docs/archive/phase5-widget-expansion-plan.md](archive/phase5-widget-expansion-plan.md)（Task 47〜49）

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
**計画書**：[Docs/archive/phase6-input-widget-plan.md](archive/phase6-input-widget-plan.md)（Task 50〜52）

- ✅ 完了（Task 50〜52）。Label が binding の「読み」（変数 → 表示の追従）だけだったのに対し、NumericField は **読み（表示）+ 書き（入力確定で変数更新）の両用 binding** を担う初の入力 Widget。
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
  - **Codex レビュー（PR #105）対応 — P2 ×2**：①`HmiNumericField` のフォーカス取得時に `text: root.text` 宣言バインドを**外す**よう修正（編集中に外部 action / 別入力が同変数を更新しても入力中の値が上書きされない。フォーカス喪失で `Qt.binding` 貼り直し＝確定値へ再同期）。②NumericField で「状態」セクションを丸ごと隠すと `enabled:false` を含む JSON を Editor で有効へ戻せず詰むため、**「有効」チェックだけは表示**（トグル/初期オンは Button 専用のまま）。②の修正で新たに P1（フォーカス喪失時に再バインドが確定より先に走ると旧 root.text へ戻り入力値が失われる）を Codex に指摘され、**確定 + 再バインドを `onEditingFinished`（Enter / blur の単一確定点）へ集約し「commit → 再バインド」の順**に整理（`onActiveFocusChanged` の loss 側では再バインドしない＝Codex 推奨の deferred-rebind。Tab / 別所クリックでの確定でも入力が保存され、commit もちょうど 1 回）。さらに Codex から **ロケール数値**の 2 段指摘（`IntValidator` は既定 locale で桁区切り `1,234` も locale 固有数字 `١٢٣` も受理するが `parseInt` がそれぞれ `1` / `NaN→0` と誤読）→ `commitValue()` で確定値を **IntValidator と同じ `Qt.locale()` で `Number.fromLocaleString` 数値化し ASCII 整数へ正規化**してから emit するよう修正（validator と同一 locale 解釈でどの locale でも整合）。CodeRabbit の nitpick（test init で focusSink リセット）も対応。さらに CodeRabbit から **Enter→blur で `onEditingFinished` が二度発火し `commitValue()` が重複**する軽微指摘 → `_lastCommittedText` による**同一値の二重確定スキップ**（フォーカス取得でクリアし別セッションでは再確定可）で抑止。Codex は途中で利用上限に到達したため、以降は CodeRabbit のレビューにフォールバックして対応した（[[feedback-coderabbit-fallback]]）。
- **Task 52（cross-app E2E〔typed-write〕）完了**（本タスク）＝**Phase 6（NumericField）クローズ**：新規 cross-app E2E `tests/e2e/test_numeric_input.py`（`test_action_roundtrip` テンプレ）を追加。Editor で fixture（`setpoint`(int) 変数 + NumericField〔value binding〕 + 観測用 Label〔text binding〕）を `--open` → `saveTo` で round-trip → 保存 JSON を直接 assert（`type:"NumericField"` / binding `{property:"value"}` / 変数）→ Simulator を `--open` で起動し、**読み**（NumericField と観測用 Label がともに `setpoint=10` に追従）を確認 → **書き**は Spix が `editingFinished` を発火できないため `setStringProperty(num/hmiNumericField, "text", "42")` + 公開メソッド `commitValue()` の `invokeMethod` で確定を模し、`writeBoundValue` で `setpoint=42` に更新 → 観測用 Label が `"42"` へ追従するのを `getStringProperty` で観測。`tests/e2e/CMakeLists.txt` に `e2e_numeric_input`（TIMEOUT 60 / LABELS e2e）を登録。Web `ctest` unit 10 + e2e 8 = **18/18 緑**。スクショは Task 51 で NumericField シーンに同期済みで Task 52 は UI 不変（テスト + CMake のみ）のため再撮影不要。

---

## Phase 6-B: NumericField 拡張（real 型 + 数値範囲 min/max）

**目標**：Phase 6（int 変数のみ）で保留した **real（浮動小数）型**と **数値範囲 min/max** を実装する。
**計画書**：[Docs/archive/phase6b-numeric-extend-plan.md](archive/phase6b-numeric-extend-plan.md)（Task 53〜55。2026-06-13 ユーザー承認）

- ✅ 完了（Task 53〜55）。スコープは 2 軸：**real は変数スコープ**（`VariableData.type="real"` + `VariableStore.coerce("real")`。NumericField は real/int を持たず、**bound 変数の型から `isReal` を導出**して `DoubleValidator` に切替える）／**min/max は Widget スコープ**（`WidgetData.minValue/maxValue`。同じ変数を別 NumericField が別レンジで編集しうるため Widget 固有）。
  - **設計の核（計画段階で確定）**：**min/max は負値が正当なので `-1`/`0` をセンチネルに使えない**（borderWidth/radius との差）→ **presence フラグ方式**（`hasMinValue`/`hasMaxValue` bool ＋ `minValue`/`maxValue` double。JSON はキーの有無で未指定を表す）。範囲外入力は**確定時に clamp**（拒否でなく境界へ丸め）。
  - **タスク**：Task 53（real end-to-end）/ 54（min/max〔Schema presence フラグ + validator/clamp + インスペクタ範囲項目 + delegate〕）/ 55（cross-app E2E〔real typed-write + clamp〕+ スクショ）。
  - **step / decimals / unit / 後続入力 Widget（Gauge / Toggle）は非スコープ＝別承認**。

### Task 53: real 変数型 end-to-end ([PR #112](https://github.com/hang-up33/hmi-platform/pull/112))

- ✅ 完了。`VariableData::isValidJson` に `"real"` を追加 + `VariableStore.coerce("real")`（`Number(raw)`、NaN→0.0）+ Editor 変数定義 ComboBox に `"real"` + `HmiNumericField.isReal`（`DoubleValidator` 切替 + commit を小数保持）+ SimulatorCanvas の `boundVariableType("value")==="real"` で `isReal` 導出。**`WidgetData` 無改変**（real は変数スコープ）。Web `ctest` unit 10 + e2e 8 = **18/18 緑**。
- **学び（real 型 = 文字列正規化と locale の罠）**：int で素通せた箇所が real では破綻し、レビューから計 7 件の指摘を受けた（**Codex 6 件**＝locale 整合・JSON 数値精度・指数表記・表示整形・SimulatorCanvas テスト locale・非有限値、**CodeRabbit 1 件**＝C++ 範囲外キャスト UB。途中で Codex が利用上限に達し CodeRabbit にフォールバック）。要点は **「real の表示値は変数ストアの JS 数値由来で常に ASCII 小数点（C locale）」**という前提に validator・commit・表示・テスト入力をすべて揃えること：
  - `DoubleValidator { locale: "C"; notation: StandardNotation }` + commit を `Qt.locale("C")` でパース（system locale で再パースすると小数点カンマ環境で "36.5" を 365 と誤読し書き戻す）。
  - real 確定値は `String(n)` だと `1e-7` 等の指数表記になり StandardNotation validator と矛盾するため、`_toFixedNotation` で固定小数へ展開（表示テキストにも適用）。
  - JSON 数値 `initial` は `QString::number(d)` の既定 6 桁で丸まるため、**round-trip する最短桁探索**（prec 1→16 + fallback 17）で保持。整数表現化は `std::isfinite` + `std::modf` + `qlonglong` 範囲チェックで UB 回避。
  - real のテスト入力は `Qt.locale().decimalPoint` でなく **ASCII "36.5" 固定**（C locale 実装と整合させ locale 依存の test failure を防ぐ）。
  - 詳細は [.claude/rules/numeric-field-real-locale.md](../.claude/rules/numeric-field-real-locale.md)。

### Task 54: 数値範囲 min/max ([PR #113](https://github.com/hang-up33/hmi-platform/pull/113))

- ✅ 完了。NumericField に入力範囲を Widget スコープで追加。**負値が正当なので数値センチネル不可** → **presence フラグ方式**（`WidgetData.minValue/maxValue`(double) + `hasMinValue/hasMaxValue`(bool)。`toJson` は presence のときだけキーを書く＝後方互換、`fromJson` は `obj.contains()` で presence 判定）。`HmiNumericField` は validator の `bottom`/`top` + 確定時 clamp の二段で範囲を担保（範囲外は拒否でなく境界へ丸め）。Editor インスペクタ「詳細」に範囲 最小値/最大値（NumericField のみ可視、2 本立て、負値・小数可）。Web `ctest` **18/18 緑**。
- **学び**：
  - **clamp の境界は validator と「型に合わせた実効境界」で共通化する**：int は小数境界（min=2.5）を `Math.ceil`/`Math.floor` で整数境界へ丸めてから clamp（生の 2.5 へ clamp 後に整数化すると min 未満の 2 へ落ちる不整合）。`_effectiveBounds()` に集約し commitValue と両 validator で共用。
  - **境界逆転（min > max）は実効境界で swap 正規化する**（CodeRabbit Major）。さもないと clamp が max 側へ押し込み、validator が `bottom > top` になる。
  - **新しいインスペクタ入力欄は `widgetEditFieldFocused` に必ず登録する**（CodeRabbit Major）。漏らすと編集中に Delete ショートカットが誤発火し undo 境界も欠落する。
  - **CodeRabbit の偽陽性 2 件を理由付きで不採用にできた**：①「snapshotModel が JSON I/O＝Schema 集約違反」→ snapshotModel は live QML Item → QVariantMap の**収集**のみで実シリアライズは Schema（既存全フィールド同パターン）。②「`Canvas.qml` 命名衝突」→ Task 2 以来の既存ファイルで `import HmiEditor` 明示で回避済み・全面改名は別タスク。返信で根拠を示し CodeRabbit も了承（Codex 利用上限のため本 PR は CodeRabbit フォールバックでレビュー）。

### Task 55: cross-app E2E（real typed-write + clamp）+ スクショ ([PR #114](https://github.com/hang-up33/hmi-platform/pull/114)) ＝ Phase 6-B クローズ

- ✅ 完了。Phase 6-B の締めとして Task 53（real）/ 54（min/max）の 2 軸を初めて cross-app E2E で観測。`tests/e2e/test_numeric_extend.py` 新設（Phase 6 Task 52 テンプレ踏襲）：Editor で real 変数 + `maxValue` 付き NumericField の fixture を `--open` → `saveTo` round-trip し保存 JSON を直接 assert（`type:"real"` / presence フラグ＝`maxValue` キー有・`minValue` キー無 / value binding）。Simulator で root〔`hmiNumericField`〕に `setStringProperty(text)` + `commitValue()` invoke で確定を模し、**real は "36.5" の小数保持**、max=100 の NumericField は **"150"→clamp で 100** が `writeBoundValue` 経由で変数へ書かれ観測用 Label が追従するのを観測。`e2e_numeric_extend` 登録。Web `ctest` **19/19 緑**（unit 10 + e2e 9）。
- **スクショ**：`editor.png` を範囲項目（インスペクタ「詳細」最小値/最大値）が見える状態へ更新（+ `task-55` 証跡）。`--screenshot` 単体では Widget 未選択でインスペクタが空になるため、**E2E と同じ Spix を流用した使い捨てスクリプト**（「詳細」展開 + NumericField 選択 + ウィンドウ高拡大 → `takeScreenshotAsBase64`、Editor 本体は無改変）で撮影。
- **学び**：①E2E の `commitValue()` は **root（`hmiNumericField`）のメソッド**＝内部 `numericTextField` を指すと確定が走らない（Phase 6 と同じ参照粒度に揃える）。②インスペクタ範囲項目は ScrollView 最下部にあり `contentY` 直接設定が効かない（内部 Flickable に objectName 無し）→ **ウィンドウ高を広げて viewport 拡大**する方が確実。

---

## Phase 7: Modbus TCP 通信（PLC と連動）

**計画書**：[Docs/phase7-modbus-plan.md](phase7-modbus-plan.md)（MB-1〜6。2026-06-16 ユーザー承認で着手）

- ✅ **MB-1〜MB-4（Web 分）完了**（PR #119/#121/#122）。残る MB-5〔実 PLC 書込確認〕/ MB-6〔実機 Runtime 展開〕はローカル専用＝Web 不可。`hmi_simulator`/`hmi_runtime` が **QtSerialBus（`QModbusTcpClient`）で Modbus マスタ**になり PLC レジスタを周期ポーリング/書込→既存の変数ストア + binding 経路へ流す（実務 HMI の核心）。**通信は Simulator 共有ソース（→Runtime 継承）に置き、Editor は `Qt6::SerialBus` 非リンク**（接続定義を JSON に書くだけ）。実 PLC は CI/Web から不達のため自動検証は **pymodbus ソフトスレーブ相手の E2E**、実 PLC/実機確認はローカル。
  - **タスク**：MB-1（変数ソース Schema + Editor 編集 UI・実通信なし・Web 可）/ MB-2（PC 読込ポーリング・pymodbus E2E・Web 可）/ MB-3（実 PLC 読込・ローカル）/ MB-4（書込 + 接続状態・Web 可）/ MB-5（実 PLC 書込・ローカル）/ MB-6（実機 Runtime 展開・WSL2+実機・Web 不可）。

### MB-1: 変数ソース Schema + Editor 編集 UI（実通信なし）

- ✅ 完了（PR #119）。**Schema**：新型 `ConnectionData`（id/proto=modbusTcp/host/port=502/unitId=1）と `SourceData`（connection/reg〔coil/discrete/input/holding〕/address〔0 始まり正準・常時書出〕/poll=1000ms）を追加し、`VariableData` に optional `source`、`ProjectData` に optional `connections[]`（空時省略＝後方互換）を追加（4 メソッド + isValidJson、optional は必須集合に入れない）。**正準 JSON は connections[] 参照方式**（変数の `source.connection` が接続定義 id を参照）で、Editor UI は接続詳細をインライン保持 → `ProjectIo.save` で connections[] へ dedup 集約、`load` で接続詳細を source へ戻して round-trip。**Editor 変数パネル**に「PLC レジスタに割当」CheckBox + host/port/unitId/reg/address/poll 編集欄を追加（全欄を `variableFieldFocusCount` の Delete 抑止に組込み、新規 objectName `variableSource*_<index>` で既存非破壊）。**Editor は `Qt6::SerialBus` 非リンクのまま**。Web `ctest` unit 10/10 緑。
- レビュー（Codex/CodeRabbit）対応：`source` 存在時の内容検証（object + `SourceData::isValidJson`）・空 connection の不正 JSON 書出防止（内部変数へ戻す）・同一 id 重複時の先勝ち + 不一致 qWarning・port/address 範囲検証・load 時の孤立 source qWarning。
- MB-1 の意図的最小化：**接続 id は "plc1" 固定**（複数 PLC 編集 UI は別タスク）。JSON スキーマは複数接続を表現できる connections[] 参照方式を保持。

### MB-2: PC 読込ポーリング（pymodbus ソフトスレーブ E2E）

- ✅ 完了（PR #121）。**Simulator 共有ソース（→Runtime 継承）に `ModbusController`（C++）を新設**：`QModbusTcpClient` + `QTimer` で接続ごとに `connectDevice()`、source 持ち変数ごとに `poll`ms 周期で `sendReadRequest` → `QModbusReply::finished`（UI スレッド・非同期）で値を `variableUpdated(name, value)` emit → QML が `VariableStore.setValue` で既存 binding 経路へ流す（coil/discrete は bool 正規化、holding/input は int）。`Simulator/qml/Main.qml` は読込完了時に `modbusController.configure(connections, variables)` を呼ぶ。**読込のみ**（書込・接続状態 UI・再接続は MB-4）。source 無し変数は無視＝後方互換。
- **CMake**：`find_package(Qt6 ... SerialBus)` は **root `CMakeLists.txt`** に置く（IMPORTED target を hmi_runtime のサブディレクトリスコープからも見えるように）。リンク（`Qt6::SerialBus`）は Simulator の共有 function 内に閉じ、**Editor は非リンク**（`ldd` で 0 確認）。
- **検証**：build 緑 + `ctest` 21/21 緑（unit 11〔新規 `tst_modbus_controller`：reg 文字列→`QModbusDataUnit::RegisterType` 純関数・Qt 標準 `QModbusTcpServer` in-process スレーブで実 PLC 不要〕+ e2e 10〔新規 `e2e_modbus_read`：pymodbus 3.13 ソフトスレーブを `127.0.0.1:15020` で起動 → Simulator の Label が register 値へ追従するのを Spix で観測。pymodbus 不在は skip〕）。
- **環境プロビジョニング**：Web 環境の Qt（aqtinstall）に `qtserialbus`/`qtserialport` が無く pymodbus も未導入だったため、`scripts/web/setup.sh` に両 Qt addon（fresh は `-m`、復元スナップショットは冪等 ensure）+ pymodbus 導入を追加（将来セッションでも自動で揃う）。
- 確認した API：QtSerialBus（`QModbusDevice::Network{Address,Port}Parameter`・`QModbusDataUnit::{Coils,DiscreteInputs,InputRegisters,HoldingRegisters}`・`sendReadRequest(unit, unitId)`）／pymodbus 3.13 は旧 `ModbusSlaveContext`/`ModbusSequentialDataBlock` が deprecated・`setValues` 不動作 → 新 `SimData`/`SimDevice` を `ModbusTcpServer(context=...)` に渡す形が正。
- 学び（kaizen）：[[qml-module-conventions]] に「Simulator 共有 function だけが要る Qt コンポーネントの `find_package` は root に置く（さもないと hmi_runtime だけ moc/include 解決に失敗）」を追記。

### MB-4: 書込 + 接続状態 + 自動再接続（pymodbus write E2E）

- ✅ 完了（PR #122）。**書込**：`ModbusController::writeVariable(name, value)` を追加。configure 時に **coil/holding のみ**を書込写像 `m_writeItems`（name→{connection,reg,address}）へ登録（discrete/input は読取専用＝no-op + 警告）。coil は bool→0/1、holding は int→`quint16` を `sendWriteRequest`。**読込ループ回避**は「経路分離」で実現：読込（`variableUpdated`→`setValue`）由来では書かず、**ユーザー操作の書き経路**（`SimulatorCanvas.writeBoundValue`〔NumericField 確定〕/ `runClickActions` の `setVariable`/`toggleVariable`〔Button アクション〕）が `VariableStore` 更新直後に `writeToPlc`→`writeVariable` を呼ぶ（`SimulatorCanvas` に `plcController` 参照を渡す）。
- **接続状態**：各接続の `stateChanged`/`errorOccurred` を購読し `Q_PROPERTY QVariantMap connectionStates`（id→"connected"/"connecting"/"disconnected"/"error"、`NOTIFY connectionStatesChanged`）で QML へ公開。Simulator の変数パネル内に最小一覧表示（専用 Widget は作らない）。**自動再接続**：`UnconnectedState` 化で固定 4s 間隔の `QTimer`（`scheduleReconnect`）が `connectDevice()` を再試行、成功でタイマ破棄。世代カウンタ（MB-2 既存）で configure/stop 後の旧クライアント・旧 reply・旧再接続タイマを弾く。stop で再接続タイマ片付け + 状態クリア。
- **検証**：build 緑 + `ctest` 22/22 緑（unit 12〔write〔holding/coil が in-process `QModbusTcpServer` で変わる〕・read 専用 reg の no-op・接続状態 "connected" + stop クリア・`isWritableRegister` 純関数を追加〕+ e2e 11〔新規 `e2e_modbus_write`：pymodbus スレーブ相手に NumericField 確定 → `writeVariable` → スレーブの holding が変わるのを別 client で読み返し assert。pymodbus 不在は skip〕）。**Editor は SerialBus 非リンク維持**。
- 意図的最小化：接続状態は最小一覧表示のみ（専用 Widget なし）。int/bool のみ（float/スケーリングは別）。Editor 不変。
- 学び（kaizen）：①QML バインド右辺の self-reference（context property と同名 property に渡すと自分自身=null）→ 受け口を `plcController` に改名。②`hmi_simulator` 単体ビルドでは qmlplugin が更新されず QML テストが古い QML で落ちる → フルビルド必須。③`WriteSingleCoil` の ON は `0xFF00`＝サーバ側 `data()` は 65280 を返す → coil 検証は `!= 0`。

---

## Phase 8: トレンドグラフ（Trend・ライブ折れ線）

**計画書**：[Docs/archive/phase8-trend-plan.md](archive/phase8-trend-plan.md)（T-A〜T-D。2026-06-16 ユーザー要望「トレンドグラフ欲しい」+ スコープ 2 問確定で着手）

- ✅ 完了（T-A〜T-D）。新 Widget 種別「Trend」を Phase 5（Label）/ Phase 6（NumericField）の **横展開テンプレ**（型分岐の足場 + Schema 4 メソッド + インスペクタ型対応 + cross-app E2E）に乗せた。**ライブのみ**（bound 変数を変更時/周期サンプリングしリングバッファに直近 N 点保持、履歴永続化は非スコープ）。**描画は QML `Canvas` 自描画で新 Qt モジュール依存ゼロ**（QtCharts 不使用＝Phase 7 の QtSerialBus 同梱問題を構造的に回避し i.MX8MP rootfs にそのまま載る）。サンプル源は既存 `bindings` の「読み」を再利用するため **Schema / C++ ブリッジは無改変**。Canvas はピクセル不可視のため、E2E は公開プロパティ（`sampleCount`/`lastValue`）でサンプル取り込みを観測する。
  - **タスク**：T-A（Schema 拡張：`type:"Trend"` + `pointCount`/Y軸 min·max〔presence フラグ〕/線色/`sampleMs`・PR #127）/ T-B（`HmiTrend.qml` Canvas 描画 + delegate 4 分岐目・PR #128）/ T-C（Editor 追加 UI + インスペクタ型対応・PR #130）/ T-D（cross-app E2E `tests/e2e/test_trend_live.py`〔`e2e_trend_live`〕+ `simulator.png` ライブ折れ線スクショ）。すべて Web 可。
  - **学び**：Spix の `getStringProperty` は int（`sampleCount`）/ real（`lastValue`）プロパティも QVariant 文字列化で取得でき、Canvas 非可視でも公開プロパティだけで「変数変化 → サンプル取り込み」を観測できる。simulator.png は使い捨て Spix スクリプトで操作用 NumericField を `commitValue()` 連打してサンプルを溜め `takeScreenshotAsBase64` で撮ると、ライブ折れ線が描かれた状態を残せる。Web `ctest` 23/23 緑。

---

## Phase 8-B: Trend 拡張（複数系列 + 軸目盛り/凡例）

**計画書**：[Docs/archive/phase8b-trend-extend-plan.md](archive/phase8b-trend-extend-plan.md)（8B-A〜8B-E。2026-06-17 着手承認＝Phase 8 完了後の候補から「複数系列 + 軸目盛り/凡例」をユーザー選択。履歴永続化は今回非スコープ）

- ✅ 完了（2026-06-20 クローズ）— 8B-A〜8B-E すべて完了（Web `ctest` 25/25 緑）。Phase 8 の単系列 Trend を ①複数系列（子型 `TrendSeriesData {variable, color, label}` の `series` 配列で N 本の折れ線・色分け）②軸目盛り/凡例（グリッド線・Y 軸目盛りラベル・系列名凡例）へ拡張した。**Phase 8 の最重要制約「新 Qt モジュール依存ゼロ（QML `Canvas` 自描画のみ・QtCharts 不使用）」を維持**（グリッド/目盛り/凡例も `Canvas` の `strokeText`/`fillText`/線描）。**Phase 8 の単系列 JSON は無改変で動く**（`series` 空＝既存 `value` バインド + `lineColor` を暗黙 1 系列に合成する後方互換）。
  - **タスク**：8B-A（Schema 拡張：子型 `TrendSeriesData` + `WidgetData.series`/`showGrid`/`showLegend`/`yTickCount`・4 メソッド + round-trip）/ 8B-B（`HmiTrend.qml` を N 系列化〔`_buffers` + `series`/`seriesValues`〕+ Simulator delegate が `VariableStore` から各系列値を供給）/ 8B-C（軸/凡例描画）/ 8B-D（Editor 系列エディタ + 軸/凡例トグル + `editor.png`）/ 8B-E（cross-app E2E〔系列ごと独立サンプリング〕+ スクショ）。すべて Web 可。
  - **8B-A 実装済み（PR #132）**：子型 `TrendSeriesData {variable, color, label}` 新設（4 メソッド + `tst_trend_series_data.cpp`）、`WidgetData` に `series`/`showGrid`/`showLegend`/`yTickCount` を全 optional で追加、Editor の delegate/snapshot/EditableWidget メタ素通し + 変数 rename/削除の `series` 追従。単系列 JSON 無改変回帰を固定。
  - **8B-B 完了（PR #136）**：`HmiTrend.qml` を単一 `_buffer` から系列ごとの `_buffers`（配列の配列）へ一般化。`series`（`[{variable,color,label}]`）+ `seriesValues`（各系列現在値）を入力に取り、系列ごとの色（`series[i].color` 空なら既定パレット `_palette[i%n]`）で N 本 `strokePath`。自動 Y スケールは全系列横断 min/max。**`series` 空のときは従来の `value`/`resolvedLineColor` を暗黙 1 系列として温存（後方互換）**。サンプル取り込みトリガは多系列＝`onSeriesValuesChanged`、単系列＝`onValueChanged`（A/B 二重取り込み防止は継承）。公開テスト API に `seriesCount`/`sampleCountAt(i)`/`lastValueAt(i)`/`bufferSizeAt(i)` を追加（`sampleCount`/`lastValue`/`bufferSize` は系列 0 互換で維持＝既存 unit/E2E を壊さない）。Simulator `SimulatorCanvas.qml` の `trendComponent` が `seriesValues` を `VariableStore.values[...]` から依存追跡式で供給（boundValue 同型）、Editor `Canvas.qml` のプレビューは系列数ぶん位相をずらしたダミー波形を色違いで描く。`tst_hmi_trend.qml` に N 系列の独立取り込み/巻き取り/後方互換テスト 5 件追加。
  - **8B-C 完了**：`HmiTrend.qml` の `Canvas.onPaint` にグリッド線 + Y 軸目盛りラベル（実効 Y 範囲を `resolvedYTickCount` 等分・`0`/負値→既定 4）+ 系列凡例（色スウォッチ + ラベル）を追加。`showGrid`/`showLegend` で描画分岐（既定 OFF＝後方互換）、いずれも `Canvas` 自描画で新 Qt 依存ゼロ維持。レイアウトは派生プロパティに集約（プロット域 `_plotX`/`_plotY`/`_plotWidth`/`_plotHeight`、目盛りラベル域幅 `_axisLabelWidth`=34px、凡例域高さ `_legendHeight`=18px）。凡例ラベルは `series[i].label` 空→変数名→`S<i+1>` フォールバック。`tst_hmi_trend.qml` にピクセル非依存の派生プロパティ assert 6 件追加。
  - **8B-D 完了**：`trendComponent`（Editor/Simulator 両 delegate）が `showGrid`/`showLegend`/`yTickCount` を `HmiTrend` へ供給（8B-A 配線の素通し穴埋め）。Editor インスペクタ「Trend 詳細」に系列エディタ（系列行 = 変数 ComboBox + 線色〔専用 `seriesColorDialog`〕+ 凡例ラベル、追加/削除）と軸/凡例トグル（`showGrid`/`showLegend` チェック + `yTickCount` 入力）を追加。系列は `widgetSeries`（live 配列）を真実に配列丸ごと置換編集（`addSeries`/`removeSeries`/`updateSeries`）。undo 境界は追加/削除=`pushUndo()`・連続編集=フォーカス境界 `beginEdit`/`commitEdit`、動的 TextField は新カウンタ `seriesFieldFocusCount` で undo 算入 + Delete ガード。objectName・編集ロジック・Schema 不変。ショーケース demo を 2 系列 + グリッド + 凡例に拡張し `editor.gif`/`simulator.png` 再撮影。
  - **8B-E 完了（Phase 8-B クローズ）**：`tests/e2e/test_trend_multi.py`（`e2e_trend_multi`）新設。Editor 段で 2 系列 + 凡例 ON の Trend を round-trip 保存し保存 JSON を直接 assert（`series` 2 件・各 variable/color/label・`showGrid`/`showLegend`/`yTickCount`）、Simulator 段で A/B の NumericField を交互確定して各系列変数を独立操作し `sampleCountAt(i)`/`lastValueAt(i)` の独立追従を観測（系列取り違え無しを期待表で担保）。Web `ctest` 25/25 緑。罠：`sampleCountAt`/`lastValueAt` は `invokeMethod` の typed 返り値（AnyRPC が `<value><i4>1</i4></value>` と型タグ付きで返す）なので、既存 E2E の string 専用正規表現では float 変換できず FAIL → `<i4>`/`<int>`/`<double>`/`<boolean>`/`<string>` を剥がすよう値抽出を一般化して解消。

---

## Phase 9: OPC-UA クライアント（完了・OP-1〜OP-6）

**計画書**：[Docs/archive/phase9-opcua-plan.md](archive/phase9-opcua-plan.md)（OP-1〜OP-6。2026-06-20 スコープ選択＝Phase 8-B クローズ後の候補から OPC-UA をユーザー選択。**本タスクは計画書の起票のみ**）

- 📋 計画起票（PR #139）→ 🚧 OP-1 完了（PR #140）→ OP-2 完了（macOS ローカル）→ OP-3 完了（macOS ローカル）→ OP-4 完了（macOS ローカル）。Modbus（Phase 7）で導入した「変数ソース」抽象（`connections[]` + `VariableData.source`）に **proto 2 本目（`opcua`）** を足し、`OpcUaController`（`QOpcUaClient` + MonitoredItem 購読 + 書込/接続状態/自動再接続）を Simulator 共有ソースに置く（→Runtime 継承・Editor は `Qt6::OpcUa` 非リンク）。読込/購読値は `VariableStore.setValue`、書込は MB-4 の二経路分離を流用。
  - **OP-3 完了（macOS ローカル：test_server.py 実サーバ代用での読込追従確認）**：`scripts/opcua/test_server.py`（asyncua ライブ値サーバ：Counter/Temperature/Running/Setpoint の 4 ノードをライブで変化させる）を起動し、`Docs/samples/opcua-demo.json`（同 4 変数を OPC-UA 購読で表示する Label 群）を `hmi_simulator` で開いて OPC-UA 接続→MonitoredItem 購読→Label 追従を肉眼確認。証跡スクショ 2 枚（4 秒差）で Counter 68→98・Temperature 27.47→23.17 の値変化を記録（`Docs/screenshots/op3-read-t1.png` / `op3-read-t2.png`）。コードは OP-2 完了時点のものを使用（新たな実装変更なし）。
  - **OP-4 完了（macOS ローカル：unit 13/13 + asyncua E2E `e2e_opcua_read` / `e2e_opcua_write` round-trip 緑）**：`OpcUaController` を MB-4 と同型で拡張。①**書込**＝`writeVariable(name,value)`→対応ノードの `writeAttribute(Value)`。**QML 由来の数値は QVariant で double 化されサーバの Int32 ノードと型不一致で拒否される罠**があり、`WriteItem.variableType`（変数定義型）に従い OPC-UA 型〔int→Int32 / real→Double / bool→Boolean / string→String〕へ値と型を明示変換してから書く。②**接続状態**＝`Q_PROPERTY QVariantMap connectionStates`（id→connected/connecting/disconnected/error）+ NOTIFY。Main.qml は Modbus / OPC-UA の `connectionStates` をマージ（`connectionStatesAll`）して接続状態セクションに proto 横断で一覧表示。③**自動再接続**＝discovery を `startDiscovery` へ切出し、`stateChanged` の Disconnected で `scheduleReconnect`（`kReconnectIntervalMs`）、Connected で再接続タイマ停止 + 購読開始。世代カウンタで configure/stop 後の旧接続・旧タイマ・旧コールバックを弾く。SimulatorCanvas は `opcController`（self-reference 回避で別名受け）を足し `writeToPlc` で Modbus / OPC-UA 両 controller に投げる（対応 source を持たない変数では各 controller が no-op＝読込ループ回避）。unit `tst_opcua_controller` に接続状態公開 / write 安全性〔未知・未接続・stop 後〕/ stop クリアを追加。書込 E2E `tests/e2e/test_opcua_write.py`（`opcua_server.py --writable` の `ns=2;s=Setpoint` へ HMI commit→`OpcUaController.writeVariable`→書込→別 asyncua client で読み返し検証）。検証は `bash scripts/opcua/run-local-check.sh`（read + write E2E を回す。両方 OK=0 / 片方 FAIL=1 / 両方 SKIP=77）。Editor 非リンクは `otool -L` で確認。
  - **OP-2 完了（macOS ローカル：unit 13/13 + asyncua E2E `e2e_opcua_read` round-trip 緑）**：`Simulator/src/OpcUaController`（`QOpcUaClient` を `QOpcUaProvider` で生成 → `requestEndpoints` → `endpointsRequestFinished` で securityPolicy None を優先選択 → `connectToEndpoint` → `Connected` でノード生成 + `dataChangeOccurred` を `variableUpdated(name,value)` で emit + `enableMonitoring`〔発行間隔は poll と無関係の固定既定〕。**購読不可ノードは `source.poll` 周期の `readAttributes` フォールバック**〔plan 定義どおり購読を主・poll=0 はフォールバックなし〕）を追加。root `CMakeLists.txt` に `find_package(Qt6 ... OpcUa)`（SerialBus と同じ理由で root 配置）、Simulator 共有 function 内で `Qt6::OpcUa` リンク（`otool -L` で Editor 非リンク・Simulator リンクを確認）。main.cpp で `opcuaController` を context property 公開、Main.qml の `applyLoadedProject` で `opcuaController.configure`（Modbus と同じ list を渡し proto で排他に拾う）+ `variableUpdated`→`VariableStore.setValue`。MVP は読込/購読のみ（書込/接続状態/再接続は OP-4）。世代カウンタで再 configure/stop 後の旧非同期コールバックを無効化（ModbusController と同型）。unit `tst_opcua_controller`（backend 存在 / proto 排他 / 到達不能の安全性 / 再 configure・stop）。Qt OPC-UA はこの構成でサーバ機能を持たない（in-process Qt サーバ不可）ため購読 round-trip は asyncua E2E が担う（`tests/e2e/opcua_server.py` の `ns=2;s=Temp`=1234 を Simulator が購読 → Label text 追従）。
  - **🔴 Web 不可ゲート→ macOS ローカルで解消（2026-06-22）**：OP-2 着手時に **qtopcua を Qt 6.11.1 ソースから open62541 backend 付きでビルドし Homebrew Qt（`/opt/homebrew/opt/qt`）にマージ**して解消（`QOpcUaProvider::availableBackends()`=`("open62541")` 確認）。罠：full Xcode 不在（CLT のみ）だと Qt モジュールビルドが「Can't determine Xcode version」で FATAL → `-DQT_NO_XCODE_MIN_VERSION_CHECK=ON` でスキップ。手順・罠の正本は [.claude/rules/dev-environment.md](../.claude/rules/dev-environment.md)「Qt OPC-UA を Homebrew Qt にマージ」。**Web/CI（aqt 非同梱）・Windows 母艦・実機 rootfs は別途**。
  - **OP-1 完了（PR #140・Web ctest 25/25 緑）**：`ConnectionData.endpoint` / `SourceData.nodeId` を optional 追加（4 メソッド・空時省略）。`SourceData::isValidJson` を「`connection` 必須 +（`reg` 有効 or `nodeId`〔文字列・非空〕）」へ変更（OPC-UA source を受理。reg/nodeId 双方欠落は不正）。`ConnectionData::isValidJson` に proto 既知値検証、`SourceData::isValidJson` に poll 非負検証も追加。Editor は変数ソース編集に「プロトコル」ComboBox を追加し proto 切替時に proto 由来 connection id（plc1/opc1）+ 非アクティブ proto フィールドのクリア + poll 既定（modbus 1000 / opcua 0）を入替（混在時の connections[] 集約衝突・nodeId 空 source 保存・modbus 復帰時 reg 欠落を回避）。Editor は `Qt6::OpcUa` 非リンク維持。レビュー往復で Codex P1（接続 ID 衝突）/ Major（modbus 復帰時 reg 復元）、CodeRabbit Major（opcua nodeId 必須）/ Minor（nodeId 型検証・proto/poll 検証）を解消。
  - **🔴 最重要ゲート（Web 不可）**：**Qt OPC-UA（`qtopcua`）は aqtinstall のバイナリ addon に含まれない**（2026-06-20 実証：Web の Qt 6.10.0 linux で `aqt list-qt ... --modules` に `qtopcua` 無し・`qtserialbus` はある）。よって OP-2 以降（OpcUa リンク）は Web でビルド・テスト不可。実装はローカル kit（Qt OpcUa を自前ビルド/別配布でマージ）+ 実機 rootfs（`qtopcua` + open62541 backend）が要る。**OP-1（Schema + Editor UI）のみ OpcUa 非依存で Web 可。**
  - **タスク**：OP-1（変数ソース Schema 拡張〔`endpoint`/`nodeId`/`proto`〕+ Editor UI・Web 可）/ OP-2（PC 読込/購読・asyncua ソフトサーバ E2E・ローカル）/ OP-3（実サーバ読込確認・ローカル）/ OP-4（書込 + 接続状態 + 再接続・ローカル）/ OP-5（実サーバ書込確認・ローカル）/ OP-6（実機 Runtime 展開・WSL2+実機）。
  - **OP-5 完了（Windows 母艦：`test_server.py` + `opcua-demo.json` の NumericField で Setpoint 書込確認。2026-06-27）**：Windows 母艦（Qt 6.11.0 MinGW）に `scripts/windows/build-opcua.ps1` で qtopcua を導入し `hmi_simulator` をリビルド。`scripts/opcua/test_server.py` をソフトサーバとして起動し `Docs/samples/opcua-demo.json` を開いて NumericField で Setpoint を書き込み asyncua クライアント（別ターミナル）で読み返し確認。macOS に続き Windows でも OP-3（読込追従）と OP-5（書込）を実証。
  - **OP-6 完了（2026-06-27：i.MX8MP 実機で OPC-UA 読込購読を VNC キャプチャで確認）**：`meta-toolchain-qt6` SDK に qtopcua が既包含（SDK 再ビルド不要）→ WSL2 で `HMI_BUILD_DIR=/home/ubuntu/build-yocto-op6 HMI_SRC_DIR=/mnt/c/repo/hmi-platform bash scripts/yocto/cross-build.sh` → 実機 scp（Windows 母艦から `scp -O -o StrictHostKeyChecking=no`）→ 実機に `libsocketcan2` / `libqt6serialport6` / `libqt6serialbus6` の deb を転送 + `dpkg -i`（この順で依存解決）→ 実機の eth0 に `ip addr add 192.168.1.211/24 dev eth0` で静的 IP 付与 → Windows 母艦で `python test_server.py --host 192.168.1.210`（全 IF バインド）起動 → `QT_QPA_PLATFORM='vnc:size=1280x720'` で hmi_runtime 起動 → `python scripts/yocto/vnc-capture.py 192.168.1.211 5900 out.png 192.168.1.210` でキャプチャ。証跡：`Docs/screenshots/op6-runtime.png`（Counter=234・Temperature=20.065・Running=false・Setpoint=50 のライブ値が i.MX8MP 実機で表示）。踏んだ罠と手順の正本は [.claude/rules/dev-environment.md](../.claude/rules/dev-environment.md)「OPC-UA 実機展開」に追記済み。**Phase 9 OPC-UA クライアント対応クローズ（OP-1〜OP-6 全完了）。**

---

## Phase 10: メーター（Meter・車のスピードメーター風／完了 — M-A〜M-D クローズ）

**計画書**：[Docs/archive/phase10-meter-plan.md](archive/phase10-meter-plan.md)（M-A〜M-D。2026-06-27 スコープ選択＝Phase 9 クローズ後の候補からユーザーが「メーター」を選択し、形状を「車のスピードメーター風＝円弧＋針」に確定。**本タスクは計画書の起票のみ**）

- 📋 計画起票。新 Widget 種別「Meter」を Phase 5（Label）/ 6（NumericField）/ 8（Trend）で確立した横展開テンプレ（resolved\* フォールバック + Schema 4 メソッド + delegate 型分岐 + インスペクタ型対応 + cross-app E2E）に乗せる。**描画は円弧（アーク）＋針の QML `Canvas` 自描画で新 Qt モジュール依存ゼロ**（Trend と同じく i.MX8MP rootfs にそのまま載る）。読み取り専用表示で値源は既存 `bindings` の「読み」を再利用＝**Schema 4 メソッド追加のみで C++ ブリッジ無改変**。
  - **Schema 新規フィールド（Meter 固有・全 optional）**：`meterMin`/`hasMeterMin`・`meterMax`/`hasMeterMax`（スケール範囲＝値→角度マッピング定義域。負値正当 → presence フラグ方式。NumericField の `minValue`/`maxValue`・Trend の `yMin`/`yMax` の前例踏襲で**独立フィールド**）、`arcColor`/`needleColor`（`""` センチネル）、`tickCount`（`0` センチネル）、`unit`（`""` センチネル）。`isValidJson` 必須集合（id/type/width/height）は不変＝後方互換。
  - **タスク**：M-A（Schema 拡張・round-trip）/ M-B（型分岐の足場 5 分岐目 + HmiMeter 描画〔値→針角度 + Canvas 自描画。テスト用公開 `displayValue`/`needleAngle`〕）/ M-C（Editor「メーター追加」+ インスペクタ「Meter 詳細」型対応）/ M-D（cross-app E2E `e2e_meter_live`〔針追従を公開プロパティで観測〕+ スクショ）。
  - **非スコープ（別承認）**：複数メータースタイル（半円のみ・360°リング・縦横バー）・色帯（緑/黄/赤ゾーン）・中央数値の decimals 指定・後続入力 Widget（Toggle）・履歴永続化。
- ✅ **M-A（Schema 拡張）完了**。`WidgetData` に Meter 固有フィールド（`meterMin`/`hasMeterMin`・`meterMax`/`hasMeterMax`〔presence フラグ方式・負値正当〕・`arcColor`/`needleColor`〔`""` センチネル〕・`tickCount`〔`0` センチネル〕・`unit`〔`""` センチネル〕）を追加し、`toJson`/`fromJson`/`toVariantMap`/`fromVariantMap` の 4 メソッドを Trend（`yMin`/`yMax`/`lineColor`）の前例どおり揃えた。**C++ ブリッジ（ProjectIo / ProjectLoader）無改変**（`git diff` は Schema 2 ファイル + test のみ）。`isValidJson` 必須集合は不変＝後方互換。`tst_widget_data.cpp` に round-trip 3 本（`meterFieldsRoundTrip`〔presence true + 空/`0` センチネル〕/ `meterRangeOmittedWhenUnspecified`〔未指定時キー省略〕/ `negativeMeterRangeRoundTrip`〔負値〕）を追加。**描画 HmiMeter・追加 UI・インスペクタは M-B 以降**。ただし **Editor 保存経路の round-trip 保全は M-A に前倒し**（Codex PR #152 [P2]）：`EditableWidget` の Meter メタ + `Canvas.qml` delegate 流し込み + `snapshotModel()` 書き戻しを追加し、Meter JSON を Editor で開いて保存しても範囲・色・目盛り・単位を失わないようにした（Task 8B-A の Trend `series` 素通しと同型。全スカラ＝変数参照/入れ子なしなので deep copy・rename 追従は不要）。`tst_canvas.qml` に snapshot 保全テスト追加。Web `ctest` 25/25 緑。
- ✅ **M-B（型分岐の足場 5 分岐目 + HmiMeter 描画）完了**。`Shared/Widgets/qml/HmiMeter.qml` を新設（背景・枠を持つ `Rectangle` + 弧/目盛り/針/中央数値を自描画する `Canvas` + 選択用 `MouseArea`。**`import QtQuick` のみ＝新 Qt モジュール依存ゼロ**。Trend と同じ resolved\* フォールバック方式で既定値〔`meterMin`→0 / `meterMax`→100 / 弧色 #4cc9f0 / 針色 #ff595e / 目盛り 10 / 背景 #0b1d2a〕を HmiMeter 1 箇所へ集約）。**値→針角度**は `startAngle=135`・`spanAngle=270`（下側 90° を開けたスピードメーター既定・実装時確定）で線形マッピング + clamp（min→startAngle / 中点→startAngle+span/2 / max→endAngle）。**不正範囲（max<=min）は 0 除算せず下限へ退避**（plan リスク 3）。Canvas はピクセル不可視のためテスト用に `displayValue`/`needleAngle` を公開。`Shared/Widgets/CMakeLists.txt` の `QML_FILES` に登録。Editor `Canvas.qml` / Simulator `SimulatorCanvas.qml` の delegate に **5 分岐目** `meterComponent`（objectName `hmiMeter`）を追加（Editor=live:false で中間値〔(min+max)/2〕プレビュー / Simulator=live:true で `boundValue("value")` 追従＝Trend の value 追従と同じ boundValue 経路）。単体 `tst_hmi_meter.qml`（resolved 既定・値→角度・負値範囲・clamp・不正範囲退避・displayValue 追従・プレビュー中間値・clicked＝11 本）+ Editor/Simulator の delegate 生成 unit を追加。Web `ctest` 25/25 緑。**実機 Canvas 描画の VNC 確認は作業 TODO**（ローカル実機が要るため Web で満たせない＝完了条件外。plan リスク 1）。**追加 UI（ツールバー / インスペクタ）は M-C**＝本タスクは手書き JSON で検証。
- ✅ **M-C（Editor 追加 UI + インスペクタ型対応）完了**（PR #154）。Editor に Meter の追加 UI とインスペクタ型対応を足した（Schema・C++ ブリッジ・描画は不変）。①`Canvas.qml` の `addWidget` ホワイトリストに `"Meter"` を追加（既定サイズ 200×200・`text:""`）。②ツールバーに「メーター追加」ボタン（objectName `addMeterButton`）。③`Main.qml` に `selectedIsMeter` を追加し `selectedSupportsClickAction` に `&& !selectedIsMeter` を連結（Meter はクリックアクション非対応）。④基本セクションの Text 欄・文字セクションを Meter でも隠す。⑤新設「Meter 詳細」セクション（`visible: selectedIsMeter`）に 範囲 min/max〔presence チェック方式〕/ 弧色・針色〔hex TextField + 色スウォッチ + ColorDialog〕/ 目盛り数〔SpinBox・0=既定 10〕/ 単位〔TextField〕を配置。`tst_canvas.qml` に `addWidget("Meter")` の型・既定サイズ・undo 回帰を追加。`editor.png` 同期。
- ✅ **M-D（cross-app E2E + スクショ）完了＝Phase 10 クローズ**。Meter の「変数変化 → 針追従」を観測する cross-app E2E `tests/e2e/test_meter_live.py` を新設し `tests/e2e/CMakeLists.txt` に `e2e_meter_live` を登録した（Schema・C++ ブリッジ・QML・描画は不変＝テスト追加のみ）。①Editor 段：`vehicleSpeed`（int）変数 + `value` binding の Meter（`meter001`, meterMin 0 / meterMax 180 / tickCount 12 / unit "km/h"）+ 同変数の操作用 NumericField（`speeder001`）を持つ JSON を `--open` → `saveTo` で round-trip 保存し、保存 JSON を直接 assert（`type:"Meter"` / value binding / `meterMin`・`meterMax` の presence round-trip）。②Simulator 段（主眼）：操作用 NumericField を `setStringProperty` + `commitValue()` invoke で `["60","120","200"]` と順に確定して同変数を変化させ、Meter（objectName `hmiMeter`）の公開 `displayValue` が書いた値（範囲外 "200" は max=180 へ clamp）へ、`needleAngle` が弧の角度域へマッピングした期待値へ追従するのを `getStringProperty` で観測する。**期待角度は実行時に読んだ公開 `startAngle`/`spanAngle`/`resolvedMeterMin`/`resolvedMeterMax` から計算**し既定角度の定数（135°/270°）へテストを結合しない（plan リスク 2）。Canvas はピクセル不可視なので公開 real プロパティのみで針追従を見る（`test_trend_live` の Meter 版）。Web `ctest` 26/26 緑（`e2e_meter_live` 含む）。**UI は M-C から不変＝ヒーロー / スクショ再撮影は不要**（M-C で同期済み）。**これで Phase 10（Meter）クローズ。次フェーズは未承認＝先にユーザーとスコープ確定。**

---

## Phase 11: Widget サンプルパレット（D&D 追加）＋ 初号「シンプルボタン」（完了 — W-A〜W-E クローズ）

**計画書**：[Docs/archive/phase11-widget-palette-plan.md](archive/phase11-widget-palette-plan.md)（W-A〜W-E。2026-07-12 承認）

- 📋 計画起票 + 見た目プロトタイプ。issue #155「シンプル・イズ・ベスト版 HMI ボタン（ベゼル無し）」を QML の実 Widget として忠実再現し、さらに**見た目そのままの Widget サンプルをインスペクタに並べてキャンバスへ D&D で追加する汎用パレット UX** を新設する（初号＝シンプルボタン。将来他 Widget もパレット化）。
  - **設計方針**：ランプ・進捗リング・円形など既存 HmiButton（Rectangle+Text）で描けない造形のため**新 Widget 種別 `SimpleButton`（`HmiSimpleButton.qml`）** として横展開テンプレに乗せる。**描画は Canvas 自描画で新 Qt モジュール依存ゼロ**（`import QtQuick` のみ＝Meter/Trend 同方針で i.MX8MP rootfs にそのまま載る）。issue の `oklch()`/`color-mix()` は Qt Quick 非対応のため hex 換算。効果音は非スコープ。
  - **タスク**：W-A（Schema 拡張＝`shape`/`theme`/`accentColor`/`holdMs` + `checked` 再利用）/ W-B（HmiSimpleButton 描画 + delegate 6 分岐目・長押し確定リング/バー）/ W-C（サンプルパレット・パネル＝実 Widget を縮小レンダリング）/ W-D（パレット→キャンバス D&D 追加）/ W-E（インスペクタ型対応 + cross-app E2E + スクショ）。
  - **見た目プロトタイプ先行（本エントリ）**：見た目確定のため `HmiSimpleButton.qml` を W-A/W-B に先行して作成し、ユーザーレビューで反復調整（ランプを右上へ・TEST を大きな主ラベル/ON・OFF を小さな従に・文字サイズは面短辺比でリサイズ耐性）→ 承認。`Shared/Widgets/CMakeLists.txt` の `QML_FILES` に登録（ビルド検証済み・Web `ctest` 26/26 緑）。**まだ Schema 型・delegate・パレットには未接続**＝単体プレビュー用コンポーネント。正式な横展開は W-A（Schema）以降。
  - **非スコープ（別承認）**：効果音・複数アクセントテーマの動的追加・WARN/ERR/LOCK 状態モード・他 Widget 種別のプリセット拡充・リッチ版ボタン（retro/juicy/temperate）移植。
- ✅ **W-A〜W-D**（PR #163 / #164 / #165 / #166）：Schema 拡張（`shape`/`theme`/`accentColor`/`holdMs` の 4 メソッド round-trip）→ HmiSimpleButton 描画 + delegate 6 分岐目（長押し確定リング/バー・`checked` binding 経路一本化＝`runClickActions` 非使用）→ サンプルパレット（実 Widget 縮小レンダリング + クリック追加）→ パレット→キャンバス D&D 追加（`addPresetWidget(preset, dropX, dropY)` + `DropArea`）。
- ✅ **W-E: インスペクタ型対応 + cross-app E2E + スクショ（Phase 11 クローズ）**
  - **目的**：SimpleButton の属性（形状 / テーマ / 差し色 / 長押し時間）をインスペクタで編集可能にし、長押しトグルの round-trip を E2E で固定して Phase 11 を閉じる。
  - **成果物**：①インスペクタ「シンプルボタン詳細」セクション（`selectedIsSimpleButton` 出し分け。文字・背景/枠はテーマが決めるため非表示、`checked`〔状態をオン〕は表示、クリックアクションは `selectedSupportsClickAction` に `&& !selectedIsSimpleButton` で非表示）②`HmiSimpleButton.commitHold()`（長押し満了を模す公開メソッド＝`commitValue()` 前例）③cross-app E2E `e2e_simple_button_live`（Editor round-trip 保存 JSON 直接 assert → Simulator で `commitHold()` 3 連打・`checked` 反転を観測）④ショーケース demo に SimpleButton（長押し RUN・`running` バインド）追加 + ヒーロー（editor.gif / simulator.png）撮り直し。
  - **学び（重要）**：**W-D の D&D ゴーストを `Overlay.overlay` に親替えした変更が、QtQuick Controls の Overlay にマウスイベントを奪わせ Editor ウィンドウ全体のクリックを殺す回帰**を起こしていた（main CI で e2e 4 件失敗）。W-E でゴーストの親をウィンドウ `contentItem` に差し替えて解消（[qml-module-conventions](../.claude/rules/qml-module-conventions.md) に追記）。

---

## リファクタリング（RF-A〜・v1.0 公開まで中断）

**計画書**：[Docs/refactoring-plan.md](refactoring-plan.md)（PR #167 で `[Future]` として起票 → 2026-07-22 ユーザー指示で承認・Phase 11 と並行着手）

- ✅ **RF-A: Main.qml 分割①（ツールバー / ダイアログ抽出）**。`Editor/qml/Main.qml`（2,712 行）からツールバー Row を `EditorToolbar.qml`、ダイアログ 4 つ（色選択 ×2 / 保存 / 読込）を `EditorDialogs.qml` へ抽出（2,533 行に減）。objectName・挙動は不変＝既存 E2E 互換。Canvas 参照は自己参照罠回避で受け口を `editorCanvas` 別名にした（MB-4 罠①と同型）。
  - **学び（W-D の不具合発見・同 PR で修正）**：E2E 検証で 4 件（place_and_drag / save_load_roundtrip / simulator_display / style_roundtrip）が RF-A 適用前の main でも失敗しており、bisect で W-D（PR #166）由来と特定。**D&D ゴーストを `Overlay.overlay` に再親化すると、QQuickOverlay が Editor ウィンドウ全体の合成マウスイベントを奪い、ツールバー・キャンバスのクリックが全て死ぬ**（Qt 6.10 offscreen で実証）。ゴーストの親を `Window.contentItem` + 高 `z` に変えて修正（クリップ回避という元目的は維持）。
- ✅ **RF-B: Main.qml 分割②（インスペクタ本体抽出）**。`Main.qml` に残っていたインスペクタ（`ScrollView` 以下の全 `InspectorSection`）と**インスペクタ専用のヘルパー**（フォーカス集約 `widgetEditFieldFocused` / `inspectorFieldFocused`、型判定 `selectedIsXxx` / `selectedSupportsClickAction`、アクション・バインディング・系列・幾何の編集関数、インライン `ColorSwatch`、`colorSwatchSize`）を `InspectorPanel.qml` へ抽出（**Main.qml 2,533→346 行**）。`objectName: "inspectorPanel"` と各入力欄の objectName・編集ロジック・Schema は不変＝既存 E2E 互換。回帰テスト `Editor/tests/tst_inspector_panel.qml`（6 件）を追加し、全 30 テスト緑。
  - **境界の引き方**：Project レベルの状態（`projectVariables` とその編集ヘルパー・`variableNameModel`）とダイアログ起動（`openColorDialog` / `openSeriesColorDialog` / `colorToHex`）は **Window 所有のまま**にし、パネルからは受け口 `editorRoot` 経由で呼ぶ（状態の所有者を子へ動かさない）。逆に系列編集 `updateSeries` はパネルへ移ったので、`EditorDialogs` に受け口 `editorInspector` を足して書き戻し先をパネルへ向けた。
  - **学び**：①**抽出先が同一モジュール内の型（`InspectorSection` / `SamplePalette`）しか使わないなら `import HmiEditor` は不要**で、外すと Qt Quick Test から `Qt.resolvedUrl("../qml/InspectorPanel.qml")` で直接ロードでき回帰テストを書ける（`Canvas.qml` は QtQuick の `Canvas` と名前衝突するため利用側の明示 import が要る＝Main.qml 側だけの事情）。②Window の派生プロパティが**抽出対象の内部 id を列挙している**（`widgetEditFieldFocused` が 30 個超の入力欄 `activeFocus` を OR）場合、その派生プロパティごと抽出先へ移し、残った側（Shortcut のガード）はパネルのプロパティを参照する形にする。
- ✅ **RF-D: 種別分岐の集約（widgetTypeTable）**。種別ごとの「許可リスト・既定サイズ・既定文字」が `Canvas.qml` の `normalizeWidgetType`（許可リスト）と `addWidget`（`isTrend/isMeter` サイズ分岐 + text 三項連鎖）に散っていたのを、単一の `readonly property var widgetTypeTable`（種別 → `{width, height, text}`）へ集約。`normalizeWidgetType` はキー存在判定、`addWidget` は `meta` 参照、`addPresetWidget` はサイズ既定に同テーブルを使う。**新種別追加時はテーブルに 1 行足すだけ**で 3 関数が追従する。既存挙動は完全不変（全 26 テスト緑）で、従来欠けていた Trend 既定サイズ（240×120）の回帰テストを補った。
- ✅ **RF-E: delegate 重複の削減（Shared/Widgets への型別ホスト QML化）**。Editor（`Canvas.qml`）/ Simulator（`SimulatorCanvas.qml`）が型ごとに反復定義していた「Schema 値 → Hmi* プロパティ」受け渡しを、`Shared/Widgets/qml/ButtonHost.qml` / `LabelHost.qml` / `SimpleButtonHost.qml`（方式 (a)）へ集約した。**対象は「表示専用 + binding 読取のみ」の 3 種（Button/Label/SimpleButton）に限定**：読み書き両用 binding を持つ NumericField、binding 非対応の Trend/Meter は非対称性の吸収コストが見合わず対象外（別途検討）。Editor（静的値）/ Simulator（`boundValue` で変数追従）の非対称性は Host の `resolveBound` フック（null＝Editor / `wrapper.boundValue` そのまま渡す＝Simulator）で吸収し、String化/bool化（coerce）も Host 側へ集約した。Canvas.qml 1,244→1,240 行 / SimulatorCanvas.qml 532→492 行。objectName・QML ツリー構造・Schema・見た目は完全不変（`ctest` 30/30 緑、E2E 込み）。
  - **経緯**：着手前に方式 (a) Shared/Widgets への型別ホスト QML化 / 方式 (b) Simulator 側ヘルパー止まり の 2 方式を Button/Label で試作比較し、(a) を採用（`Docs/refactoring-plan.md` の想定どおり）。
  - **学び**：QML の依存追跡は「関数呼び出しを跨いでも効く」（Task 41 の `boundValue` パターン）だけでなく、**object literal のバインディング式（`widget: ({ text: wrapper.widgetText, ... })`）でも同様に効く**（内部で読んだプロパティが依存として追跡される）。Host を挟んで QML ツリーが 1 段深くなっても、Spix / unit の objectName 探索は再帰的（`hmiEditorWindow/widget_<id>/hmiButton` が元々複数の無名ノードを跨いで解決できている）ため objectName パスは無傷だった。

フェーズタスクとは別に、プロジェクト全体の**開発時の通称（ブランド別名）**を決めた経緯。

- **きっかけ**：Yocto 5.0 にコードネーム（scarthgap）があることに着想し、本プロジェクトにも愛称を付けるか検討。
- **要件の確定**：対話で次の 4 点に整理 — ①**ブランド名（恒久・1 個）**、②由来のアンカーは**マキャベリ**「積極果敢に行動する者に味方する」（正確にはラテン語 *Audentes Fortuna iuvat* はウェルギリウス由来、マキャベリ『君主論』25 章はその思想を *impeto / virtù* で展開）、③**別名のみ**（リポジトリ名・CMake・QML URI はリネームしない）、④**被り可・開発時のみ**使用（商標/一意性チェックは不要）。
- **候補の遍歴**：マキャベリ軸のラテン/伊語（Audentia → Audax → Audens → Impeto / Virtù）→ 天体・神話系（Impeto / Atlas / Helios / Polaris）→ 4 語の造語（Impelios / Imathelaris 等）→ 最終的に短く据わりの良い **Atlas** に決定。
- **決定**：**Atlas（アトラス）**。由来はギリシャ神話で天空を支える巨神アトラス（Editor / Simulator / Runtime / Shared を**束ねて支える基盤**の含意）。マキャベリ由来からは離れたが、製品の「基盤」性格との比喩適合と語感を優先。
- **成果物**：[README.md](../README.md) 冒頭と [CLAUDE.md](../CLAUDE.md) 冒頭に一文ずつ追記（コミット `69acc83`）。**リネームは一切なし**（`hmi-platform` / `hmi_*` / `Hmi*` は従来どおり）のため CI / Codex 連携スコープ / スクショ URL 等の依存は無傷。
- **学び**：恒久ブランド名は「不可読性」より「読める・呼びやすい・由来を語れる」を優先軸にすべき、という整理に落ち着いた（Yocto 式の“回すコードネーム”とは設計目的が異なる）。被り可・別名運用に割り切ると、一意性検証のコストをかけずに決められる。

---

## v1.0 公開準備（OSS 化・着手中）

**計画書**：[Docs/v1-release-plan.md](v1-release-plan.md)（2026-11-05 ユーザー指示で承認）

- **決定事項**：公開日 2026-11-09（月）、ライセンス MIT、リファクタリング RF-E は公開後に再開。公開までは機能凍結。
- **方針**：public 化すると全 git 履歴が読めるようになるため、機微情報の全履歴スキャン（V1-1）と self-hosted runner の廃止（V1-4）を「公開を止める条件」にした。

---

## 関連ドキュメント

- [README.md](../README.md) — 進捗表（状態のみ）・ビルド手順・スクリーンショット
- [CLAUDE.md](../CLAUDE.md) — Claude Code 向けの作業指針・既知の罠の集約
- [AGENTS.md](../AGENTS.md) — Codex GitHub App 向けのレビュー指針
- [Docs/archive/phase2-testing-plan.md](archive/phase2-testing-plan.md) — Phase 2 計画書
- [Docs/archive/phase3-e2e-plan.md](archive/phase3-e2e-plan.md) — Phase 3-A 計画書
- [Docs/archive/phase3b-runtime-plan.md](archive/phase3b-runtime-plan.md) — Phase 3-B 計画書 v2
- [Docs/archive/phase4-button-slice-plan.md](archive/phase4-button-slice-plan.md) — Phase 4 計画書（コア縦スライス + 拡張）
- [Docs/archive/phase10-meter-plan.md](archive/phase10-meter-plan.md) — Phase 10 計画書（メーター / 円弧＋針）
- [Docs/archive/phase3b-runtime-journey.md](archive/phase3b-runtime-journey.md) — Phase 3-B 奮闘記（Task 23/24 をどう乗り越えたか・心境の記録）
- [Docs/archive/qml-canvas-structure.md](archive/qml-canvas-structure.md) — Canvas.qml の構造解説
