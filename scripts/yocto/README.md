# scripts/yocto — Yocto SDK クロスビルド（Phase 3-B / Task 23・24）

`hmi_runtime` を i.MX8MP（aarch64 / Yocto scarthgap）向けにクロスビルドし、実機で
起動するための補助スクリプトと手順。**WSL2 内で実行する想定**で、macOS / Windows の
ホストビルド（`build/` ・ `build-mingw/`）には影響しない。

計画と設計判断の正本は [Docs/archive/phase3b-runtime-plan.md](../../Docs/archive/phase3b-runtime-plan.md)、
開発環境の現状は [.claude/rules/dev-environment.md](../../.claude/rules/dev-environment.md)。

## 前提（SDK と実機 image）

実機の現行 image が Qt6 非対応（NXP zeus 5.4）だったため、新 BSP で image と SDK を
**同一 BSP/config から**生成する（ABI / Qt バージョンを揃える）。WSL2 内で:

```sh
# 1) BSP 取得（Google repo tool）
mkdir -p ~/imx-scarthgap && cd ~/imx-scarthgap
repo init -u https://github.com/nxp-imx/imx-manifest -b imx-linux-scarthgap -m imx-6.6.52-2.2.2.xml
repo sync -c -j8

# 2) ビルド環境（EULA 同意・build dir 作成）
DISTRO=fsl-imx-xwayland MACHINE=imx8mp-lpddr4-evk EULA=1 source ./imx-setup-release.sh -b build-xwayland

# 3) 実機 image（Qt6 入り）→ SD/eMMC に焼く
bitbake imx-image-full

# 4) Qt6 クロス SDK（軽量。imx-image-full -c populate_sdk は ML 等で巨大かつ詰まりやすい）
bitbake meta-toolchain-qt6

# 5) SDK install
tmp/deploy/sdk/fsl-imx-xwayland-glibc-x86_64-meta-toolchain-qt6-armv8a-imx8mp-lpddr4-evk-toolchain-6.6-scarthgap.sh -y -d ~/qt6-sdk
```

> **狭いディスクでの注意**：`imx-image-full` のフルビルドは tmp/work が巨大化する。
> `INHERIT += "rm_work"` を `conf/local.conf` に足すと peak を大幅に抑えられる。
> crates.io が wget の既定 UA を 403 で弾くため `FETCHCMD_wget = "/usr/bin/env wget -t 2 -T 30 --passive-ftp --user-agent=yocto-bitbake"` も足す。詳細は dev-environment.md。

## クロスビルド

```sh
./scripts/yocto/cross-build.sh
```

`~/qt6-sdk/environment-setup-*` を source → toolchain file を明示渡し →
`-DHMI_ENABLE_E2E=OFF -DBUILD_TESTING=OFF` で configure → `--target hmi_runtime` のみビルド →
`file` で **`ELF 64-bit LSB ... ARM aarch64`** を確認する。

環境変数で上書き可：`HMI_SDK_ENV` / `HMI_SRC_DIR` / `HMI_BUILD_DIR`。

成果物：`~/build-yocto/Runtime/hmi_runtime`（aarch64 ELF, ~5.5MB）。

## 実機へ配布して起動（Task 24）

実機（i.MX8MP EVK / scarthgap / weston）で確認できた手順。**boot は microSD（SW4=0011、0010=eMMC）**。

```sh
# 実機の IP を確認（LAN 直結だと 169.254.x.x の link-local になることがある）
ip a show eth0

# 転送: 実機 sshd は socket-activated。新しい OpenSSH の scp は -O（旧プロトコル）必須。
#   Windows 母艦からなら link-local でも届く（WSL は NAT 越しで届きにくい）。
scp -O ~/build-yocto/Runtime/hmi_runtime root@<board-ip>:/tmp/hmi_runtime    # 実機側で passwd 設定要

# 実機側で weston(Wayland) 上に起動（weston は root / uid 0 で動作）
export XDG_RUNTIME_DIR=/run/user/0
export WAYLAND_DISPLAY=wayland-1
export QT_QPA_PLATFORM=wayland
chmod +x /tmp/hmi_runtime
/tmp/hmi_runtime --open /tmp/project.json
```

