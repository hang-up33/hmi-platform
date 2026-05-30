# CLAUDE.md

このファイルは、本リポジトリで作業する Claude Code（claude.ai/code）への指針です。
**ユーザーは日本人のため、応答・ドキュメント・コミットメッセージは日本語を基本とします**（コード識別子は英語可）。

> **本プロジェクトの開発コードネームは「Atlas（アトラス）」**（プロジェクト全体のブランド別名・開発時の通称）。正式なリポジトリ名・CMake プロジェクト名・QML URI 等は従来どおり（`hmi-platform` / `hmi_*` / `Hmi*`）で、リネームはしない。Atlas はあくまで README 冒頭などで用いる愛称。由来はギリシャ神話で天空を支える巨神アトラス（Editor / Simulator / Runtime / Shared を束ねて支える基盤の含意）。

---

## プロジェクト概要

Yocto / i.MX8M Plus 向け Qt6 HMI ランタイムを対象に、HMI 作画ツール（Editor）・PC 試験環境（Simulator）・実機ランタイム（Runtime）・JSON スキーマ（Shared/Schema）・共有 Widget（Shared/Widgets）を統合した開発基盤。詳細は [README.md](README.md)。タスクごとの時系列まとめ（目的 / PR / 成果物 / 学び）は [Docs/development-history.md](Docs/development-history.md) — 第三者説明用で、タスク完了時に当該 Task のエントリを追記する運用候補。

**現在のフェーズ**：**Phase 3-A 完了 + Phase 3-B-1（Task 22）完了**、Task 23〜24 未着手。Phase 1 / MVP（Task 1〜8）、Phase 2 / テスト基盤導入（Task 9〜15）、Phase 3-A / E2E テスト導入（Task 16〜21）、**Phase 3-B-1 / Runtime CMake glue（Task 22）** まで完了済み。Task 22 で **Simulator の QML module を STATIC 化 + 共通 CMake function `hmi_add_simulator_like_executable` で hmi_simulator / hmi_runtime の 2 バイナリを同一ソースから生成** する構成を確立（ホスト PC で両バイナリが完全に同じレイアウトで JSON 描画することを目視確認、`Docs/screenshots/task-22-*.png`）。E2E フレームワークに **Spix（OSS / MIT）** を採用し、Editor 配置 → JSON 保存 → Simulator 表示までの cross-app 動作を `ctest -L e2e` で検証可能。**macOS は E2E まで含む `ctest` 緑、Windows MinGW は AnyRPC の libstdc++ 衝突回避のため `HMI_ENABLE_E2E` が既定 OFF・E2E は既知スキップで通常 ctest のみ緑**（詳細は後述「Spix（E2E）統合の罠」最終項）。GitHub Actions CI も同様にユニットは全 OS、E2E は macOS のみで実行する構成。タスク分割と完了基準は [Docs/phase3-e2e-plan.md](Docs/phase3-e2e-plan.md) を参照。**残りの Phase 3-B（Task 23: Yocto SDK クロスビルド / Task 24: 実機描画）は未着手**。開発ホストは Windows 母艦 + WSL2 で、Yocto SDK クロスビルドは **WSL2 内で実施**。**ただし 2026-05-30 に実機 image が Qt6 非対応（NXP zeus 5.4、Qt6 未搭載）と判明したため、Task 23 はまず NXP 新 BSP（scarthgap）で `imx-image-full` をビルドして実機 image を更新 → 同一 BSP から SDK 生成、という流れに拡張**（[Docs/phase3b-runtime-plan.md](Docs/phase3b-runtime-plan.md) §「実機 image 調査結果と更新方針」）。3 バイナリ構成（hmi_editor / hmi_simulator / hmi_runtime）を維持。タスク分割と完了基準は [Docs/phase3b-runtime-plan.md](Docs/phase3b-runtime-plan.md) を参照。

---

## コア原則

1. **1 タスクずつ完結** — 設計書のフェーズタスク順（MVP / Phase 2 / Phase 3-A / Phase 3-B …）を厳守し、各タスクは `cmake --build` 成功を完了基準とする。
2. **Shared/Schema が唯一の真実** — Widget / Screen / Project に該当する型・JSON 入出力はここにのみ定義。
3. **継続的改善（kaizen）の遵守** — タスク完了報告の前に、得た知見を CLAUDE.md / README / メモリ / 設定のいずれかに反映する（[kaizen-close](.claude/skills/kaizen-close/SKILL.md) スキルで標準化）。
4. **既存資産の保護** — フォルダ構成変更禁止・既存コード削除禁止（例外は明示されたプレースホルダーのみ）。
5. **計画してから実装** — 複雑なタスクはエージェントに計画させてから手を動かす。

---

## ビルドと実行

### macOS

```sh
# 構成（Qt 6.8 以上を指す。後述「Qt バージョンの罠」参照）
cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt

# 全体ビルド
cmake --build build

# 個別ターゲット
cmake --build build --target hmi_editor
cmake --build build --target hmi_simulator
cmake --build build --target hmi_schema
cmake --build build --target hmi_widgets

# 起動
./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor
./build/Simulator/hmi_simulator.app/Contents/MacOS/hmi_simulator
```

### Windows（PowerShell）

```powershell
# configure + build （build-mingw/ に出力）
.\scripts\windows\build.ps1
.\scripts\windows\build.ps1 -Target hmi_editor
.\scripts\windows\build.ps1 -Reconfigure

# 起動（build.ps1 実行後はそのまま起動可。新シェルなら setup-env.ps1 を dot-source）
. .\scripts\windows\setup-env.ps1
.\build-mingw\hmi_editor.exe
.\build-mingw\hmi_simulator.exe
```

Windows は **Qt 6.11.0 MinGW 64-bit kit + 付属 MinGW 13.1 + Ninja** を前提とする（MSVC kit は未使用）。`scripts/windows/setup-env.ps1` が Qt 付属ツールチェイン（MinGW / Ninja / CMake）を PATH 先頭に挿入することで、システム側の VS `cl.exe` や別 MinGW を回避する。詳細・罠は [qt6-build](.claude/skills/qt6-build/SKILL.md) スキル参照。

テスト・lint・フォーマッタは未整備。

---

## アーキテクチャ

ルート `CMakeLists.txt` から 4 つのサブプロジェクトを統合：

