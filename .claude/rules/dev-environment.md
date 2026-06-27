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
- **Qt OPC-UA（qtopcua）を Homebrew Qt にマージ済み（2026-06-22 / Phase 9 OP-2 着手前ゲート解消）**：Homebrew の `qt` 6.11.1 ボトルは **qtopcua を含まない**（`find /opt/homebrew -iname '*opcua*'` が空）。aqtinstall も qtopcua 非同梱（Web/CI 不可）なので、**qtopcua モジュールを Qt ソースから自前ビルドして Homebrew Qt にマージ**して OP-2 以降をローカルで回せるようにした（plan §依存 option ②）。手順（実証済み）：
  - `brew install open62541 ninja`（open62541 はバックエンド・ninja は生成器）。
  - `git clone --depth 1 --branch v6.11.1 https://code.qt.io/qt/qtopcua.git`。
  - `qt-cmake <src> -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/opt/homebrew/opt/qt -DQT_NO_XCODE_MIN_VERSION_CHECK=ON -DQT_NO_APPLE_SDK_MIN_VERSION_CHECK=ON` → `cmake --build . && cmake --install .`。
  - **罠：full Xcode 不在（CLT のみ）だと Qt モジュールビルドが「Can't determine Xcode version」で FATAL 停止**する。`-DQT_NO_XCODE_MIN_VERSION_CHECK=ON`（+ `-DQT_NO_APPLE_SDK_MIN_VERSION_CHECK=ON`）で版数チェックブロックごとスキップすれば CLT で通る（CLT で実ビルドは問題なし）。
  - 検証：`lib/cmake/Qt6OpcUa/` と `lib/QtOpcUa.framework` が入り、`share/qt/plugins/opcua/libopen62541_backend.dylib` が同梱され、最小プログラムで `QOpcUaProvider::availableBackends()` が `("open62541")` を返せば OK。`find_package(Qt6 ... OpcUa)` がこれで通る。
  - これは **Homebrew Qt の現物（`/opt/homebrew/opt/qt`）を書き換える**ので、`brew reinstall qt` すると消える（その時は再ビルドが要る）。**Windows 母艦 / Yocto 実機 rootfs は別途**（plan §依存 option ①③・SerialBus と同様にそれぞれ未導入＝OP-6 等で対応）。
  - asyncua E2E は **Homebrew python3.14 の pyexpat が壊れていて asyncua を import/install できない**（`Symbol not found: _XML_SetAllocTrackerActivationThreshold`）。**self-check スクリプト `bash scripts/opcua/run-local-check.sh` が、expat の健全な Python を自動選択して venv（既定 `build/opcua-venv`）に asyncua を入れ、OPC-UA 込みの hmi_simulator を探して `tests/e2e/test_opcua_read.py`（asyncua ソフトサーバ → 購読 → Label 追従）を回す**＝Claude/開発者/将来 CI が 1 コマンドで再現テストできる（exit 0=OK / 77=SKIP / 1=FAIL。OP-2 で緑を確認済み）。ctest 既定の python3.14 では asyncua import 失敗で `e2e_opcua_read` が SKIP（exit 77）になる＝緑は妨げないので、購読 round-trip を実際に見るには本スクリプトを使う。手動で値を動かして見たいときは `scripts/opcua/test_server.py`（ライブ値サーバ）+ `Docs/samples/opcua-demo.json`。
