# scripts/yocto — Yocto SDK クロスビルド（Phase 3-B / Task 23・24）

`hmi_runtime` を i.MX8MP（aarch64 / Yocto scarthgap）向けにクロスビルドし、実機で
起動するための補助スクリプトと手順。**WSL2 内で実行する想定**で、macOS / Windows の
ホストビルド（`build/` ・ `build-mingw/`）には影響しない。

計画と設計判断の正本は [Docs/phase3b-runtime-plan.md](../../Docs/phase3b-runtime-plan.md)、
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