| モジュール | ターゲット名 | 種類 | URI | 役割 |
|---|---|---|---|---|
| Shared/Schema | `hmi_schema` | STATIC lib | — | プロジェクト JSON の**唯一の真実**。Widget/Screen/Project の型と JSON I/O |
| Shared/Widgets | `hmi_widgets` | QML module | `HmiWidgets` | Editor/Simulator で共有する Widget 部品 |
| Editor | `hmi_editor` | アプリ | `HmiEditor` | 作画アプリ。`loadFromModule("HmiEditor", "Main")` で起動 |
| Simulator | `hmi_simulator` | アプリ | `HmiSimulator` | 読み取り専用の試験アプリ。同じ JSON を描画 |
| Runtime | `hmi_runtime` | アプリ（Simulator のソース共有） | `HmiSimulator`（再利用） | i.MX8MP / Yocto 向け。**Simulator/ のソースを共有して `hmi_runtime` バイナリを生成**（Runtime/ は CMake glue のみ）。Task 22 でホスト PC ビルドまで成立、Task 23（Yocto SDK クロスビルド）・Task 24（実機描画）未着手。詳細は [Docs/phase3b-runtime-plan.md](Docs/phase3b-runtime-plan.md) |

JSON 入出力は `QJsonDocument`（外部依存なし）。Editor / Simulator の widget リストの現状実装は **QML の `var` 配列ベース**（Task 5 で確立、`widgetModel = widgetModel.concat([...])` で配列丸ごと差し替えて Repeater をリトリガする）。`QAbstractListModel` 化は Phase 3-B スコープ確定後に再評価予定（メモリ `project_widgetmodel_refactor_deferred` 参照、現状は deferred）。

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

本プロジェクトはレビューを Codex GitHub App に委ねるため、**フェーズタスク（MVP / Phase 2 / Phase 3-A / Phase 3-B …）はすべて PR 経由で main に取り込む**。Claude は以下のフローに従う。

Codex 向けの永続的な指示は **リポジトリ直下の [AGENTS.md](AGENTS.md)** に記述する（Codex 公式推奨形式）。レビューを日本語化するための `## Review guidelines` セクションを含み、Codex GitHub App / Codex CLI の両方がレビュー時に参照する。Codex 関連で「全 PR に効かせたい」指示が増えたら、CLAUDE.md ではなく AGENTS.md 側に追記すること。

### ブランチ命名

- フェーズタスク（MVP / Phase 2 / Phase 3-A / Phase 3-B …）：`task/<N>-<短い名>` 形式（例：`task/2-canvas`, `task/16-spix-bootstrap`, `task/22-runtime-glue`）
- ドキュメント・設定変更：`docs/<短い名>` 形式（例：`docs/codex-auto-review`, `docs/qml-canvas-structure`）
- 1 単位 = 1 ブランチ = 1 PR。原則として main から派生させる
- **例外：直前タスクの PR がまだ main にマージされていない状態で次タスクに着手する場合**、当該依存ブランチ（例：`task/9-qt-test-setup`）から派生させ、`gh pr create --base <依存ブランチ>` で PR の base も依存ブランチに合わせる。依存ブランチが main にマージされたら、`git fetch origin && git rebase --onto main <依存ブランチ> task/<N>-...` で main にリベースし、PR の base も `gh pr edit <N> --base main` で main に切り替える。Task 10 着手時に Task 9 PR #18 が未マージだったため確立（2026-05）

### タスク完了時のフロー

1. 実装 → `cmake --build build` で緑を確認 → 動作確認
2. README の進捗表を更新
3. [kaizen-close](.claude/skills/kaizen-close/SKILL.md) スキルを実行
4. `task/<N>-<短い名>` ブランチを作成し、コミット
5. `gh pr create` で **ready-for-review** の PR を作成（draft にしない — Codex GitHub App に即レビューさせるため）
6. **`gh pr comment <N> --body "@codex review"` で明示的にレビュー依頼**（自動レビュー任せにせず毎回コメントで発火）
7. PR URL をユーザーに提示
8. **Codex レビュー結果が返るまで自走で待つ**（ユーザー指示を待たない。詳細は次節「Codex 指摘への対応」）

詳細は [codex-pr](.claude/skills/codex-pr/SKILL.md) スキルを参照。

**重要**：Step 7 で PR URL を提示しても、Codex レビューが返るまでは「完了」と報告しない。Codex が「Didn't find any major issues. 👍」のクリーンレビューを返した時点で初めて完了報告する。

### PR タイトル / 本文

- **タイトル**：`Task N: <短い説明>`（コミット先頭行と同じ）
- **本文**：Summary / 変更点 / Test plan / Codex 向け補足（不安な観点や重点的に見てほしい箇所）を含める

### マージ戦略

- **Squash and merge**。1 タスク = main 上の 1 コミットになるよう統合する。
- マージは **ユーザーが行う**（Codex のレビュー指摘を反映してから）。Claude は勝手にマージしない。

### Codex 指摘への対応

- Codex のレビュー結果は **PR コメントとして自動投稿される**。Claude は **ユーザー指示を待たず自走で待機** し、レビューが返り次第 `gh pr view <番号> --comments` と `gh api repos/.../pulls/<番号>/comments` で内容を取得する。指摘があれば当該ブランチで対応コミットを追加 push する。
- 修正 push の **直後にも必ず** `gh pr comment <N> --body "@codex review"` で再レビューを依頼する（PR 作成時と同じ運用）。
- **指摘 0 件のクリーンレビュー（`Codex Review: Didn't find any major issues. 👍`）になるまで** 自走でループする。0 件になって初めて「完了」とユーザーに報告できる。
- 大きな方針差し戻しになる場合は新タスクとして切り出すかをユーザーに相談する。

#### 自走待機の具体手段

Codex レビュー（issue comment or inline）は手動操作なしには通知されないため、Claude は Bash のバックグラウンドポーリングで待つ。30 秒間隔・最大 10 分（= 20 回）が現実的なバランス：

```sh
LAST_TS=$(gh api repos/<owner>/<repo>/issues/<N>/comments --jq 'sort_by(.created_at) | last | .created_at')
for i in $(seq 1 20); do
  sleep 30
  NEW=$(gh api repos/<owner>/<repo>/issues/<N>/comments --jq 'sort_by(.created_at) | last | .created_at')
  [ "$NEW" != "$LAST_TS" ] && break
done
```

inline review は `gh api repos/<owner>/<repo>/pulls/<N>/comments` 側にも来るので両方監視する。10 分で返らなかった場合のみユーザーに状況報告して指示を仰ぐ。

### 前提（Codex 側のセットアップ）

- **ChatGPT Codex（Web 版エージェント）** を使用する。
- chatgpt.com の **Codex** → **Settings** から GitHub を OAuth 連携し、`hang-up33/hmi-platform` への権限を付与しておく。
- GitHub の Installed Apps 一覧には "ChatGPT" / "OpenAI Codex" などの名前で出現する（マーケットプレイス検索ではヒットしない）。
- **Codex 側の自動レビュー設定が有効** になっており、`ready-for-review` で PR を push すれば手動操作なしに Codex が PR コメントでレビューを返す。Claude は `gh pr view <番号> --comments` で結果を取得できる。

