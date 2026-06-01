#!/usr/bin/env bash
#
# hmi_runtime を Yocto SDK で aarch64 クロスビルドする（Phase 3-B / Task 23）。
#
# 想定実行環境: Windows 母艦の WSL2 内（Ubuntu 22.04）。
#   - macOS / Windows のホストビルド（build/ ・ build-mingw/）には一切影響しない。
#   - SDK は本リポジトリの計画どおり、新 BSP（scarthgap, imx-6.6.52-2.2.x）から
#     `bitbake meta-toolchain-qt6` で自前生成したものを install して使う
#     （詳細は Docs/phase3b-runtime-plan.md と scripts/yocto/README.md）。
#
# 使い方:
#   ./scripts/yocto/cross-build.sh
#
# 環境変数で上書き可:
#   HMI_SDK_ENV    SDK の environment-setup-* スクリプト（既定: ~/qt6-sdk/environment-setup-*）
#   HMI_SRC_DIR    リポジトリルート（既定: このスクリプトの 2 つ上）
#   HMI_BUILD_DIR  ビルドツリー（既定: ~/build-yocto。WSL ext4 上に置くと高速）
#
set -eo pipefail

# --- SDK 環境スクリプトを解決（armv8a / aarch64 どちらの命名でも拾う）---
SDK_ENV="${HMI_SDK_ENV:-}"
if [ -z "$SDK_ENV" ]; then
  SDK_ENV="$(ls "$HOME"/qt6-sdk/environment-setup-* 2>/dev/null | head -1 || true)"
fi
if [ -z "$SDK_ENV" ] || [ ! -f "$SDK_ENV" ]; then
  echo "ERROR: SDK の environment-setup-* が見つからない。" >&2
  echo "  meta-toolchain-qt6 の .sh を install し、HMI_SDK_ENV で指定してください。" >&2
  echo "  例: HMI_SDK_ENV=\$HOME/qt6-sdk/environment-setup-armv8a-poky-linux $0" >&2
  exit 1
fi

SRC_DIR="${HMI_SRC_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
BUILD_DIR="${HMI_BUILD_DIR:-$HOME/build-yocto}"

echo "=== Yocto cross-build (Task 23) ==="
echo "SDK_ENV   : $SDK_ENV"
echo "SRC_DIR   : $SRC_DIR"
echo "BUILD_DIR : $BUILD_DIR"

# SDK 環境を source（CC/CXX/SYSROOT/OECORE_NATIVE_SYSROOT 等を設定）。
# shellcheck disable=SC1090
source "$SDK_ENV"

# 非対話スクリプトでは environment-setup-* が仕込む cmake alias が展開されず
# CMAKE_TOOLCHAIN_FILE が自動付与されない（Yocto ML 2018-01 既知事項）。
# そのため toolchain file を明示的に渡す。
#   - HMI_ENABLE_E2E=OFF : Spix / AnyRPC はクロスツールチェイン互換性に難があるため明示 OFF
#   - BUILD_TESTING=OFF  : 実機ランタイムにユニットテストは不要
cmake -S "$SRC_DIR" -B "$BUILD_DIR" \
  -DCMAKE_TOOLCHAIN_FILE="$OECORE_NATIVE_SYSROOT/usr/share/cmake/OEToolchainConfig.cmake" \
  -DHMI_ENABLE_E2E=OFF \
  -DBUILD_TESTING=OFF

# PC 専用の hmi_editor / hmi_simulator はクロスビルドしない（hmi_runtime のみ）。
# hmi_runtime は hmi_simulator_qmlplugin 等の必要依存だけを連れてビルドされる。
cmake --build "$BUILD_DIR" --target hmi_runtime

# --- 成果物の検証: aarch64 ELF であることを確認 ---
BIN="$BUILD_DIR/Runtime/hmi_runtime"
echo
echo "=== verify: file $BIN ==="
file "$BIN"
if file "$BIN" | grep -q "ARM aarch64"; then
  echo "OK: hmi_runtime は ARM aarch64 ELF として生成された。"
  echo "    実機へ: scp -O \"$BIN\" root@<board-ip>:/tmp/hmi_runtime"
else
  echo "NG: aarch64 ELF ではない（toolchain file が渡せていない可能性）。" >&2
  exit 1
fi
