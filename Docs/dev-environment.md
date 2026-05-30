# 開発環境メモ（クロスマシン共有）

本リポジトリは **macOS と Windows 母艦（+ WSL2）** の複数マシンで開発する。
環境固有の知識（ホスト構成・ディスク事情・WSL/Yocto ビルド環境・実機 i.MX8MP の状態など）を
ここに **git 管理で集約** し、どのマシンからでも参照できるようにする。

> **なぜリポジトリに置くか**：Claude Code 等の「セッション横断メモリ」はマシンローカル（各 PC のホーム配下）に
> 保存され、Windows ↔ Mac では引き継がれない。環境固有の事実をこの文書に書いておけば git で全マシンに伝播する。

## 運用ルール

- **環境固有の事実が変わったらこの文書を更新する**（新マシン追加、ディスク構成変更、WSL/SDK 状態、実機 image 更新など）。
- 役割分担：
  - **この文書** = 環境・マシン・実機の「現状スナップショット」。
  - [phase3b-runtime-plan.md](phase3b-runtime-plan.md) ほか `Docs/phase*-plan.md` = フェーズ/タスクの設計判断と完了基準。
  - [development-history.md](development-history.md) = タスクごとの時系列まとめ（目的 / PR / 成果物 / 学び）。
  - [../CLAUDE.md](../CLAUDE.md) = 作業指針（ビルド手順・ルール・罠）。
- 重複が出たら、**手順・設計はプラン文書、環境の現状はこの文書**に寄せ、互いをリンクで結ぶ（同じ事実を二重メンテしない）。

---

## 開発ホスト一覧

| ホスト | OS | 役割 | ビルド出力 | Qt |
|---|---|---|---|---|
| **Windows 母艦** | Windows 11 | Editor / Simulator / Runtime のビルド・GUI 確認。**WSL2 内で Yocto SDK クロスビルド**（Task 23+） | `build-mingw/`（ビルドツリー直下に `hmi_*.exe`） | Qt 6.11.0 MinGW 64-bit kit + 付属 MinGW 13.1 + Ninja（MSVC kit 未使用） |
| **macOS** | macOS 14+（Darwin 25+） | Editor / Simulator のビルド・GUI 確認、動作証跡スクショ撮影 | `build/`（`.app` バンドル） | Homebrew Qt（`/opt/homebrew/opt/qt`、6.8+） |

- Editor / Simulator は両 OS で GUI 起動確認済み。Runtime（PC sanity 版）も Task 22 で両 OS ビルド確認済み。
- ビルド手順の詳細は [../CLAUDE.md](../CLAUDE.md)「ビルドと実行」と [qt6-build スキル](../.claude/skills/qt6-build/SKILL.md)。

### Windows 母艦の詳細

- 入口スクリプト：`scripts/windows/build.ps1`（configure+build）、`scripts/windows/setup-env.ps1`（dot-source で PATH 設定）。
- 主要パス：Qt = `C:\Qt\6.11.0\mingw_64`、MinGW = `C:\Qt\Tools\mingw1310_64`、generator = Ninja 固定。
- 罠（詳細は CLAUDE.md「Windows 環境の罠」）：
  - PowerShell 5.1 は BOM 無し UTF-8 を cp932 誤認 →`scripts/windows/*.ps1` は UTF-8 with BOM で保存。
  - VS の `cl.exe` や別 MinGW が PATH を汚染しないよう `setup-env.ps1` が Qt 付属ツールチェインを PATH 先頭に挿入。
  - EXE 出力先はビルドツリー直下（`build-mingw\hmi_editor.exe`）。macOS の `.app` とは構造が違う。
  - 初回のみ `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` が必要。

### macOS の詳細

- 構成：`cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt`。
- **AGL 罠**：同梱の `~/Qt/6.7.0/macos` は macOS 14+ でリンク不可（`-framework AGL` が削除済み）。**Homebrew Qt 6.11.x または Qt 6.8+ を使う**。詳細は qt6-build スキル。
- 動作証跡スクショ：`scripts/capture-app-window.sh <proc> <out.png>`（画面収録権限が必要）。Windows 版キャプチャは未整備（Phase 3-C 候補）。

---

## ディスク事情（Windows 母艦・2026-05-30 時点）

| ドライブ | 容量 | 空き | 主な用途 |
|---|---|---|---|
| **C:** | 476 GB | 約 80 GB | OS / 開発ツール（VS, Unity, dotnet…）/ ユーザープロファイル（AppData 等） |
| **D:** | 466 GB | 約 41 GB | ゲーム（Steam 約 386GB / Epic 約 38GB）。**Yocto 用に容量が足りなくなったら、ここのゲームを整理して空ける** |
| **E:** | 233 GB | 約 212 GB | **Yocto ビルド置き場**（2026-05-30 のディスク整理で 212GB を確保） |

- **Yocto ビルド方針（2026-05-30 決定）**：新 BSP（scarthgap）の image+SDK フルビルドは **100〜200GB** 規模。
  **E ドライブを使用し、足りなくなったら D ドライブ（ゲーム）を空ける**。