---

## 利用可能なスキル

| スキル | 用途 |
|---|---|
| [mvp-next-task](.claude/skills/mvp-next-task/SKILL.md) | フェーズタスクの次を進める標準ワークフロー（MVP / Phase 2 / Phase 3-A / Phase 3-B …） |
| [codex-pr](.claude/skills/codex-pr/SKILL.md) | Codex レビュー前提の PR 作成手順 |
| [qt6-build](.claude/skills/qt6-build/SKILL.md) | Qt6 + CMake セットアップ・ビルド手順と既知の罠 |
| [kaizen-close](.claude/skills/kaizen-close/SKILL.md) | タスク完了直前に学びをドキュメントに反映する手順 |

---

## ルール（Must Always / Must Never）

### Must Always

- 現フェーズのタスク順を守る。Phase 1 / MVP（Task 1〜8）、Phase 2 / テスト基盤導入（Task 9〜15）、Phase 3-A / E2E テスト導入（Task 16〜21）、**Phase 3-B-1 / Runtime CMake glue（Task 22）** は完了済み。**Phase 3-B の残タスクは Task 23（Yocto SDK クロスビルド）・Task 24（実機描画）**（[Docs/phase3b-runtime-plan.md](Docs/phase3b-runtime-plan.md)）。次セッションで「次のタスクを進めて」と指示があれば Task 23 から着手するが、**前提が 2026-05-30 に変更**：実機の現行 image が Qt6 非対応（NXP zeus 5.4、Qt6 未搭載）と判明したため、Task 23 はまず **NXP 新 BSP（scarthgap）で `imx-image-full` をビルドして実機 image を更新 → 同一 BSP から SDK 生成 → `hmi_runtime` をクロスビルド** という流れになる（詳細は [Docs/phase3b-runtime-plan.md](Docs/phase3b-runtime-plan.md) §「実機 image 調査結果と更新方針」）。**新 BSP のフルビルドは大容量ディスク（100〜200GB）が要る。2026-05-30 のディスク整理で E ドライブに 212GB の空きを確保済みで、ユーザー方針として「Yocto ビルドは E ドライブを使用、不足時は D ドライブを空ける」と決定**（[Docs/phase3b-runtime-plan.md](Docs/phase3b-runtime-plan.md) §「実機 image 調査結果と更新方針」の「制約／ディスク確保済み」）。**Task 23 着手時はまず WSL distro を E へ relocate**（ext4.vhdx が現状 C: のため）してからビルドする。Phase 3-A の経緯と完了基準は [Docs/phase3-e2e-plan.md](Docs/phase3-e2e-plan.md) を参照。
- Widget / Screen / Project 型と JSON I/O は `Shared/Schema` にのみ実装。
- 完了報告の直前に [kaizen-close](.claude/skills/kaizen-close/SKILL.md) を実行し、得た知見を反映する。
- QML モジュール URI とアプリの `loadFromModule()` 引数を一致させる。
- 出力（応答・ドキュメント・コミットメッセージ）は日本語を基本とする。

### Must Never

- 複数のフェーズタスク（Phase 1 / Phase 2 / Phase 3）を 1 回で実装する。
- フォルダ構成を変更する（`Editor/ Simulator/ Runtime/ Shared/Schema/ Shared/Widgets/ Docs/` を維持）。
- 既存コードを削除する（例外：後述のプレースホルダー 2 件のみ）。
- qmake その他の代替ビルドシステムを導入する。
- main ブランチに直接 push / コミットする。タスクは必ず `task/<N>-<短い名>` ブランチ + PR で取り込む。
- 設計書未承認のフレームワーク / ライブラリを独断で追加する。
- Claude Code on the web でフェーズタスクの実装 / Codex 指摘対応 / ビルド検証を進める（理由は「Claude Code on the web は非対応」節を参照）。

---

## Qt バージョンの罠（macOS）

同梱の `~/Qt/6.7.0/macos` は **macOS 14 以降（Darwin 25+）でリンク不可**。`FindWrapOpenGL.cmake` が常に `-framework AGL` をリンクするが、AGL は macOS 14 で SDK から削除されている。

→ **Homebrew Qt 6.11.1（`/opt/homebrew/opt/qt`）または Qt 6.8+ を使用すること**。`AGL` 関連のリンクエラーが出たら、コードではなく `CMAKE_PREFIX_PATH` を疑う。詳細・他の罠は [qt6-build](.claude/skills/qt6-build/SKILL.md) と [cmake-build-resolver](.claude/agents/cmake-build-resolver.md) を参照。

## Spix（E2E）統合の罠

Task 16 で **Spix（OSS / MIT / `faaxm/spix` v0.14）と AnyRPC（XML-RPC 依存）を FetchContent で取り込んだ際に踏んだ落とし穴**。Phase 3-A の Task 17 以降を進める時、または別環境で再ビルドする時に再発する可能性が高い。

- **AnyRPC も FetchContent で取り込む必要がある**：Homebrew / apt の公式パッケージが存在しないため、Spix の `find_package(AnyRPC REQUIRED)` を満たすには `sgieseking/anyrpc` を自前でビルドする。Spix 単独 FetchContent では configure が落ちる。
- **AnyRPC は `cmake_minimum_required(VERSION 2.8)`**：CMake 3.27+ で configure が落ちるため、ルート CMakeLists.txt で **`set(CMAKE_POLICY_VERSION_MINIMUM 3.5)` を `FetchContent_MakeAvailable(anyrpc)` の前に置く**。`CMAKE_POLICY_VERSION_MINIMUM` は CMake 3.27 で導入された変数で、サブプロジェクトの policy floor を上書きする。
- **AnyRPC 内部の `include_directories(${CMAKE_SOURCE_DIR}/include)` が FetchContent 経由で誤動作する**：`CMAKE_SOURCE_DIR` はトップレベル（hmi-platform）を指すため、AnyRPC ヘッダが見つからない。**`FetchContent_MakeAvailable(anyrpc)` 直後に `target_include_directories(anyrpc PUBLIC $<BUILD_INTERFACE:${anyrpc_SOURCE_DIR}/include>)` を追加して補正**する。
- **Spix の `FindAnyRPC.cmake` を欺くには CACHE 変数 + ALIAS**：
  ```cmake
  if(NOT TARGET AnyRPC::anyrpc)
      add_library(AnyRPC::anyrpc ALIAS anyrpc)
  endif()
  set(AnyRPC_INCLUDE_DIRS "${anyrpc_SOURCE_DIR}/include" CACHE PATH "" FORCE)
  set(AnyRPC_LIBRARIES anyrpc CACHE STRING "" FORCE)
  ```
