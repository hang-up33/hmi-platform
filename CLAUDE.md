# CLAUDE.md

このファイルは、本リポジトリで作業する Claude Code（claude.ai/code）への指針です。
**ユーザーは日本人のため、応答・ドキュメント・コミットメッセージは日本語を基本とします**（コード識別子は英語可）。

> **本プロジェクトの開発コードネームは「Atlas（アトラス）」**（プロジェクト全体のブランド別名・開発時の通称）。正式なリポジトリ名・CMake プロジェクト名・QML URI 等は従来どおり（`hmi-platform` / `hmi_*` / `Hmi*`）で、リネームはしない。Atlas はあくまで README 冒頭などで用いる愛称。由来はギリシャ神話で天空を支える巨神アトラス（Editor / Simulator / Runtime / Shared を束ねて支える基盤の含意）。

---

## プロジェクト概要

Yocto / i.MX8M Plus 向け Qt6 HMI ランタイムを対象に、HMI 作画ツール（Editor）・PC 試験環境（Simulator）・実機ランタイム（Runtime）・JSON スキーマ（Shared/Schema）・共有 Widget（Shared/Widgets）を統合した開発基盤。詳細は [README.md](README.md)。タスクごとの時系列まとめ（目的 / PR / 成果物 / 学び）は [Docs/development-history.md](Docs/development-history.md) — 第三者説明用で、タスク完了時に当該 Task のエントリを追記する運用候補。**苦労の多かったタスク／フェーズでは、事実だけでなく「奮闘記」（postmortem）も残す**：障害の連鎖を「どう乗り越えたか・その時の判断と心境」まで物語として `Docs/<phase>-journey.md` に記録する（役割分担＝事実・罠は development-history / dev-environment.md、"どう抜けたか・心境" は奮闘記。初出は [Docs/phase3b-runtime-journey.md](Docs/phase3b-runtime-journey.md)）。**開発環境の現状（ホスト構成・ディスク事情・WSL/Yocto ビルド環境・実機 i.MX8MP の状態）は [.claude/rules/dev-environment.md](.claude/rules/dev-environment.md) に集約**（`.claude/rules/` は git 管理＋毎セッション自動読込される Claude Code のメモリ機構。Claude の自動メモリ `~/.claude/projects/.../memory/` はマシンローカルで Windows ↔ Mac を跨がないため、マシン横断の環境知識はこちらを正とする）。

**現在のフェーズ**：**Phase 3-B / Runtime（Task 22〜24）完了**、次は **Phase 4 / Button 縦スライス（Task 25〜30）** に着手。Phase 1 / MVP（Task 1〜8）、Phase 2 / テスト基盤導入（Task 9〜15）、Phase 3-A / E2E テスト導入（Task 16〜21）、**Phase 3-B / Runtime（Task 22〜24）** まで完了済み。Task 22 で **Simulator の QML module を STATIC 化 + 共通 CMake function `hmi_add_simulator_like_executable` で hmi_simulator / hmi_runtime の 2 バイナリを同一ソースから生成** する構成を確立。Task 23/24 で **NXP 新 BSP（scarthgap）から Qt6 入り実機 image と Qt6 クロス SDK（`meta-toolchain-qt6`）を生成し、`hmi_runtime` を aarch64 にクロスビルド → i.MX8MP 実機（weston / Wayland / Qt6 6.8.1）で Editor 由来の JSON を描画**するところまで到達（詳細は [Docs/phase3b-runtime-plan.md](Docs/phase3b-runtime-plan.md)、奮闘記 [Docs/phase3b-runtime-journey.md](Docs/phase3b-runtime-journey.md)）。E2E フレームワークに **Spix（OSS / MIT）** を採用し、Editor 配置 → JSON 保存 → Simulator 表示までの cross-app 動作を `ctest -L e2e` で検証可能。**macOS は E2E まで含む `ctest` 緑、Windows MinGW は AnyRPC の libstdc++ 衝突回避のため `HMI_ENABLE_E2E` が既定 OFF・E2E は既知スキップで通常 ctest のみ緑**（詳細は後述「Spix（E2E）統合の罠」最終項）。GitHub Actions CI も同様にユニットは全 OS、E2E は macOS のみで実行する構成。3 バイナリ構成（hmi_editor / hmi_simulator / hmi_runtime）を維持。**次の Phase 4 / Button 縦スライス（Task 25〜30）** は、Widget 種別を横に増やす前に **Button 1 つを全レイヤ（Schema→Widgets→Editor→Simulator→Runtime→実機）で深く作り込み「Widget 追加テンプレ」を確立**する（選択・インスペクタ・リサイズ・削除・スタイル属性の Schema 拡張）。タスク分割と完了基準は [Docs/phase4-button-slice-plan.md](Docs/phase4-button-slice-plan.md) を参照。

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