- **Qt OPC-UA（qtopcua）を Windows 母艦（Qt 6.11.0 MinGW）に導入する手順**：`scripts/windows/build-opcua.ps1` を実行する（plan §依存 option ①）。スクリプトは **2 段階**で動く：
  - **Stage A**：Qt サーバから `qt.qt6.6110.addons.qtopcua.win64_mingw` の 7z を取得して `C:\Qt\6.11.0\mingw_64\` にマージ（SerialBus と同じ方法）。open62541 backend plugin（`plugins\opcua\open62541_backend.dll`）が含まれれば完了。
  - **Stage B（自動フォールバック）**：**qtopcua を MinGW でソースビルドして Qt にマージする**。qtopcua のタグは `$QtDir` パスから自動導出（例: `C:\Qt\6.11.0\mingw_64` → `v6.11.0`）。open62541 は qtopcua に同梱されているため別途ビルド不要（`-DCMAKE_PREFIX_PATH=$QtDir` のみ指定し、同梱版の open62541 が backend plugin として組み込まれる）。初回は 10〜30 分かかる。
  - 検証：`plugins\opcua\*open62541*` が存在し、`lib\cmake\Qt6OpcUa\` と `include\QtOpcUa\` が入ること（スクリプトが最後に自動確認）。
  - 完了後：`.\scripts\windows\build.ps1 -Reconfigure` で hmi_simulator が OpcUa 込みでビルドできる。
  - **罠・ポイント**：`qt-cmake.bat` は `.bat` なので PowerShell から直接呼ぶと引数渡しが不安定。スクリプト内では `cmake -DCMAKE_PREFIX_PATH=$QtDir` を直接呼ぶ（`qt-cmake.bat` をラップしない）ことで回避済み。`windeployqt`（deploy.ps1）を使う際は `Qt6OpcUa.dll` と `open62541.dll`・`plugins\opcua\` が hmi_simulator.exe の隣に配置されることを確認。
  - **導入完了・動作確認済み（2026-06-27）**：Stage A で `open62541_backend.dll` を取得し hmi_simulator が `Qt6OpcUa` リンク済みで再ビルド成功。`pip install asyncua` → `scripts/opcua/test_server.py` 起動 → `Docs/samples/opcua-demo.json`（NumericField 付き）で読込追従（OP-3）・Setpoint 書込（OP-5）を確認。

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
- **OPC-UA 実機展開（OP-6 で確立・2026-06-27）**：
  - **SDK に qtopcua が既に包含**：`meta-toolchain-qt6`（`~/qt6-sdk/`）は `Qt6OpcUa` の cmake ファイル・ライブラリ・open62541 backend plugin（`libopen62541_backend.so`）を包含しており、**SDK 再ビルドなしでクロスビルド可**（`find ~/qt6-sdk/sysroots -name '*OpcUa*'` で確認）。ビルドは `HMI_BUILD_DIR=/home/ubuntu/build-yocto-op6 HMI_SRC_DIR=/mnt/c/repo/hmi-platform bash scripts/yocto/cross-build.sh`（build dir を専用名にすると既存 yocto build dir の CMake キャッシュ衝突を回避）。
  - **実機 image に `libQt6SerialBus.so.6` が存在しない**：`hmi_runtime`（`ModbusController` も含む）起動時に `error while loading shared libraries: libQt6SerialBus.so.6` で即死。scarthgap の `imx-image-full` に `qtserialbus`/`qtserialport` が未同梱のため。Yocto deb から取り出して実機に転送・`dpkg -i` で対処。**インストール順**：`libsocketcan2` → `libqt6serialport6` → `libqt6serialbus6`（依存解決順。SerialBus は SerialPort と socketcan に依存）。
  - **WSL から scp がハングする**：WSL2 内で `scp root@<board-ip>:/tmp/...` を呼ぶと known_hosts 未登録によるホストキー確認の対話待ちでハング。回避：**Windows 母艦から直接 scp**。WSL 内ファイルは `\\wsl$\Ubuntu-22.04\home\ubuntu\...` の UNC パスで Windows から参照できるので `scp -O -o StrictHostKeyChecking=no "\\wsl$\Ubuntu-22.04\...\file.deb" root@<board-ip>:/tmp/` で転送する（PowerShell 5.1 の `&&` 非対応に注意。`scp ...; if ($?) {...}` で連結）。
  - **実機ネットワーク（link-local のみの場合）**：mDNS が失敗したらシリアルで `ip addr show eth0` で link-local IP を確認し `ip addr add 192.168.1.211/24 dev eth0` で静的 IP 付与。Windows 母艦の送信元 IF アドレス（例 `192.168.1.210`）と同サブネットにする。
  - **test_server.py の全 IF バインド**：引数なしだと `127.0.0.1:4840` のみリッスンで実機から到達不可。`python test_server.py --host 192.168.1.210` で起動すると `0.0.0.0:4840` でリッスンして実機から接続可能になる。
  - **実機 VNC キャプチャ（OPC-UA 証跡）**：`QT_QPA_PLATFORM='vnc:size=1280x720'` で起動し `python scripts/yocto/vnc-capture.py 192.168.1.211 5900 out.png 192.168.1.210` でキャプチャ（第 4 引数は送信元 IP）。証跡：`Docs/screenshots/op6-runtime.png`（Counter/Temperature/Running/Setpoint の OPC-UA ライブ値が実機で表示）。
- 詳細手順は [scripts/yocto/README.md](../../scripts/yocto/README.md)、設計判断は [phase3b-runtime-plan.md](../../Docs/phase3b-runtime-plan.md)。

---

## リポジトリ運用の注意

- **ローカルクローンが `origin/main` から大きく遅れていることがある**（実績：あるブランチが origin/main より 88 コミット遅れ・固有コミット 0）。
  「次のタスク」を判断する前に必ず `git fetch` → `git log --oneline origin/main` で実態を確認する。
  作業ツリーの README / CLAUDE.md が古いと「次タスク」を誤認する。
- 変更は **`task/<N>-<短い名>`（フェーズタスク）/ `docs/<短い名>`（ドキュメント・設定）** ブランチ + PR で取り込む（main 直 push 禁止）。
  レビューは ChatGPT Codex（GitHub App）。詳細は CLAUDE.md「Codex 連携 / PR ワークフロー」。
- **【暫定】GitHub Actions CI が 2026-06-07 12:26 UTC 以降、全 run 即時失敗中**（main push 含む全ブランチ。ジョブが runner 未割当のまま約 4 秒で failure・ステップ実行ゼロ・ログ無し＝404。2026-06-10 切り分け）。PR の変更内容とは無関係のインフラ起因で、**Actions の無料枠 / 支出上限切れの疑い**（`main` push 毎に macOS 10x / Windows 2x ジョブが走る設定のため消費が速い）。オーナーの Billing 設定でのみ確認・解消可能。この間の「テスト緑」は Web セッション内 `ctest` の結果で CI 緑ではない。**赤 CI を自分の PR のせいと誤診しないこと**。
- **【CI コスト削減（2026-06-10）】上記の課金消費を止めるため、`.github/workflows/ci.yml` の自動トリガ（`pull_request` / `push`）をコメントアウトし、`workflow_dispatch`（手動実行）のみに切替えた**。
- **【自動 CI 復活（2026-06-18）】上記コスト問題を解消する形で、Proxmox 上の self-hosted runner に linux ジョブを載せ替えて自動 CI を復活した**（計画・進捗の正本は [Docs/ci-self-hosted-plan.md](../../Docs/ci-self-hosted-plan.md)）。
  - **runner 箱**：Proxmox `pve`（VE 9.1.6 / 192.168.40.99）の **LXC CT 101 `gh-runner`**（Ubuntu 24.04 / 4 vCPU・4GB・swap2GB / rootfs 32GB(local-lvm) / net vmbr0 DHCP=192.168.40.209 / unprivileged / nesting=1 / onboot=1）。CI 依存（[ci.yml](../../.github/workflows/ci.yml) の Linux deps + cmake/build-essential/curl/git/python3/sudo）導入済。
  - **runner 本体**：actions/runner v2.335.1 を `runner` ユーザーで登録（labels `self-hosted` `Linux` `X64` `qt` / name `gh-runner-lxc`）→ `svc.sh` で systemd 常駐（`actions.runner.hang-up33-hmi-platform.gh-runner-lxc.service`、enabled・自動起動）。`runner` の NOPASSWD sudo は `apt-get` のみに限定。
  - **ci.yml 構成**：**linux ジョブ＝`runs-on: [self-hosted, linux]`**（毎 PR / main push 自動・課金 0・主ゲート）。**desktop（mac 10x / win 2x）は `workflow_dispatch` か PR `ci-desktop` ラベル時のみ**（main push では走らない）。Qt は `install-qt-action` の `modules: "qtserialbus qtserialport"`（SerialBus 必須）。
  - **runner 操作（母艦から）**：`ssh root@192.168.40.99` → `pct exec 101 -- bash -c "cd /home/runner/actions-runner && ./svc.sh status|start|stop"`。GitHub 側状態は `gh api repos/hang-up33/hmi-platform/actions/runners`。
  - **セキュリティ前提**：**private リポ限定**。public 化 / fork PR 許可時は linux の `runs-on` を fork→GitHub-hosted へ逃がす条件式に差し替える（[Docs/ci-self-hosted-plan.md](../../Docs/ci-self-hosted-plan.md)「セキュリティ注意」）。