- **Spix の `install(EXPORT SpixCoreTargets)` が AnyRPC::anyrpc を含むため、anyrpc を同じ export set に登録する必要がある**：登録しないと `target "SpixCore" requires target "anyrpc" that is not in any export set` で configure が落ちる。`FetchContent_MakeAvailable(spix)` の前に `install(TARGETS anyrpc EXPORT SpixCoreTargets)` を呼ぶ。`cmake --install` を実行しなければ副作用なし。
- **Spix の `runTestServer` は非ブロッキング**：内部スレッドを立ち上げてすぐ return する。Spix の example は `auto bot = new spix::QtQmlBot();` で leak しているが意図的（process 終了まで生存させる、OS が回収）。本プロジェクトも同じパターンを採用しているが、`if (parser.isSet(e2eOpt))` 分岐の中で起動するため、`spix::AnyRpcServer` は **`static` ローカル**にして if スコープを抜けても破棄させない（`spix::AnyRpcServer` がローカル変数だと if 終了で destruct → サーバが即落ちる）。
- **`--e2e [<port>]` のような optional value は使えない**：QCommandLineParser は単一オプションの optional value を非サポート。真偽フラグ `--e2e` と値オプション `--e2e-port` に分けて宣言する。既定ポートは Editor=9876 / Simulator=9877（両アプリ同時起動 E2E シナリオでポート競合を避ける）。各 `main.cpp` の `QCommandLineOption e2ePortOpt(..., "port", "9876")` のデフォルト値で書き分け。
- **通常起動への影響はゼロを保つ**：Spix をリンク済みでも `--e2e` フラグが立っていなければ `AnyRpcServer` は構築されず、ネットワークも開かない。これを保つために Spix 起動コードを `if (parser.isSet(e2eOpt))` 分岐の中だけに置く（[Docs/phase3-e2e-plan.md](Docs/phase3-e2e-plan.md)「Must Never」の「通常起動パスに E2E 用コードを混ぜない」原則）。検証方法：`hmi_editor` 単独起動 → `nc -z localhost 9876` が **失敗**することを確認。
- **Windows MinGW では Spix を opt-out**：AnyRPC は MinGW 検出時に `internal/mingw.mutex.h` / `mingw.condition_variable.h` を強制 include して `namespace std` 内に `recursive_mutex` / `timed_mutex` / `condition_variable` を再定義する。これは pthread 非対応の古い MinGW 向けのシムで、modern MinGW（`mingw1310_64` / POSIX threads モデル）の libstdc++ と `error: redefinition of 'class std::...'` で衝突する。AnyRPC upstream は 2022 年以降未メンテで修正されない見込みのため、ルート CMakeLists.txt で `option(HMI_ENABLE_E2E ...)` を **MinGW 検出時に既定 OFF** にする。CMake 側で `HMI_HAS_SPIX` define を渡し、`Editor/src/main.cpp` / `Simulator/src/main.cpp` 双方で `#ifdef HMI_HAS_SPIX` で Spix include + 起動コードを囲む。`--e2e` フラグは常に受け付け、Spix 無効ビルドで `--e2e` が指定された場合は `qCritical()` で明確なエラーを出して `return 1`（黙ってフラグを無視しない）。Windows ローカル開発で E2E を使いたい場合は MSVC kit に切り替えるか `-DHMI_ENABLE_E2E=ON` を明示的に指定する（が、後者は CI で既知のビルドエラーになる）。
- **Homebrew Python 3.14 の `_pyexpat` 不整合**：macOS で `/opt/homebrew/opt/python@3.14` を使うと `import xmlrpc.client` が `Symbol not found: _XML_SetAllocTrackerActivationThreshold` で落ちる。これは Homebrew の `python@3.14` バンドルと macOS の `/usr/lib/libexpat.1.dylib` のバージョン非互換で、`pyexpat` 拡張がロード不可になることに起因する。**Phase 3-A の E2E テストは xmlrpc.client を避け、`urllib.request` で XML-RPC リクエストを直接 POST する**（expat を経由しないため Python ビルドの差異に左右されない）。レスポンスも XML パースせず `<methodResponse>` の文字列存在 + 期待メソッド名の存在チェックで判定する。CI の Python（macOS 3.13 / Windows 3.12）では `xmlrpc.client` 自体は動くが、テストランナーの一貫性のため全環境で同じ実装を使う。Spix 自身のメソッド一覧は AnyRPC の `system.listMethods` 経由で取得できる。**v0.14 で実際に返るメソッド名**：`mouseClick` / `mouseClickWithOffset` / `mouseClickWithProportion` / `mouseClickWithButton` / `mouseBeginDrag` / `mouseEndDrag` / `mouseDropUrls` / `getStringProperty` / `setStringProperty` / `existsAndVisible` / `waitForItem` / `wait` / `inputText` / `invokeMethod` / `enterKey` / `quit` / `getBoundingBox` / `getErrors` / `takeScreenshot` / `takeScreenshotAsBase64` / `system.listMethods` / `system.methodHelp`。**`getProperty` という名前は存在しない**ので注意（`getStringProperty` を使う）。
- **Spix の drag は item 中央間の drag&drop モデル、自由座標は取れない**：`mouseBeginDrag(path)` / `mouseEndDrag(path)` は **source / dest item の中央** で mouseDown → mouseMove → mouseUp を発火するだけで、座標オーバーロード（`mouseBeginDrag(path, x, y)` のような）は存在しない。さらに Qt 6.11 + `QT_QPA_PLATFORM=offscreen` 環境では Spix が `QGuiApplication::postEvent` で投げる中間 `mouseMove` が drag 閾値判定に到達せず、Editor 側の `MouseArea.drag.target` が動かないことを Task 18 で確認した。**Phase 3-A の E2E では座標変更を `setStringProperty(path, "x", "<n>")` で代替する**。Task 18 / 19 / 20 のスコープ「Editor の状態を E2E から変更し反映パスが通る」を担保するには十分。実マウスドラッグの動作確認は Phase 3-B（実機 / Yocto）の手動テストか、Spix の Qt 6 サポートが改善した段階で別タスクとして追加する想定。
- **`waitForItem(path, millisecondsToWait)` は 2 引数必須**：ms を省略すると AnyRPC が引数不足で即 `false` を返し、ハーネスが「item が出ていない」と誤判定する。Task 18 では `waitForItem(path, 2000)` のように明示する。
- **Spix の `getStringProperty` レスポンスは型タグ無しの `<value>50</value>`**：XML-RPC 仕様で「型タグなしの `<value>` は string」とみなす。AnyRPC は `<value><string>...</string></value>` でなく `<value>...</value>` で返すことがあるため、テスト側の正規表現は両対応で書く：`r"<value>(?:<string>)?\s*(-?\d+(?:\.\d+)?)\s*(?:</string>)?</value>"`。
- **Repeater + `var` array model で `setStringProperty` の結果がバインディング再評価で巻き戻る**：Task 19 で確認。Canvas.qml は `widgetModel = widgetModel.concat([...])` で配列丸ごと差し替える設計（QML の `var` 配列は in-place push でバインディング通知が出ないための回避策）。これにより Repeater が delegate を再生成し、`x: modelData.x` 等のバインディングも再評価される。**`setStringProperty` でバインディングを切って入れた値は、再生成された delegate では消える**。E2E では **「Repeater のサイズを変える操作（`addWidgetButton` の `mouseClick` 等） → 全 widget の座標変更」の順序を固定**する。座標を変えた後で `addWidget` 系を呼ぶと、それより前に動かした widget は初期値に戻る。`getStringProperty` で値を取り直して assert する形にしておくと、再生成事故が起きた時に即 fail で気づける。
- **FileDialog は Spix から自動操作できないため、Window 直下に Q_INVOKABLE 相当の QML 関数を生やして `invokeMethod` で呼ぶ**（Task 19 で確立）。`saveDialog.onAccepted` のロジックを `function saveTo(path) { ... }` のように関数化し、Spix 側で `invokeMethod(windowObjectName, "saveTo", [path])` を呼ぶ。本体 UI には影響しない（手動操作は依然として FileDialog 経由）。`objectName` を付けるのと同じ「E2E ハンドル化のための最小侵入」原則の延長線で、AppleScript / Spix の `mouseClick(FileDialog 内のボタン)` の代替として汎用的に使える。
- **`invokeMethod` の第 3 引数は array（XML-RPC `<array><data>...</data></array>`）として渡す**：Spix のシグネチャは `invokeMethod(string path, string method, any[] args)`。引数 0 個でも空 array `<array><data></data></array>` を渡す必要がある。`harness.py` の `_encode_value` に list/tuple → array エンコードを追加してあるので、テスト側は `call_method(url, "invokeMethod", path, method, [arg1, arg2])` のように **Python list で第 3 引数を渡す**。スカラ単体で展開（`call_method(... method, arg1, arg2)`）すると XML-RPC のシグネチャ不一致で fault レスポンスになる。
- **Editor の起動時自動ロードは Simulator と揃えて `--open <path>` 命名で統一**（Task 19）：[Docs/phase3-e2e-plan.md](Docs/phase3-e2e-plan.md) は当初 `--load` で計画していたが、Simulator が Task 8 で採用済みの `--open` に統一した。実装も Simulator 側の Task 8 パターン（`QCommandLineParser` で値オプション化 → `QFileInfo` で絶対パス化 → `setContextProperty("initialJsonUrl", QUrl)` → QML `Component.onCompleted` で `projectIo.load()`）をそのまま流用する。新たに「起動時オプション」を Editor 系アプリに足すときも同じ命名で並べる。
- **Window と Widget delegate の objectName はアプリごとに `<app>Window` / `widget_<id>` で命名統一**（Task 20）：Editor は `hmiEditorWindow`、Simulator は `hmiSimulatorWindow`。Widget delegate は両アプリとも `widget_<id>`（例：`widget_btn001`）。**cross-app E2E（Editor → JSON 保存 → Simulator が描画）では Window 名を取り違えると `existsAndVisible` が無反応で返ってくる**ため、テストランナー側で `_EDITOR_WIN` / `_SIM_WIN` の 2 定数に分け、フェーズごとにどちらを使うか明示する。Simulator 側 delegate は Editor の EditableWidget と違い中身が plain `Item` だが、objectName を直に Item に付けるだけで `existsAndVisible` / `getStringProperty("x")` が同様に通る。新規アプリを足したら（Phase 3-B Runtime 等）同じ命名（`hmiRuntimeWindow` 等）で揃える。
- **cross-app E2E は 2 つの Spix エンドポイントを順次起動する**（Task 20）：Editor=9876 / Simulator=9877 と既定ポートを分けてあるため同時起動も可能だが、`spix_app` contextmanager の with ブロックを 2 段に重ねて **前者を terminate してから後者を起動** する設計にする。デバッグ時に「今どっちが落ちているか」が一目で分かるのと、子プロセスを 2 つ同時に抱え込まないためテストランナーの後始末が単純になる。中間ファイル（JSON）は `tempfile.mkstemp` で確保 → 空ファイル削除 → Editor の `saveTo` で新規作成、最後に finally で `os.unlink`。Task 19 で確立した mkstemp パターンをそのまま再利用できる。
- **GitHub Actions CI でも `ctest -L e2e` をそのまま使える**（Task 21）：harness.py が `env.setdefault("QT_QPA_PLATFORM", "offscreen")` で offscreen を強制するので、ランナーに display が無くても動く。Windows MinGW では `tests/e2e/CMakeLists.txt` 側で `HMI_ENABLE_E2E=OFF` を検出して `add_test` を呼ばないため E2E は登録されず、`ctest -L e2e` は **「no tests matched」を warning で出すだけで exit 0 を返す**（fail しない）。ジョブを OS 別に分けなくても 1 つの matrix エントリで「macOS は 4 件走る / Windows は 0 件でスキップ」の両立が実現できる。Python ランナーは `actions/setup-python@v5` で明示インストールしておくと将来のランナー更新に強い。