`project.json` は `Shared/Schema` の形状（`project` / `screens[].widgets[]`）。最小例は
[README.md](../../README.md#共通データ仕様project-format) 参照。成功すると weston 上に
「HMI Simulator」ウィンドウが出て widget が描画される（動作証跡：
[Docs/screenshots/task-24-runtime-imx.jpg](../../Docs/screenshots/task-24-runtime-imx.jpg)）。

## ディスプレイ未接続でも描画を digital capture する（Task 30 で確立）

実機の **HDMI が未接続**だと weston に出力が無く（`DRM: head 'HDMI-A-1' ... is disconnected`）、
Qt は "fake screen" に描画して `weston-screenshooter` でも何も撮れない（**HDMI 接続済みでも `weston-screenshooter` が
`Output capture error: unauthorized` で撮れない weston ビルドがある**ため、HDMI の有無に
関わらず下記 VNC 経路が確実。VNC は weston とは別インスタンスなのでモニタ表示用 weston を
止めず並行起動できる）。物理モニタ無しで
実機 GPU/CPU の描画を撮るには **Qt 内蔵 VNC platform** を使う（image に `libqvnc.so` 同梱済み）：

```sh
# 実機側（ssh 越しに起動。weston ではなく vnc platform を使うので WAYLAND_DISPLAY 不要）
QT_QPA_PLATFORM='vnc:size=1280x720' nohup /tmp/hmi_runtime --open /tmp/x.json >/tmp/vnc.log 2>&1 </dev/null &
# → /tmp/vnc.log に "QVncServer created on port 5900" が出れば OK

# 母艦側（Windows）: 最小 RFB クライアントで 1 フレームを PNG 化（stdlib のみ・依存なし）
python scripts/yocto/vnc-capture.py <board-ip> 5900 out.png <source-ip>
```

### 実機キャプチャの罠（Task 30 で踏んだ）

- **`pkill -f hmi_runtime` は使わない**：ssh のリモートシェルの**コマンドライン自身に
  "hmi_runtime" が含まれる**ため、`pkill -f` が自分の親シェルを kill して ssh が exit 255 で
  即死する（出力も出ない）。プロセス停止は **`pkill -x hmi_runtime`**（実行ファイル名完全一致）。
- **link-local の宛先 IF 選択がぶれる**：母艦に複数の link-local IF（VirtualBox / WSL の仮想
  アダプタ等）があると `169.254.x.x` への ping/ssh が**別 IF 経由で host unreachable** になる。
  実機直結アダプタの IP を送信元に固定する：ping は `-S <src>`、**ssh は `-b <src>`、scp は
  `-o BindAddress=<src>`**（Windows OpenSSH の `scp` に `-b` は無い＝`unknown option -- b`）、
  `vnc-capture.py` は第 4 引数 `<src>`。実機 IP は mDNS（`imx8mp-lpddr4-evk.local`）で引ける
  （link-local は毎回変わるので都度解決する）。
- **scp は `-O`**（実機 sshd は socket-activated・sftp-server 無し）。鍵認証なら非対話で回せる
  （母艦で `ssh-keygen` → 公開鍵を実機 `/root/.ssh/authorized_keys` にシリアル経由で 1 行追記）。
- 実機 image に**日本語フォントが無い**ため、ツールバー等の日本語ラベルは □ になる（描画自体は正常）。
  動作証跡用の JSON はラベルを **ASCII** にすると豆腐を避けられる（例 `Docs/samples/task-43-runtime-action-demo.json`）。

## アクション（クリック→状態変化）を実機で撮る（Task 43 で確立）

`vnc-capture.py` は framebuffer を 1 枚読むだけ（読み取り専用）。**変数・クリックアクション・
バインディング**（Phase 4 拡張トラック B）の「クリック→変数更新→プロパティ追従」を実機で
動作証跡化するには、実際にクリックを送って**前後**を撮る必要がある。Qt 内蔵 VNC（QVncServer）は
RFB の **PointerEvent** をマウス入力として QML シーンへ配送するので、`vnc-click-capture.py` で
クリックを 1 回送って before / after を保存できる（stdlib のみ・依存なし）。

```sh
# 実機側（vnc platform で起動。ウィンドウ実寸 1024x768 に合わせる）
QT_QPA_PLATFORM='vnc:size=1024x768' nohup /tmp/hmi_runtime --open /tmp/action.json >/tmp/vnc.log 2>&1 </dev/null &

# 母艦側（Windows）: TOGGLE ボタン中心へクリックを送り前後を撮る
#   <before.png> <after.png> <click_x> <click_y> [<source-ip>]
python scripts/yocto/vnc-click-capture.py <board-ip> 5900 before.png after.png 512 209 <source-ip>
```

- **クリック座標はウィンドウ（VNC framebuffer）左上原点の画面ピクセル**。Simulator/Runtime は
  1024x768 ウィンドウに 800x600 キャンバスを `centerIn` するので、キャンバス座標 `(cx, cy)` は
  画面 `(112 + cx, 84 + cy)`（例：キャンバス `(400,125)` の Button 中心 → 画面 `(512,209)`）。
- **after は incremental でなく non-incremental（全面）で撮る**：QVnc は変化が無いと incremental
  要求に応答を保留するため、`recv` がブロックして socket timeout になる。`vnc-click-capture.py` は
  before / after とも全面取得にして確実化している。
- before/after を 1 枚に合成するのは任意（README 掲載は PIL で横並びにした `task-43-runtime-action.png`）。

### mDNS / 接続の追加の罠（Task 43 で踏んだ）

- **mDNS が IPv6（AAAA）しか返さないことがある**：`Resolve-DnsName imx8mp-lpddr4-evk.local` が
  `fe80::...`（IPv6 link-local）だけを返し IPv4（A）が出ない場合がある。IPv4 を引くには
  **`Resolve-DnsName imx8mp-lpddr4-evk.local -Type A`** で A レコードを明示照会する。
  IPv6 link-local で直接 ping するなら zone id 付き（`fe80::...%<ifIndex>`）。
- **SSH 鍵認証は非対話で回る**（`-o BatchMode=yes` で確認可）。PowerShell 越しに ssh/scp を呼ぶと
  known_hosts 追加の警告が stderr に出て `$LASTEXITCODE`/`$?` が偽陰性になることがあるが、
  標準出力の内容で成否を判断する（`2>&1` 由来の NativeCommandError は無視してよい）。
