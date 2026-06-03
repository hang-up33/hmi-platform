# 開発環境メモ（クロスマシン共有）

本リポジトリは **macOS と Windows 母艦（+ WSL2）** の複数マシンで開発する。
環境固有の知識（ホスト構成・ディスク事情・WSL/Yocto ビルド環境・実機 i.MX8MP の状態など）を
ここに **git 管理で集約** し、どのマシンからでも参照できるようにする。

> **なぜここ（`.claude/rules/`）に置くか**：Claude Code の自動メモリ（`~/.claude/projects/<project>/memory/`）は
> **マシンローカル**で、Windows ↔ Mac を跨いで共有されない。一方 `.claude/rules/*.md` は **git 管理されチームと共有**され、
> `paths` frontmatter を付けなければ **毎セッション起動時に自動読込**される（`.claude/CLAUDE.md` と同じ優先度）。
> よって「マシン横断で必要な環境知識」は本ファイルを唯一の真実とする（[Claude Code メモリ仕様](https://code.claude.com/docs/ja/memory) 準拠）。

## 運用ルール

- **環境固有の事実が変わったらこの文書を更新する**（新マシン追加、ディスク構成変更、WSL/SDK 状態、実機 image 更新など）。
- 役割分担：
  - **この文書** = 環境・マシン・実機の「現状スナップショット」。
  - [phase3b-runtime-plan.md](../../Docs/phase3b-runtime-plan.md) ほか `Docs/phase*-plan.md` = フェーズ/タスクの設計判断と完了基準。
  - [development-history.md](../../Docs/development-history.md) = タスクごとの時系列まとめ（目的 / PR / 成果物 / 学び）。
  - [CLAUDE.md](../../CLAUDE.md) = 作業指針（ビルド手順・ルール・罠）。
- 重複が出たら、**手順・設計はプラン文書、環境の現状はこの文書**に寄せ、互いをリンクで結ぶ（同じ事実を二重メンテしない）。

---

## 開発ホスト一覧

| ホスト | OS | 役割 | ビルド出力 | Qt |
|---|---|---|---|---|
| **Windows 母艦** | Windows 11 | Editor / Simulator / Runtime のビルド・GUI 確認。**WSL2 内で Yocto SDK クロスビルド**（Task 23+） | `build-mingw/`（ビルドツリー直下に `hmi_*.exe`） | Qt 6.11.0 MinGW 64-bit kit + 付属 MinGW 13.1 + Ninja（MSVC kit 未使用） |
| **macOS** | macOS 14+（Darwin 25+） | Editor / Simulator のビルド・GUI 確認、動作証跡スクショ撮影 | `build/`（`.app` バンドル） | Homebrew Qt（`/opt/homebrew/opt/qt`、6.8+） |

- Editor / Simulator は両 OS で GUI 起動確認済み。Runtime（PC sanity 版）も Task 22 で両 OS ビルド確認済み。
- ビルド手順の詳細は [CLAUDE.md](../../CLAUDE.md)「ビルドと実行」と [qt6-build スキル](../skills/qt6-build/SKILL.md)。

### Windows 母艦の詳細

- 入口スクリプト：`scripts/windows/build.ps1`（configure+build）、`scripts/windows/setup-env.ps1`（dot-source で PATH 設定）。
- 主要パス：Qt = `C:\Qt\6.11.0\mingw_64`、MinGW = `C:\Qt\Tools\mingw1310_64`、generator = Ninja 固定。
- 罠（詳細は [qt6-build スキル](../skills/qt6-build/SKILL.md) の「既知の罠」）：
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

### SDK 生成（2026-06-01：自前ビルドで完了）

新 BSP（scarthgap, `imx-6.6.52-2.2.2`）から **自前ビルド** で image と SDK を生成し、実機更新まで完了した
（手順の正本は [scripts/yocto/README.md](../../scripts/yocto/README.md)、設計判断は [phase3b-runtime-plan.md](../../Docs/phase3b-runtime-plan.md)）。

- **image**：`bitbake imx-image-full` → microSD に焼いて実機更新（Qt6 6.8.1 入り）。
- **SDK**：当初 `imx-image-full -c populate_sdk`（フル SDK）を試したが、**`onnxruntime-dbg`（692MB の ML デバッグ deb）の dpkg 展開で失敗**。Qt6 のクロスビルドに ML/opencv は不要なので **`bitbake meta-toolchain-qt6`（Qt6 だけの軽量 SDK, ~1.8GB `.sh`）に切替** → これで成功。
- **install**：`.sh -y -d ~/qt6-sdk`。env スクリプト名は NXP tune の都合で **`environment-setup-armv8a-poky-linux`**（`aarch64` ではない点に注意）。
- **クロスビルド**：`./scripts/yocto/cross-build.sh` で実行（env source → toolchain file 明示 → `-DHMI_ENABLE_E2E=OFF -DBUILD_TESTING=OFF` → `--target hmi_runtime`）。`~/build-yocto/Runtime/hmi_runtime` が aarch64 ELF で生成され、実機描画も確認済み（Task 24）。

#### Yocto ビルドで踏んだ罠（再ビルド時の備忘）

- **crates.io の 403**：bitbake の wget 既定 UA を crates.io（CloudFront）が 403 で弾く。`conf/local.conf` に
  `FETCHCMD_wget = "/usr/bin/env wget -t 2 -T 30 --passive-ftp --user-agent=yocto-bitbake"` を足すと解消（premirror に無く crates.io 直叩きになる crate 全般に効く）。
- **GitHub 並列 fetch のスロットル**：`gitsm://github.com/...` の clone が exit 128 で稀に落ちる（並列 fetch 集中時）。リポジトリは健在なので **retry で通る**。
- **ディスク**：`imx-image-full` は tmp/work が巨大化し E（233GB の外付け SSD）を使い切る。**`INHERIT += "rm_work"`** で peak を ~30GB に抑える。それでも膨らんだ vhdx は **`diskpart compact vdisk`（管理者 PowerShell、`wsl --shutdown` 後 attach readonly → compact）** で物理回収（`wsl --manage --set-sparse` や `fstrim` だけでは縮まなかった。compact は 228GB に対し一晩かかったが ~52GB 回収）。
- **WSL distro relocate（C→E）**：`wsl --export` → `--unregister` → `--import ... --version 2`（[ディスク事情] 節のコマンド）。

---

## 実機 i.MX8MP EVK

- **ボード**：NXP **i.MX8MPlus LPDDR4 EVK**（`/proc/device-tree/compatible` = `fsl,imx8mp-evk` ＝LPDDR4。シリアルで判定）。
- **シリアルコンソール**：**COM5 / 115200 8N1**（FTDI クアッド UART デバッグブリッジ経由）。root はパスワード無し。
- **現行 image（2026-06-01 更新済み）**：`fsl-imx-xwayland` **6.6-scarthgap**（NXP `imx-6.6.52-2.2.2`）。
  **Qt6 6.8.1 入り**（`/usr/lib/libQt6Core.so.6.8.1` 確認済み）。weston / Wayland。これで `hmi_runtime` が実機起動・描画可能（Task 24 達成）。
  - 旧 image は zeus 5.4（2020・Qt6 無し）で `hmi_runtime` 起動不可だったため、新 BSP（scarthgap）で `imx-image-full` をビルドし microSD に焼いて更新した。
- **ブートスイッチ（SW4）**：**`0011` = microSD ブート / `0010` = eMMC ブート**。SD の新 image を起動するには SW4 を 0011 に。
- **実機運用メモ（Task 24 で確立）**：
  - **転送**：実機 sshd は **socket-activated**（`sshd.socket` enabled、`sshd.service` は無い → `systemctl start sshd` は失敗するが port 22 は listen 済み）。新しい OpenSSH の scp は SFTP 既定で実機に sftp-server が無く失敗するため **`scp -O`** 必須。事前に実機で `passwd`（ssh は空パスワード拒否）。
  - **ネットワーク**：LAN 直結だと DHCP 無しで **link-local（169.254.x.x）** になる。**WSL2 は NAT 越しで link-local に届きにくいので Windows 母艦から `scp`** する（Windows の ethernet も 169.254.x.x が付き ping 可）。
  - **起動**：weston は **root（uid 0）** で動作、Wayland socket は `/run/user/0/wayland-1`。`export XDG_RUNTIME_DIR=/run/user/0; export WAYLAND_DISPLAY=wayland-1; export QT_QPA_PLATFORM=wayland` してから `hmi_runtime --open <json>`。
- **実機キャプチャ・接続メモ（Task 30 で確立）**：
  - **mDNS で IP が引ける**：実機は avahi 稼働。`imx8mp-lpddr4-evk.local` が link-local IP（実績 `169.254.29.17`）に解決される。
  - **link-local の宛先 IF 選択がぶれる**：母艦に複数の link-local IF（VirtualBox `192.168.56.x` / WSL `172.18.x` 等）があると `169.254.x.x` への ping/ssh が別 IF 経由で **host unreachable** になる。実機直結アダプタ（実績「イーサネット 2」`169.254.32.193`）を**送信元に固定**する：ping は `-S <src>`、ssh/scp は **`-b <src>`**。
  - **`pkill -f hmi_runtime` 厳禁**：ssh のリモートシェルのコマンドライン自身に "hmi_runtime" が含まれ、`pkill -f` が**自分の親シェルを kill** して ssh が exit 255 で即死する。停止は **`pkill -x hmi_runtime`**。
  - **HDMI 未接続だと weston に出力が無い**（`DRM: head 'HDMI-A-1' ... is disconnected`）→ Qt は "fake screen" 描画で `weston-screenshooter` も撮れない。物理モニタ無しで撮るには **`QT_QPA_PLATFORM='vnc:size=1280x720'` で起動 → 母艦から `scripts/yocto/vnc-capture.py <ip> 5900 out.png <src>`**（Qt 内蔵 VNC, 依存なし）。実機 image に**日本語フォント無し**でラベルは □ になる（描画自体は正常）。
- 詳細手順は [scripts/yocto/README.md](../../scripts/yocto/README.md)、設計判断は [phase3b-runtime-plan.md](../../Docs/phase3b-runtime-plan.md)。

---

## リポジトリ運用の注意

- **ローカルクローンが `origin/main` から大きく遅れていることがある**（実績：あるブランチが origin/main より 88 コミット遅れ・固有コミット 0）。
  「次のタスク」を判断する前に必ず `git fetch` → `git log --oneline origin/main` で実態を確認する。
  作業ツリーの README / CLAUDE.md が古いと「次タスク」を誤認する。
- 変更は **`task/<N>-<短い名>`（フェーズタスク）/ `docs/<短い名>`（ドキュメント・設定）** ブランチ + PR で取り込む（main 直 push 禁止）。
  レビューは ChatGPT Codex（GitHub App）。詳細は CLAUDE.md「Codex 連携 / PR ワークフロー」。