## Qt バージョンの罠（CI / aqtinstall）

**CI 用 Qt バージョンはローカル開発バージョン（6.11.x）と必ずしも一致させない**。Task 15 初回ランで `version: "6.11.0"` を `jurplel/install-qt-action@v4` に渡したら、両 OS で aqtinstall が `Failed to locate XML data for Qt version '6.11.0'`（`download.qt.io/online/qtsdkrepository/.../qt6_6110/Updates.xml` 不在）で落ちた。Qt 公式 mirror の最新リリースは Updates.xml の同期に遅れがあるため、CI では **1〜2 マイナー下げた安定取得可能なバージョン（現状 6.10.0）** を使うと信頼性が高い。Qt 6.x の minor 互換でテスト緑判定は維持される。バージョンを上げる時は事前に `aqt list-qt <host> desktop --spec "<X.Y>"` で取得可能性を確認する。詳細パターンは [Docs/phase2-testing-plan.md](Docs/phase2-testing-plan.md) の「Task 15 で確立したパターン」を参照。

## Windows 環境の罠（要注意）

- **PowerShell の ExecutionPolicy が Restricted だと `.ps1` を直接起動できない**。VSCode のターミナルや素の `powershell.exe` で `.\scripts\windows\build.ps1` を叩くと `UnauthorizedAccess` で拒否される。初回セットアップ時に一度だけ `Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force` を実行する（CurrentUser スコープなので管理者権限不要、Microsoft 推奨の開発者向け設定）。設定後は VSCode のターミナルを開き直して反映させる。
- **日本語コメントを含む `.ps1` は UTF-8 with BOM で保存する**。Windows PowerShell 5.1 は BOM 無し UTF-8 を cp932 と誤認し、`The string is missing the terminator` でパースエラーになる。Edit/Write 直後は BOM 無しになることがあるので、`scripts/windows/` 配下の `.ps1` を新規作成・更新したら `[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($true))` で付け直す。
- **`-DKEY=$var` 形式の native コマンド引数は変数展開されない**。`cmake ... -DCMAKE_BUILD_TYPE=$BuildType` のように裸で書くと、PS 5.1 は `$BuildType` をリテラルとして cmake に渡す。引数全体を `"-DCMAKE_BUILD_TYPE=$BuildType"` のように **ダブルクォートで囲む** こと（シングルクォートだと展開されない）。
- **CMake が VS の `cl.exe` を掴まないようにする**。Windows には Visual Studio Build Tools が同居していることが多く、PATH 先頭に Qt 付属 MinGW を入れないと CMake が MSVC を選んで Qt MinGW kit と ABI 不一致になる。`scripts/windows/setup-env.ps1` がこれを担保する。
- **EXE の出力先が macOS と違う**。Windows は `build-mingw\hmi_<name>.exe`（ビルドツリーのトップ）に出る。macOS は `build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor`。
- 詳細・他の罠は [qt6-build](.claude/skills/qt6-build/SKILL.md) を参照。

