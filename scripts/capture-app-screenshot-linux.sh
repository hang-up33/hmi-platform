#!/usr/bin/env bash
# Claude Code on the web（ヘッドレス Linux）/ CI 用 GUI スクショ撮影スクリプト。
#
# 仕組み: Qt の offscreen プラットフォーム（QT_QPA_PLATFORM=offscreen）で
#   hmi_editor / hmi_simulator / hmi_runtime を起動し、アプリ内蔵の
#   `--screenshot <path>`（ScreenshotGrabber.h）が QQuickWindow::grabWindow() で
#   オフスクリーン描画結果を PNG に書き出して自動終了する。
#   ウィンドウシステム（X11 / Wayland）も Xvfb も不要。
#
#   実機 i.MX8MP の VNC キャプチャ（scripts/yocto/vnc-capture.py）とは別経路。
#   こちらは PC ビルドのバイナリをヘッドレス環境で撮るための手段。
#
# 前提: 先に cmake build 済みであること（scripts/web/setup.sh で Qt 導入 →
#   cmake -S . -B build && cmake --build build）。日本語ラベルを正しく出すには
#   日本語フォント（fonts-noto-cjk 等）が必要（setup.sh が導入する）。
#
# 使い方:
#   scripts/capture-app-screenshot-linux.sh -a editor    -o Docs/screenshots/editor.png
#   scripts/capture-app-screenshot-linux.sh -a simulator -o Docs/screenshots/sim.png  -j sample.json
#   scripts/capture-app-screenshot-linux.sh -a runtime   -o out.png -j sample.json -d 1000
#
# オプション:
#   -a <app>     editor | simulator | runtime（既定 editor）
#   -o <path>    出力 PNG パス（既定 Docs/screenshots/<app>-linux.png）
#   -j <json>    起動時に --open で読み込むプロジェクト JSON（任意）
#   -d <ms>      撮影前の待機ミリ秒（既定 700。過渡状態を狙うとき増やす）
#   -b <dir>     ビルドディレクトリ（既定 build）
set -euo pipefail

APP="editor"
OUT=""
JSON=""
DELAY="700"
BUILD_DIR="build"

usage() {
  # 先頭コメントブロック（2〜27 行）を help として表示する。
  sed -n '2,27p' "$0"
  exit "${1:-0}"
}

while getopts ":a:o:j:d:b:h" opt; do
  case "$opt" in
    a) APP="$OPTARG" ;;
    o) OUT="$OPTARG" ;;
    j) JSON="$OPTARG" ;;
    d) DELAY="$OPTARG" ;;
    b) BUILD_DIR="$OPTARG" ;;
    h) usage 0 ;;
    :) echo "[capture] オプション -$OPTARG には引数が必要です" >&2; usage 1 ;;
    *) echo "[capture] 不明なオプション: -$OPTARG" >&2; usage 1 ;;
  esac
done

# リポジトリルートへ移動（スクリプトの 1 つ上）。相対パスの基準を安定させる。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
cd "${REPO_ROOT}"

case "$APP" in
  editor)    BIN="${BUILD_DIR}/Editor/hmi_editor" ;;
  simulator) BIN="${BUILD_DIR}/Simulator/hmi_simulator" ;;
  runtime)   BIN="${BUILD_DIR}/Runtime/hmi_runtime" ;;
  *) echo "[capture] -a は editor|simulator|runtime のいずれか: $APP" >&2; exit 1 ;;
esac

if [ ! -x "$BIN" ]; then
  echo "[capture] バイナリが見つかりません: ${BIN}" >&2
  echo "[capture] 先にビルドしてください: cmake -S . -B ${BUILD_DIR} -DCMAKE_PREFIX_PATH=\$CMAKE_PREFIX_PATH && cmake --build ${BUILD_DIR}" >&2
  exit 1
fi

if [ -z "$OUT" ]; then
  OUT="Docs/screenshots/${APP}-linux.png"
fi
mkdir -p "$(dirname "$OUT")"

# offscreen + software backend が最もヘッドレスで安定する（GL ドライバ不問）。
# 必要なら呼び出し側で QT_QUICK_BACKEND を上書きできるよう、未設定時のみ既定値を入れる。
export QT_QPA_PLATFORM="offscreen"
export QT_QUICK_BACKEND="${QT_QUICK_BACKEND:-software}"

ARGS=(--screenshot "$OUT" --screenshot-delay "$DELAY")
if [ -n "$JSON" ]; then
  if [ ! -f "$JSON" ]; then
    echo "[capture] 指定 JSON が存在しません: ${JSON}" >&2
    exit 1
  fi
  ARGS+=(--open "$JSON")
fi

echo "[capture] ${APP} を offscreen 起動して撮影します -> ${OUT}"
"$BIN" "${ARGS[@]}"

if [ ! -s "$OUT" ]; then
  echo "[capture] 失敗: PNG が生成されませんでした (${OUT})" >&2
  exit 1
fi
echo "[capture] 完了: ${OUT}"