# Explorer からダブルクリック起動したい場合は windeployqt で DLL を同梱する
.\scripts\windows\deploy.ps1                 # 両 exe に windeployqt を実行
.\scripts\windows\build.ps1 -Deploy          # build と同時に実行する場合
```

Windows は **Qt 6.11.0 MinGW 64-bit kit + 付属 MinGW 13.1 + Ninja** を前提とする（MSVC kit は未使用）。`scripts/windows/setup-env.ps1` が Qt 付属ツールチェイン（MinGW / Ninja / CMake）を PATH 先頭に挿入することで、システム側の VS `cl.exe` や別 MinGW を回避する。詳細・罠は [qt6-build](.claude/skills/qt6-build/SKILL.md) スキル参照。

**Explorer からダブルクリックで開かない（「Qt の DLL が見つからない」）場合**は、`setup-env.ps1` を読み込んでいないシェル / Explorer が Qt・MinGW の `bin` を PATH に持たないため。`scripts/windows/deploy.ps1`（中身は `windeployqt --release --compiler-runtime --qmldir <qml>`）で Qt6 DLL・MinGW ランタイム（`libstdc++-6.dll` 等）・プラグイン（`platforms\qwindows.dll`）・QML モジュールを exe の隣へ配置すると自己完結する。**`build-mingw` をクリーン消去した後は再実行が必要**（DLL も消えるため）。`setup-env.ps1` を dot-source した開発シェルから起動する分には不要。

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

- 現フェーズのタスク順を守る。Phase 1 / MVP（Task 1〜8）、Phase 2 / テスト基盤導入（Task 9〜15）、Phase 3-A / E2E テスト導入（Task 16〜21）、**Phase 3-B / Runtime（Task 22〜24）** は完了済み（i.MX8MP 実機描画まで到達）。**次は Phase 4 / Button 縦スライス（Task 25〜30）**（[Docs/phase4-button-slice-plan.md](Docs/phase4-button-slice-plan.md)）。次セッションで「次のタスクを進めて」と指示があれば **Task 25（選択モデル + 選択枠）** から着手する。Phase 4 は Widget 種別を横に増やす前に Button 1 つを全レイヤで深く作り込み「Widget 追加テンプレ」を確立する縦スライス（選択・インスペクタ・リサイズ・削除・スタイル属性の Schema 拡張）。各タスクの完了基準・設計指針・Must Never は [Docs/phase4-button-slice-plan.md](Docs/phase4-button-slice-plan.md) を参照。Phase 3-B（Yocto / 実機）の環境知識は [.claude/rules/dev-environment.md](.claude/rules/dev-environment.md) に集約済み。
- Widget / Screen / Project 型と JSON I/O は `Shared/Schema` にのみ実装。
- 完了報告の直前に [kaizen-close](.claude/skills/kaizen-close/SKILL.md) を実行し、得た知見を反映する。
- QML モジュール URI とアプリの `loadFromModule()` 引数を一致させる。
- 出力（応答・ドキュメント・コミットメッセージ）は日本語を基本とする。
- 環境固有の事実（開発ホスト構成・ディスク事情・WSL/Yocto ビルド環境・実機 i.MX8MP の状態・シリアル設定等）が変わったら、[.claude/rules/dev-environment.md](.claude/rules/dev-environment.md) を更新する。これは git 管理＋自動読込される Claude Code のルール（`.claude/rules/`）で、マシンローカルな自動メモリと違い Windows ↔ Mac を跨いで共有されるため、マシン横断で必要な環境知識はここを唯一の真実とする。
- **新しい知見・好み・方針はマシンローカルの自動メモリ（`~/.claude/projects/.../memory/`）ではなく、git 管理＋自動読込される `.claude/rules/` に保存する**（2026-05-30 ユーザー指示）。理由は自動メモリが Windows ↔ Mac を跨がないため。1 知見 = 1 ファイル（小文字＋ハイフン区切り、frontmatter は `name` / `description` / `metadata.type` のみ。`node_type` / `originSessionId` のようなマシンローカル項目は付けない）で配置し、[.claude/rules/memory-index.md](.claude/rules/memory-index.md) に 1 行追記する。**コードの特定領域に紐づく規約は frontmatter に `paths:`（glob）を足して path-scoped rule にし、該当ファイルを編集する時だけロードさせる**（毎セッション常時ロードされる本ファイルや無条件 rule を肥大化させないため。例：[.claude/rules/qml-module-conventions.md](.claude/rules/qml-module-conventions.md) は `paths: ["**/*.qml", ...]`）。ただし CLAUDE.md / `Docs/*.md` に書ける「プロジェクト事実・設計判断」はそちらを正とし、二重メンテを避ける（rules に残すのは作業の進め方・好み等）。

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
- **起動中の `hmi_editor.exe` / `hmi_simulator.exe` を終了せずに再ビルドするとリンクが `cannot open output file ...: Permission denied` で失敗する**（Task 27 で遭遇）。Windows は実行中の exe を排他ロックするため、リンカが上書きできない。**コードのエラーではない**ので、`g++`/QML の構文を疑う前に `Get-Process hmi_editor | Stop-Process -Force` で起動中インスタンスを落としてから再ビルドする。動作確認で起動したアプリは**キャプチャ後に必ず `Stop-Process` する**運用にすると踏まない。
- **`deploy.ps1` / `build.ps1 -Deploy` を実行した後は offscreen の QML ctest が壊れる**（Task 26 で発覚）。`windeployqt` は `build-mingw\platforms\` に **`qwindows.dll` だけ**を配置するが、QML テスト exe（`tst_hmi_widgets_qml` / `tst_hmi_editor_qml`）は build-mingw 直下で動くため、この**ローカル `platforms\` が Qt 本体のプラグイン群（`qoffscreen.dll` 等）を隠す**。結果 `-platform offscreen` 起動が `0xc0000602`（STATUS_FAIL_FAST_EXCEPTION）で失敗し、しかも **「no Qt platform plugin could be initialized. Available platform plugins are: windows.」のモーダルダイアログが OK 待ちで張り付き、ctest が数百秒ハングする**（563 秒の実測あり）。回避策：ctest 実行時に `$env:QT_QPA_PLATFORM_PLUGIN_PATH = "C:\Qt\6.11.0\mingw_64\plugins\platforms"` を設定して Qt 本体の完全なプラグイン集合を明示する（ローカル `platforms\` より優先される）。`deploy.ps1` 未実行のクリーンな build-mingw では発生しない（Qt 本体の plugins へ素直にフォールバックするため）。デプロイ済みツリーで `ctest` が固まったらこの罠を疑う。
- 詳細・他の罠は [qt6-build](.claude/skills/qt6-build/SKILL.md) を参照。

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
| QML モジュール規約（URI・命名衝突回避・STATIC plugin 共有・EditableWidget の選択/編集/リサイズ結線・C++ ヘルパー公開・Simulator/Runtime ソース共有） | [.claude/rules/qml-module-conventions.md](.claude/rules/qml-module-conventions.md) | `**/*.qml` / `Editor/**` / `Simulator/**` / `Runtime/**` / `Shared/Widgets/**` |

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
- **AppleScript で Qt QML の Button を自動クリックする手段は事実上ない**（Task 7 で確認）。`tell application "System Events" to click at {x, y}` の CGEvent も、Accessibility の `click button "name" of window 1` も、QML のクリックイベントとして受理されない（座標は正しくても無反応）。FileDialog を介する読込・保存系の動作証跡が必要な場合は、(a) 起動直後の初期状態だけスクショして「ボタンが追加されたこと」を見せる、(b) どうしても「操作後の状態」を撮りたいなら、テスト用に環境変数や CLI 引数で初期 JSON を自動ロードする小機能を当該タスクに含める、のいずれかを選ぶ。最初から無理に automate しようとせず手動補完で済ませる判断もあり。

### 撮影手順（Windows）

Task 25 で `scripts/windows/capture-app-window.ps1`（PowerShell 版）を新設。`PrintWindow(PW_RENDERFULLCONTENT=2)` でウィンドウ単位に切り出すため、他ウィンドウに**隠れていても**対象アプリだけを撮れる（macOS の `screencapture -l<wid>` 相当）。

```powershell
. .\scripts\windows\setup-env.ps1
Start-Process .\build-mingw\hmi_editor.exe   # 起動
Start-Sleep -Seconds 3
.\scripts\windows\capture-app-window.ps1 -ProcessName hmi_editor -Out Docs\screenshots\task-<N>-<短い名>.png
Stop-Process -Name hmi_editor -Force
```

- 出力 PNG は **ウィンドウ枠（タイトルバー込み）** で、右下に数 px の黒縁が残ることがある（`GetWindowRect` と実描画域の差。動作証跡としては問題なし）。
- **Windows では macOS と違い Qt QML の Button を自動クリックできる**。Win32 `mouse_event`（実マウスメッセージ）は QML の `MouseArea` / `clicked` に届くため、`SetWindowPos(hWnd, HWND_TOPMOST, ...)` ＋ `BringWindowToTop` で対象を**最前面に固定**してから対象座標へ `SetCursorPos`→`mouse_event(LDOWN/LUP)` でクリックすれば「操作後の状態」（選択枠が出た状態など）を撮れる。AppleScript の CGEvent が無反応なのと対照的（理由：AppleScript は合成イベント、Win32 は実 OS マウスメッセージ）。
  - 注意：**背景プロセスからの `SetForegroundWindow` は Windows に抑制される**ことがあり、ウィンドウが他に隠れたまま注入クリックすると別ウィンドウに当たる。必ず `HWND_TOPMOST` 固定で前面に出してからクリックする。座標は `GetWindowRect` の左上 ＋ クライアント原点（`ClientToScreen`）＋ QML 上の論理座標から算出する（起動直後で対象が最前面なら `SetForegroundWindow` だけでも通る。Task 26 はこれで `btn001` を実クリックできた）。**クリック座標の簡便な求め方**：先に `capture-app-window.ps1` で撮ったスクショ画像内のピクセル位置 ＝ ウィンドウ原点からのオフセット（`PrintWindow` は物理解像度でキャプチャするため画像 px = `GetWindowRect.Left/Top` からの px オフセットに一致）。
  - **テキスト入力も自動化できる**（Task 26 で確立）。`TextField` を上記方式でクリックしてフォーカスさせた後、`[System.Windows.Forms.SendKeys]::SendWait("^a")`（全選択）→ `SendWait("Run")` でフォーカス中の入力欄に文字を流し込める。これで「選択 → インスペクタで text 編集 → キャンバス即反映」のような**操作後の状態**を Windows 上で完全自動キャプチャできる（IME 経由が必要な日本語は不安定なので、動作証跡用の入力は ASCII にする）。macOS で AppleScript が QML を操作できないのと対照的。

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

開発・動作確認は **macOS と Windows の両方**で実施（Editor / Simulator / Runtime PC ビルドともに GUI 起動確認済み）。**Phase 3-B / Task 22〜24 で 3 バイナリ構成（hmi_editor / hmi_simulator / hmi_runtime）に拡張済み**（Simulator のソースを共有して `hmi_runtime` バイナリを生成）。Task 23（Yocto SDK でのクロスビルド）・Task 24（i.MX8MP 実機 scp + 起動）も完了し、**実機（scarthgap / weston / Qt6 6.8.1）で Editor 由来 JSON の描画を確認済み**。詳細は [Docs/phase3b-runtime-plan.md](Docs/phase3b-runtime-plan.md)。

### Claude Code on the web は非対応

**Claude Code on the web では本プロジェクトの実装作業を行わない**。フェーズタスクや Codex 指摘対応は必ず macOS / Windows のローカル環境で実施する（Phase 3-B-2 / Task 23 以降は WSL2 での Yocto SDK クロスビルドも追加）。

理由（2026-05 時点で調査済）：

- 本プロジェクトは Qt 6.5+ を要求するが、Web 版コンテナ（Ubuntu 24.04）の apt は Qt 6.4.2 までしか提供しない。
- aqtinstall で公式 Qt を取得しようとすると、コンテナの既定ネットワークポリシーが `download.qt.io` / `ftp.jaist.ac.jp` / `mirrors.dotsrc.org` 等 Qt ミラーを `host_not_allowed` (HTTP 403) で全遮断する。
- 結果、`cmake --build` が通せずビルド検証ができない。GUI 動作確認も不可のため、ビルドが通ったとしても MVP の受け入れ基準を満たせない。

Web 版で実装を進める運用は採用しない。Claude Code on the web のセッションを開いてしまった場合も、フェーズタスクや Codex 指摘対応に着手せず、ローカル環境に切り替えてから作業すること。