---

## 削除可能なプレースホルダー（タスク到達時のみ削除）

削除可能なプレースホルダーは現在ありません（`Shared/Schema/src/schema_placeholder.cpp` は Task 3、`Shared/Widgets/qml/Placeholder.qml` は Task 4 で削除済み）。

実ソース追加と同時に対応する `CMakeLists.txt` の `QML_FILES` / ソース一覧を更新し、スタブを削除する。

---

## Schema 実装規約（`Shared/Schema`）

Task 3 で定着したスタイル。新しいデータ型を追加するときも踏襲する。

- **型は struct + namespace `hmi::schema`** で表現する（Q_GADGET / Q_OBJECT は必要になるまで付けない。Task 3 時点では QML 直接 expose しないため）。
- **ヘッダ配置**：`Shared/Schema/include/hmi/schema/<TypeName>.h`。利用側は `#include "hmi/schema/<TypeName>.h"`。
- **ソース**：`Shared/Schema/src/<TypeName>.cpp`。新規追加時は `Shared/Schema/CMakeLists.txt` の `qt_add_library(hmi_schema STATIC ...)` 一覧にも追記する。
- **JSON I/O**：各型に `QJsonObject toJson() const;` と `static <T> fromJson(const QJsonObject &);` を持たせる（メンバ関数 + 静的ファクトリ）。`QJsonDocument` は最上位（Project）でのみ使用する想定。
- **省略可能フィールド**：`toJson()` で `isEmpty()` 判定して書き出しを省略する（Widget の `text` / `tag` が前例）。
- **JSON 検証 API**：各型に `static bool isValidJson(const QJsonObject &);` も持たせる（Task 7 で定着）。`fromJson` はキー欠落時に既定値で埋める緩い設計なので、Editor / Simulator の読込側は **必ず `ProjectData::isValidJson` を通してから `fromJson` を呼ぶ**。検証は階層構造的に：`ProjectData::isValidJson` → `ScreenData::isValidJson` → `WidgetData::isValidJson` と再帰し、Shared/Schema 側に検証ロジックを集約する（利用側に検証コードを散らさない）。新しい必須フィールドを足す型変更時は `isValidJson` も同時に更新する。

---

## QML モジュール規約

- すべての QML モジュールは `qt_add_qml_module` で **明示的に `URI` を付与**（`HmiEditor` / `HmiSimulator` / `HmiWidgets`）。
- `Shared/Widgets` は `OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/HmiWidgets` を指定し、ビルドパスを URI と一致させる（Qt の警告防止）。
- QML ロードは `loadFromModule(URI, "Main")` を使用し、`qrc:` パス指定は避ける。
- QML import は Qt6 形式（`import QtQuick` — バージョン番号無し）。
- **QtQuick 標準型と同名の QML ファイルを作らない**（`Canvas.qml` / `Rectangle.qml` / `Item.qml` / `Text.qml` / `Image.qml` / `Window.qml` / `Button.qml`〔Controls〕等）。`import QtQuick` だけでは標準型が優先解決され、`Cannot assign to non-existent property` 等のエラーになる。回避策はいずれか：
  - **プレフィックス命名**（推奨）：`EditorCanvas.qml` / `HmiButton.qml` のように接頭辞を付ける。
  - **自モジュールを明示 import**：`Canvas.qml` のような名前を採用した場合、利用側 QML に `import HmiEditor`（または `HmiWidgets`）を必ず記述する。
- 共有 Widget（`HmiWidgets`）を新規追加する際は、上記の命名衝突に特に注意する（`Button` / `Label` / `Slider` 等は Controls と衝突しうる）。
- **複数バイナリ間で共有する QML モジュールは `STATIC` でビルドし、利用側アプリで plugin ターゲットをリンクする**。これは Qt 公式の「Multiple QML Modules in One Binary」推奨構成：
  - 共有側（`Shared/Widgets/CMakeLists.txt`、`Simulator/CMakeLists.txt` の `hmi_simulator_qml`）：`qt_add_qml_module(<name> STATIC URI <Uri> ...)`
  - 利用側（`Editor` / `Simulator` / `Runtime`）：`target_link_libraries(<app> PRIVATE <name>plugin)`
  - 動的ビルド（`STATIC` を付けない）だと plugin が `MODULE_LIBRARY` になり `target_link_libraries` がエラーになる。
  - **単一バイナリ専用** の QML モジュール（例：`HmiEditor` URI）は実行ファイル直結（`qt_add_qml_module(hmi_editor URI HmiEditor ...)`）のままで OK。STATIC 化は別バイナリと共有する場合のみ必須。
  - 代替として利用側で `IMPORTS HmiWidgets` を宣言する書き方もあるが、本プロジェクトの Qt 6.11（Homebrew）構成では自モジュール（`HmiEditor`）のリソース解決と競合して `No module named "HmiEditor"` で起動失敗した実績がある。STATIC plugin + 直リンクが唯一動作確認済みの方法。
  - Yocto / i.MX8MP の組み込みデプロイでも静的リンクの方が dylib 配布パスの問題を避けられて好都合。