- **WSL distro の relocate が必要**：WSL の `ext4.vhdx` は現状 **C:**（`%LOCALAPPDATA%\wsl\{...}\ext4.vhdx`、約 2.5GB）にあり、
  WSL 内ビルドは C を消費する。E の空きを使うには Task 23 着手時に distro を E へ移す：
  ```powershell
  wsl --shutdown
  wsl --export Ubuntu-22.04 E:\wsl\ubuntu-2204.tar
  wsl --unregister Ubuntu-22.04
  wsl --import Ubuntu-22.04 E:\wsl\Ubuntu-22.04 E:\wsl\ubuntu-2204.tar --version 2
  ```
  `/mnt/e` への drvfs/9p 直ビルドは Yocto では遅く、権限・大小文字問題が出るため非推奨（vhdx ごと E へ置くのが正攻法）。

---

## WSL2 / Yocto ビルド環境（Windows 母艦）

Task 23（Yocto SDK で `hmi_runtime` をクロスビルド）用の WSL2 環境は **構築済み**（2026-05-30）。

- **distro**：`Ubuntu-22.04`（jammy, WSL2）。`wsl --install -d Ubuntu-22.04 --no-launch` で OOBE を回避して導入。
- **ユーザー**：既定ユーザー `ubuntu`（uid 1000, sudo グループ、パスワード無し sudo）。`/etc/wsl.conf` の `[user] default=ubuntu`。
- **Yocto ホスト依存**：build-essential / gawk / wget / git / diffstat / unzip / texinfo / chrpath / socat / cpio /
  python3・pip3・pexpect・jinja2 / xz-utils / zstd / lz4 / file / locales / libacl1 ほか導入済み。`en_US.UTF-8` 生成済み。gcc 11.4 / Python 3.10.12。
  host cmake は未導入（Yocto SDK が自前 cmake を同梱するため不要）。
- **罠（最重要）**：VM Platform を有効化しても、**「シャットダウン→電源 ON」では高速スタートアップが保留中の機能インストールを確定させず**、
  WSL2 が「仮想化が無効」で起動できないことがある。スタートメニューから明示的に **「再起動」** を選ぶと完全ブートして確定する。
  （`HypervisorPresent:True` かつ `VirtualizationFirmwareEnabled:False` は Hyper-V 稼働時の正常表示で、BIOS の VT-x は ON。）

### SDK 入手方針

- 当初は「BSP を repo sync からゼロ生成」を想定したが、**ベンダ/ビルドサーバから toolchain `.sh` を入手する**方針に変更（理由：実機 image とのバージョン整合＝ABI 一致を担保するため）。
- ベンダ依頼内容：「実機 image と同一 BSP/config で生成した aarch64(cortexa53) / i.MX8MP 向け、**Qt6 を含む** SDK（`bitbake <image> -c populate_sdk` 由来 or `meta-toolchain-qt6`）」。
- SDK 入手後：`.sh` を WSL で実行（`-y -d <dir>` で非対話 install）→ `source environment-setup-aarch64-poky-linux` →
  `cmake -S . -B build-yocto -DCMAKE_TOOLCHAIN_FILE="$OECORE_NATIVE_SYSROOT/usr/share/cmake/OEToolchainConfig.cmake" -DHMI_ENABLE_E2E=OFF -DBUILD_TESTING=OFF` →
  `cmake --build build-yocto --target hmi_runtime`（`-B build-yocto` でビルドツリーを明示生成してから build する。`-S . -B` を省くとリポジトリ直下にキャッシュが作られ後続 build が失敗する）。詳細は [phase3b-runtime-plan.md](phase3b-runtime-plan.md)「Yocto SDK 連携」。

---

## 実機 i.MX8MP EVK

- **ボード**：NXP **i.MX8MPlus EVK**（`/proc/device-tree/model` = "NXP i.MX8MPlus EVK board"）。
- **シリアルコンソール**：**COM5 / 115200 8N1**（FTDI クアッド UART デバッグブリッジ経由）。root はパスワード無し。
- **現行 image（2026-05-30 調査）**：`fsl-imx-xwayland` **5.4-zeus**（NXP `L5.4.24_2.1.0`、kernel 5.4.24、2020 年ビルド、Yocto 3.0）。
  aarch64 / glibc **2.30** / libstdc++ **6.0.27**（gcc9 世代）。**Qt6 は未インストール**（`libQt6Core` も `qmake6` も無し）。
- **含意**：zeus は `meta-qt6` 登場前の世代で、この image と一致する Qt6 SDK は原理的に作れず、ボードに Qt6 ランタイムも無い。
  本リポジトリは Qt 6.8（gcc11+/C++20）前提のため、現行 image のままでは `hmi_runtime` を起動できない。
  → **Task 23 の前段として、実機 image を Qt6 対応の新 BSP（scarthgap、`imx-image-full`）に更新・再フラッシュする**必要がある。
  詳細は [phase3b-runtime-plan.md](phase3b-runtime-plan.md) §「実機 image 調査結果と更新方針」。

---

## リポジトリ運用の注意

- **ローカルクローンが `origin/main` から大きく遅れていることがある**（実績：あるブランチが origin/main より 88 コミット遅れ・固有コミット 0）。
  「次のタスク」を判断する前に必ず `git fetch` → `git log --oneline origin/main` で実態を確認する。
  作業ツリーの README / CLAUDE.md が古いと「次タスク」を誤認する。
- 変更は **`task/<N>-<短い名>`（フェーズタスク）/ `docs/<短い名>`（ドキュメント・設定）** ブランチ + PR で取り込む（main 直 push 禁止）。
  レビューは ChatGPT Codex（GitHub App）。詳細は CLAUDE.md「Codex 連携 / PR ワークフロー」。
