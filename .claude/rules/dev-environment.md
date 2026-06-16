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
  - **PowerShell から WSL を呼ぶとき `$HOME` 等の `$` 変数は PowerShell 側で先に展開される**（2026-06-09 実証）。`wsl ... bash -lc "... HMI_BUILD_DIR=$HOME/... "` と書くと PS が `$HOME`(=`C:\Users\k`) を埋め、WSL では `C:Usersk/...`（`:` と `\` が落ちた壊れたパス）になり CMake が `try_compile`/source-dir で落ちる。回避：**WSL の絶対パスを直書き**（`/home/ubuntu/...`）するか、`bash -lc` の引数を**単一引用符**で囲って PS の変数展開を止める。
  - **GUI サブシステムの exe（hmi_editor.exe 等）は PowerShell の `&` で起動しても待たれない**（`$LASTEXITCODE` も取れない）。`--screenshot` のような「起動→処理→終了」を待つには `Start-Process -Wait -PassThru` を使う。
  - **QtSerialBus / QtSerialPort はローカル kit に未同梱だった（2026-06-16 / Phase 7 MB-3 で発覚・解消済み）**：`C:\Qt\6.11.0\mingw_64` には SerialBus / SerialPort が入っておらず、MB-2 の `ModbusController`（`Qt6::SerialBus`）が `find_package` 段階で `Could NOT find Qt6SerialBus` → ビルド不可だった（MB-2 は Web/CI の aqtinstall 同梱前提で書かれていた）。**Modbus を扱うローカルビルドにはこの 2 モジュールが必須**。導入手順（実証済み）：
    - **MaintenanceTool は不可**：`qt.qt6.6110.addons.qtserialbus` を `Component(s) not found` で選択できない（6.11.0 が「歴史的バージョン」扱いになり既定リポジトリから外れているため。GUI updater 実行を要求される）。
    - **aqtinstall（v3.3.0）も `install-qt` 不可**：6.11.0 の desktop リポジトリは arch 別フォルダ（`qt6_6110/qt6_6110_mingw/`）に分割済みだが aqt 3.3.0 は旧レイアウト（`qt6_6110/qt6_6110/Updates.xml`）を見に行き 404 →「Failed to locate XML data」。ハッシュ検証を切る `INSECURE_NOT_FOR_PRODUCTION_ignore_hash` はセキュリティ上使わない（自動拒否される）。
    - **正攻法＝7z を直接 DL→検証→マージ**：`.../qt6_6110/qt6_6110_mingw/qt.qt6.6110.addons.qtserialbus.win64_mingw/<version>qtserialbus-...-X86_64.7z`（+ `qtserialport` も同様。SerialBus は SerialPort に依存）を `curl` で取得し、**同梱の `.sha256` で照合**してから `py7zr`（aqtinstall の依存で入る）で展開、`bin/ include/ lib/ plugins/ ...` を `C:\Qt\6.11.0\mingw_64\` に `Copy-Item -Recurse -Force` でマージ。`lib\cmake\Qt6SerialBus\Qt6SerialBusConfig.cmake` と `bin\Qt6SerialBus.dll` が入れば OK。`QModbusTcpClient` は SerialBus 本体にあり modbus plugin は不要。
    - **Editor 非リンクは維持される**：`objdump -p build-mingw/hmi_editor.exe | grep -i serialbus` が空、`hmi_simulator.exe` は `Qt6SerialBus.dll` を import。Explorer 起動には `deploy.ps1`（windeployqt）で `Qt6SerialBus.dll` / `Qt6SerialPort.dll` 同梱が要る（PATH 経由の直起動なら不要）。

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
- **実機で「最新の実装」を描画する前に必ず runtime を再クロスビルドする**（2026-06-09 実証＝最重要）。実機 `/tmp/hmi_runtime` は**過去にデプロイした時点のバイナリで固定**されるため、後続タスクで足した機能（配置 hAlign/vAlign・太字 fontBold・状態 checked・アクション/バインディング等）は**古いバイナリでは黙って無視され描画されない**。色・サイズ・枠・角丸など古い機能だけは効くので**一見動いて見え気付きにくい**（実際 6/3 ビルドで「配置だけ効かない」状態を踏んだ）。現ソースからのビルドは Windows 内クローン不要で `/mnt/c` を直接使える：
  ```bash
  # WSL2 内（Windows のソースをそのまま使う。build dir は WSL ext4 に置く）
  HMI_SRC_DIR=/mnt/c/repo/hmi-platform HMI_BUILD_DIR=/home/ubuntu/build-yocto-latest \
    bash scripts/yocto/cross-build.sh
  ```
  既存 `~/build-yocto` は別ソースパスで configure 済みだと CMake キャッシュが衝突するので、ソース dir を変えるときは **build dir も別名**にする（上記は `build-yocto-latest`）。生成後は WSL→Windows→`scp -O` で実機 `/tmp/hmi_runtime` を**上書き前に `pkill -x hmi_runtime` で停止**する（実行中だと `Text file busy` で scp 失敗）。

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
  - **mDNS で IP が引ける**：実機は avahi 稼働。`imx8mp-lpddr4-evk.local` が link-local IP に解決される（実績 `169.254.29.17` / `169.254.48.18` / `169.254.124.33` など **DHCP 無しの link-local は毎回変わる**ので、記録値を使い回さず**都度 mDNS で解決**する。Windows は `Resolve-DnsName imx8mp-lpddr4-evk.local`）。
    - **mDNS が IPv6（AAAA）だけ返すことがある**（2026-06-10 実証）：素の `Resolve-DnsName` が `fe80::...`（IPv6 link-local）しか返さず IPv4 が出ないことがある。IPv4（A）を引くには **`-Type A` を明示**（`Resolve-DnsName imx8mp-lpddr4-evk.local -Type A` → 例 `169.254.124.33`）。IPv6 link-local で直接叩くなら zone id 付き（`ping fe80::...%<ifIndex>`、ifIndex は `Get-NetAdapter`／直結 IF は実績「イーサネット 2」）。ボード MAC は IPv6 から導出可（`fe80::204:9fff:fe06:c9dc` → `00:04:9f:06:c9:dc`、NXP OUI `00:04:9f`）。
    - **SSH 鍵認証が非対話で通る**（`-o BatchMode=yes` で確認可）。PowerShell 越しに ssh/scp を呼ぶと「known_hosts に追加」警告が stderr に出て `$LASTEXITCODE`/`$?` が偽陰性（exit 1 表示）になるが、**標準出力の内容で成否を判断**してよい（`2>&1` 由来の NativeCommandError は無視）。
  - **アクション（クリック→状態変化）の実機証跡は `scripts/yocto/vnc-click-capture.py`**（Task 43 で確立）。`vnc-capture.py` は 1 枚読むだけなので、変数/アクション/バインディングの「動き」を撮るには VNC の **PointerEvent** でクリックを送って before/after を撮る。クリック座標は画面ピクセル（1024x768 ウィンドウに 800x600 キャンバスを centerIn ＝キャンバス `(cx,cy)` → 画面 `(112+cx, 84+cy)`）。**after は non-incremental 全面で撮る**（QVnc は変化なしだと incremental 応答を保留し recv が timeout する）。手順は [scripts/yocto/README.md](../../scripts/yocto/README.md)「アクション（クリック→状態変化）を実機で撮る」。
  - **link-local の宛先 IF 選択がぶれる**：母艦に複数の link-local IF（VirtualBox `192.168.56.x` / WSL `172.18.x` 等）があると `169.254.x.x` への ping/ssh が別 IF 経由で **host unreachable** になる。実機直結アダプタ（実績「イーサネット 2」`169.254.32.193`）を**送信元に固定**する：ping は `-S <src>`、**ssh は `-b <src>`、scp は `-o BindAddress=<src>`**（**Windows OpenSSH の `scp` に `-b` は無い** — 渡すと `unknown option -- b` で落ちる。`scp` のバインドは ssh_config 経由の `-o BindAddress=` で行う。ssh 本体は従来どおり `-b`。2026-06-09 実証）。
  - **`pkill -f hmi_runtime` 厳禁**：ssh のリモートシェルのコマンドライン自身に "hmi_runtime" が含まれ、`pkill -f` が**自分の親シェルを kill** して ssh が exit 255 で即死する。停止は **`pkill -x hmi_runtime`**。
  - **HDMI 未接続だと weston に出力が無い**（`DRM: head 'HDMI-A-1' ... is disconnected`）→ Qt は "fake screen" 描画で `weston-screenshooter` も撮れない。物理モニタ無しで撮るには **`QT_QPA_PLATFORM='vnc:size=1024x768'` で起動 → 母艦から `scripts/yocto/vnc-capture.py <ip> 5900 out.png <src>`**（Qt 内蔵 VNC, 依存なし。**size は runtime ウィンドウ実寸＝1024×768 に合わせる**と余白の黒帯・見切れが出ない。canvas 描画域は 800×600）。実機 image に**日本語フォント無し**で和文ラベルは □ になる（**ASCII は正常描画**。動作証跡 JSON はラベルを英数字にすると豆腐を避けられる）。
  - **HDMI 接続済みでも `weston-screenshooter` が `unauthorized` で撮れないことがある**（`Output capture error: unauthorized` — この weston ビルドは screenshooter プロトコルを許可していない。2026-06-09、HDMI=connected でも発生を実証）。**HDMI の有無に関わらず動作証跡は上記 VNC 経路が確実**。VNC は `QT_QPA_PLATFORM=vnc` で**別インスタンス**を立てるだけ（weston には繋がない）なので、**HDMI モニタ表示用の weston インスタンスを止めずに並行起動**して撮れる（撮影後は VNC 側だけ pid 指定で kill すればモニタ表示は維持される）。
- 詳細手順は [scripts/yocto/README.md](../../scripts/yocto/README.md)、設計判断は [phase3b-runtime-plan.md](../../Docs/phase3b-runtime-plan.md)。

---

## リポジトリ運用の注意

- **ローカルクローンが `origin/main` から大きく遅れていることがある**（実績：あるブランチが origin/main より 88 コミット遅れ・固有コミット 0）。
  「次のタスク」を判断する前に必ず `git fetch` → `git log --oneline origin/main` で実態を確認する。
  作業ツリーの README / CLAUDE.md が古いと「次タスク」を誤認する。
- 変更は **`task/<N>-<短い名>`（フェーズタスク）/ `docs/<短い名>`（ドキュメント・設定）** ブランチ + PR で取り込む（main 直 push 禁止）。
  レビューは ChatGPT Codex（GitHub App）。詳細は CLAUDE.md「Codex 連携 / PR ワークフロー」。
- **【暫定】GitHub Actions CI が 2026-06-07 12:26 UTC 以降、全 run 即時失敗中**（main push 含む全ブランチ。ジョブが runner 未割当のまま約 4 秒で failure・ステップ実行ゼロ・ログ無し＝404。2026-06-10 切り分け）。PR の変更内容とは無関係のインフラ起因で、**Actions の無料枠 / 支出上限切れの疑い**（`main` push 毎に macOS 10x / Windows 2x ジョブが走る設定のため消費が速い）。オーナーの Billing 設定でのみ確認・解消可能。この間の「テスト緑」は Web セッション内 `ctest` の結果で CI 緑ではない。**赤 CI を自分の PR のせいと誤診しないこと**。
- **【CI コスト削減（2026-06-10）】上記の課金消費を止めるため、`.github/workflows/ci.yml` の自動トリガ（`pull_request` / `push`）をコメントアウトし、`workflow_dispatch`（手動実行）のみに切替えた**。以後 PR / main push では CI が一切走らない（課金ゼロ）。検証が要るときは GitHub の Actions タブ → CI → Run workflow で任意ブランチを手動実行する（手動実行時は Linux / macOS / Windows 全ジョブが走る）。**自動 CI を復活させるときは ci.yml のコメントアウトを解除**し、Billing（無料枠 / 支出上限）が回復していることを確認する。テスト緑の担保は当面 Web セッション内 `ctest`（unit + e2e）で行う。