- **`default property alias content: <inner>.data` で受けた子要素の `parent` は内部 Item を指す**。たとえば `EditableWidget` は内部 `container` に子を流し込むため、Main.qml で `EditableWidget { HmiButton { text: parent.widgetText } }` と書くと `parent` は `container` を指してしまい、`widgetText`（root のプロパティ）が undefined になる。回避策：外側 Item に `id` を付け、子からは `id` 経由で参照する（例：`EditableWidget { id: btn; HmiButton { text: btn.widgetText } }`）。Canvas.qml も同じ構造のため同様の注意が必要。
- **C++ ヘルパーを QML に公開するときは `setContextProperty` が最も軽い**。Editor 側に存在する一時的なコントローラ（例：`ProjectIo`）は `engine.rootContext()->setContextProperty("projectIo", &io)` でグローバル変数として QML から呼べる。`qmlRegisterType` / QML_ELEMENT は型インスタンス化が必要な場合に使う。**`hmi_schema` 等の Shared ライブラリは QML を一切知らないことを保ち**、QML 連携クラスは利用側アプリ（Editor / Simulator）に置く。
- **Editor / Simulator で同等の C++ ヘルパーが必要になる場合、Shared に移さず両方に独立して持つ**（Task 8 で確立）。Editor `ProjectIo`（save + load）と Simulator `ProjectLoader`（load のみ）は load() の実装がほぼ同一だが、責務（編集 vs 読み取り専用）が異なるため Shared に統合しない。Shared への昇格を検討するのは、save 側にも同等の機能差が現れた時のみ。それまでは「重複を許容、利用側完結」を優先する。
- **Simulator と Runtime はソース完全共通**（Phase 3-B / Task 22 で確立済み）。Editor との関係（独立保持）とは別に、Runtime は Simulator/ のソースを `Runtime/CMakeLists.txt` の CMake glue で再利用して `hmi_runtime` バイナリを生成する。Runtime/ には `.cpp` / `.qml` / `.h` を置かない。Runtime に追加機能が必要な場合も Simulator/ 側で編集し、必要なら `#ifdef HMI_RUNTIME_BUILD` で振る舞いを分岐する。QML モジュール URI も Simulator と同じ `HmiSimulator` を再利用する（モジュール名を変えるとソース共有が崩れる）。詳細は [Docs/phase3b-runtime-plan.md](Docs/phase3b-runtime-plan.md)。
- **ソース共有の具体的 CMake 技法は「共通 function + `CMAKE_CURRENT_FUNCTION_LIST_DIR`」を採用**（Task 22 で確立）。`Simulator/CMakeLists.txt` で `function(hmi_add_simulator_like_executable target)` を定義し、関数内で `qt_add_executable(${target} ${CMAKE_CURRENT_FUNCTION_LIST_DIR}/src/main.cpp ...)` のように **関数定義位置のディレクトリ** を絶対パス基準にする。`Runtime/CMakeLists.txt` は `hmi_add_simulator_like_executable(hmi_runtime)` の 1 行だけ。CMake function はグローバルスコープなので、ルート `CMakeLists.txt` で `add_subdirectory(Simulator)` を `add_subdirectory(Runtime)` より **前** に置く必要がある（順序を逆にすると関数未定義エラー）。`CMAKE_CURRENT_FUNCTION_LIST_DIR` 自体は CMake 3.17+ で導入された機能だが、**本リポジトリは root `CMakeLists.txt` で `cmake_minimum_required(VERSION 3.21)` を指定しているため、Yocto SDK 側の CMake は 3.21 以上が必須**（3.17〜3.20 だと configure 時点で落ちる。Task 23 着手時に SDK の `cmake --version` を確認する）。QML module 側は同じ Simulator/CMakeLists.txt で `qt_add_qml_module(hmi_simulator_qml STATIC URI HmiSimulator ...)` として STATIC plugin 化し、function 内の `target_link_libraries` で両バイナリに `hmi_simulator_qmlplugin` を取り込む（CLAUDE.md 既出の Shared/Widgets と同パターン）。実行ファイルに直結したまま QML module を宣言した状態では別バイナリから共有できないため、STATIC 化は必須。
- **Task 22 時点では `hmi_runtime` のウィンドウタイトル・applicationName は `hmi_simulator` と同じ**（[Simulator/qml/Main.qml](Simulator/qml/Main.qml) の `Window.title = "HMI Simulator"`、[Simulator/src/main.cpp](Simulator/src/main.cpp) の `setApplicationName("hmi_simulator")`）。これは計画書「Task 22 段階では分岐ゼロのまま、Task 24 で実機差異が見えてから `#ifdef HMI_RUNTIME_BUILD` を入れる」方針に従った意図的な現状。Task 24 で実機初期化を入れる時に分岐すれば良い。Codex レビューでウィンドウタイトルが Simulator のままなことを指摘されたら本方針を根拠に説明する。
- **Simulator のような起動時自動ロード機能が欲しい時は CLI 引数 + `setContextProperty` の組み合わせが軽い**（Task 8 で確立）。`main.cpp` で `QCommandLineParser` から取った `QUrl` を `initialJsonUrl` 等の名前で context に詰め、QML 側 `Component.onCompleted` で空判定して `projectLoader.load()` を呼ぶ。これは FileDialog の自動操作が AppleScript で不可能な問題（動作証跡セクション参照）を回避する正攻法でもある。
- **QtQuick.Controls / QtQuick.Dialogs は QML `import` だけで動く**（Qt 6.5+）。CMake で `Qt6::QuickControls2` 等を明示リンクしなくても plugin が動的にロードされるため、`target_link_libraries` への追加は不要。デプロイ時のみ `windeployqt` / `macdeployqt` で plugin 同梱を確認する。
- **`FileDialog.selectedFile` は `file:///...` 形式の `QUrl`**。C++ で受けるときは `QUrl::toLocalFile()` で OS パスに変換してから `QFile` / `QSaveFile` に渡すこと（`toString()` だと `file://` が残って書き込みに失敗する）。書き込みは `QSaveFile` を使い `commit()` で原子的に保存するのが安全。

---

## 動作証跡スクリーンショット運用

GUI に変化がある PR（MVP Task 2 / 4 / 5 / 8 のような Editor / Simulator の見た目が変わるもの、UI 系の bugfix）には **スクリーンショットを必ず添付する**。Codex / 人間レビュアーの両方が、コードを脳内実行せず「実際にこう見える」を確認できるようにするため。

### 撮影手順（macOS）

対象アプリ（Editor / Simulator）に応じて起動バイナリとプロセス名を切り替える：

```sh
# Editor の変更を撮る場合
./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor &
sleep 2
scripts/capture-app-window.sh hmi_editor Docs/screenshots/task-<N>-<短い名>.png
kill %1

# Simulator の変更を撮る場合
./build/Simulator/hmi_simulator.app/Contents/MacOS/hmi_simulator &
sleep 2
scripts/capture-app-window.sh hmi_simulator Docs/screenshots/task-<N>-<短い名>.png
kill %1
```

両方の見た目が同時に変わるタスク（例：Task 8 で Editor の保存形式と Simulator の表示を同時に検証したい場合）は両方のスクショを撮り、`Docs/screenshots/task-<N>-<短い名>-editor.png` と `-simulator.png` のように suffix を付けて両方コミットする。

- `scripts/capture-app-window.sh` は Swift で `CGWindowListCopyWindowInfo` を呼び対象プロセスのウィンドウ ID を取得し、`screencapture -l<wid>` で当該ウィンドウのみを切り出す（Retina 倍率は自動考慮、アクセシビリティ権限不要、**画面収録権限のみ**が必要）。
- **初回のみ macOS の画面収録権限を Claude Code 親プロセス（Visual Studio Code / ターミナル）に付与する必要がある**。システム設定 > プライバシーとセキュリティ > 画面収録 で対象アプリを ON にし、再起動。
- Windows でのキャプチャは未対応（必要になったタスクで `scripts/windows/` 配下に PowerShell 版を追加する）。
- **AppleScript で Qt QML の Button を自動クリックする手段は事実上ない**（Task 7 で確認）。`tell application "System Events" to click at {x, y}` の CGEvent も、Accessibility の `click button "name" of window 1` も、QML のクリックイベントとして受理されない（座標は正しくても無反応）。FileDialog を介する読込・保存系の動作証跡が必要な場合は、(a) 起動直後の初期状態だけスクショして「ボタンが追加されたこと」を見せる、(b) どうしても「操作後の状態」を撮りたいなら、テスト用に環境変数や CLI 引数で初期 JSON を自動ロードする小機能を当該タスクに含める、のいずれかを選ぶ。最初から無理に automate しようとせず手動補完で済ませる判断もあり。

### ファイル配置と PR への埋め込み

- 出力先：`Docs/screenshots/task-<N>-<短い名>.png`（branch 名と揃える）
- PR 本文には **commit SHA 固定の raw URL** で参照する。タスクブランチ削除後も生きる：
  ```markdown
  ## Screenshot
  ![Task N: <短い説明>](https://raw.githubusercontent.com/hang-up33/hmi-platform/<commit-sha>/Docs/screenshots/task-<N>-<短い名>.png)
  ```
- SHA は push 後 `git rev-parse HEAD` で取得。PR 本文を `gh pr edit <N> --body-file ...` で更新する場合も同じ SHA を使い続ける（後続の修正コミットでスクショ自体を撮り直したら SHA も更新する）。
- GUI 変化が無いタスク（純粋な Schema / docs / CMake のみ）はスクショ省略可。

### README 掲載スクショの同期

README.md には **「常に最新」を表す固定ファイル名** のスクショを別途掲載している（[README.md](README.md) の「スクリーンショット」節）。

| 固定ファイル | 対応アプリ |
|---|---|
| `Docs/screenshots/editor.png` | Editor |
| `Docs/screenshots/simulator.png` | Simulator（必要になったタイミングで追加） |

- **Editor / Simulator の見た目が変わる PR では、`task-<N>-<短い名>.png` を撮るのと同じコミットで `editor.png` / `simulator.png` も上書きで撮り直す**。`task-*.png` は SHA 固定で時系列の証跡を残す用途、`editor.png` / `simulator.png` は README から相対パス参照で「現状を見せる」用途。役割が違うので両方更新する。
- 上書きコマンド例（Editor の場合）：
  ```sh
  ./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor &
  sleep 2
  scripts/capture-app-window.sh hmi_editor Docs/screenshots/editor.png
  kill %1
  ```
- README から相対パス参照しているため、固定ファイル名はリネームしない（リネームすると README のリンクが切れる）。
- 純粋に GUI 変化が無い PR（Schema / docs / CMake / テストのみ）は README スクショも更新不要。

---

## ファイル命名規約

- 小文字 + ハイフン区切り（例：`mvp-task-runner.md`, `qt6-build/SKILL.md`）
- エージェント：`.claude/agents/<name>.md`（YAML frontmatter に `name` `description` `tools` `model`）
- スキル：`.claude/skills/<name>/SKILL.md`（YAML frontmatter に `name` `description` `origin`）
- コミットメッセージ：`Task N: <短い説明>` を基本フォーマットとする

---

## 対象プラットフォーム

開発・動作確認は **macOS と Windows の両方**で実施（Editor / Simulator / Runtime PC ビルドともに GUI 起動確認済み）。**Phase 3-B-1 / Task 22 で 3 バイナリ構成（hmi_editor / hmi_simulator / hmi_runtime）に拡張済み**（Simulator のソースを共有して `hmi_runtime` バイナリを生成、ホスト PC で起動確認済み）。残りの Task 23（Yocto SDK でのクロスビルド）・Task 24（i.MX8MP 実機 scp + 起動）は未着手。詳細は [Docs/phase3b-runtime-plan.md](Docs/phase3b-runtime-plan.md)。

### Claude Code on the web は非対応

**Claude Code on the web では本プロジェクトの実装作業を行わない**。フェーズタスクや Codex 指摘対応は必ず macOS / Windows のローカル環境で実施する（Phase 3-B-2 / Task 23 以降は WSL2 での Yocto SDK クロスビルドも追加）。

理由（2026-05 時点で調査済）：

- 本プロジェクトは Qt 6.5+ を要求するが、Web 版コンテナ（Ubuntu 24.04）の apt は Qt 6.4.2 までしか提供しない。
- aqtinstall で公式 Qt を取得しようとすると、コンテナの既定ネットワークポリシーが `download.qt.io` / `ftp.jaist.ac.jp` / `mirrors.dotsrc.org` 等 Qt ミラーを `host_not_allowed` (HTTP 403) で全遮断する。
- 結果、`cmake --build` が通せずビルド検証ができない。GUI 動作確認も不可のため、ビルドが通ったとしても MVP の受け入れ基準を満たせない。

Web 版で実装を進める運用は採用しない。Claude Code on the web のセッションを開いてしまった場合も、フェーズタスクや Codex 指摘対応に着手せず、ローカル環境に切り替えてから作業すること。
