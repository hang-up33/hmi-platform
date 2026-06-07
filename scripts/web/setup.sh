#!/usr/bin/env bash
# Claude Code on the web（クラウド実行環境）用 Qt6 セットアップスクリプト。
#
# 目的: Ubuntu 24.04 のクラウドコンテナに Qt6 を導入し、Editor/Simulator/Runtime を
#       ビルド・テスト（-platform offscreen / vnc）できる状態にする。
#
# 使い方（2 通り。いずれも「環境のネットワークアクセス = Full」が前提。既定の Trusted は
# download.qt.io を遮断するため aqtinstall が 403 で失敗する。詳細は Docs/claude-web-dev.md）:
#   1) 環境設定の「Setup script」欄に  bash scripts/web/setup.sh  を貼る（初回のみ実行・キャッシュされる＝推奨）
#   2) セッション内で手動: bash scripts/web/setup.sh
#
# 冪等: Qt が既に入っていれば再ダウンロードしない。CLAUDE_CODE_REMOTE!=true のローカルでは何もしない。
set -euo pipefail

# --- 設定（CI の jurplel/install-qt-action と同じ 6.10.0 に合わせる）---
QT_VERSION="${HMI_QT_VERSION:-6.10.0}"
QT_HOST="linux"
QT_TARGET="desktop"
QT_ARCH="linux_gcc_64"          # Qt 6.7+ の Linux x86_64 デスクトップ arch（aqt の表記）
QT_OUTDIR="${HMI_QT_OUTDIR:-/opt/Qt}"
# aqt はディスク上 <outdir>/<version>/gcc_64 に展開する（arch 名と実ディレクトリ名が異なる点に注意）
QT_PREFIX="${QT_OUTDIR}/${QT_VERSION}/gcc_64"
# 解決した prefix を固定パスのマーカーに残し、SessionStart hook（session-env.sh）が
# HMI_QT_OUTDIR を知らなくても読めるようにする（Codex PR #70 P2 指摘）。
QT_PREFIX_FILE="${HMI_QT_PREFIX_FILE:-/opt/hmi-web-qt-prefix}"

# ローカル（非クラウド）では何もしない。SessionStart hook 経由でも安全に no-op になる。
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  echo "[hmi/web-setup] CLAUDE_CODE_REMOTE != true のためスキップ（ローカル環境）"
  exit 0
fi

# 解決した prefix をマーカーへ書く（hook がカスタム出力先でも読めるように）
write_prefix_marker() {
  echo "${QT_PREFIX}" > "${QT_PREFIX_FILE}" 2>/dev/null \
    && echo "[hmi/web-setup] prefix マーカー: ${QT_PREFIX_FILE} -> ${QT_PREFIX}" \
    || echo "[hmi/web-setup] WARN: マーカー書込み不可: ${QT_PREFIX_FILE}（hook は glob で探索）" >&2
}

# フォントは Qt キャッシュの有無に関わらず必要（ヘッドレス GUI スクショの日本語ラベル
# 豆腐 □ 回避）。下の「Qt 既導入なら exit 0」より **前** に冪等導入する。さもないと
# スナップショット復元済みの Web 環境（＝常用ケース）でフォントだけ入らず文字化けする
# （Codex PR #71 P2 指摘）。dpkg -s で既導入なら apt を呼ばず即 no-op。
ensure_fonts() {
  if dpkg -s fonts-noto-cjk >/dev/null 2>&1; then
    return 0
  fi
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq || true
  apt-get install -y --no-install-recommends fonts-dejavu-core fonts-noto-cjk \
    || apt-get install -y --no-install-recommends fonts-dejavu-core || true
}
ensure_fonts

# 既に導入済みなら即終了（環境キャッシュ復元後・SessionStart 再実行時の冪等性）
if [ -d "${QT_PREFIX}/lib/cmake/Qt6" ]; then
  echo "[hmi/web-setup] Qt 既導入: ${QT_PREFIX}（スキップ）"
  write_prefix_marker
  exit 0
fi

echo "[hmi/web-setup] Qt ${QT_VERSION}（${QT_ARCH}）を ${QT_OUTDIR} に導入します"

# --- Qt のビルド・実行に必要な OS ライブラリ ---
# - 実行時(offscreen/vnc/QtQuick): libgl1 libegl1 libxkbcommon0 libfontconfig1 ...
# - ビルド時(find_package(Qt6 Gui) が WrapOpenGL=OpenGL dev を要求): *-dev 一式が無いと configure が失敗する
# - フォント（fonts-noto-cjk 等）は上の ensure_fonts で Qt キャッシュ前に導入済み。
# 既に入っていれば apt はスキップ。-t64 系の名前ゆれは握りつぶす。
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq || true
apt-get install -y --no-install-recommends \
  libgl1 libegl1 libegl-mesa0 libxkbcommon0 libfontconfig1 libfreetype6 libdbus-1-3 \
  libglib2.0-0t64 libx11-6 libxcb1 \
  libgl-dev libglx-dev libopengl-dev libegl-dev mesa-common-dev || \
  apt-get install -y --no-install-recommends libgl1 libegl1 libgl-dev libopengl-dev mesa-common-dev || true

# --- aqtinstall を venv に入れて Qt を取得 ---
AQT_VENV="/opt/aqt-venv"
if [ ! -x "${AQT_VENV}/bin/aqt" ]; then
  python3 -m venv "${AQT_VENV}"
  "${AQT_VENV}/bin/pip" install --quiet --upgrade pip
  "${AQT_VENV}/bin/pip" install --quiet aqtinstall
fi

# QtQuick(qtdeclarative) / qtshadertools は Qt 6.10 では base デスクトップパッケージに含まれるため
# -m 指定は不要（addon 扱いにすると "not found while parsing XML" で落ちる）。
# 追加 addon が要るときは HMI_QT_MODULES（スペース区切り）で渡す。
EXTRA_MODULES="${HMI_QT_MODULES:-}"
# aqt は cwd に aqtinstall.log を吐くため、リポジトリを汚さないよう /tmp で実行する。
# shellcheck disable=SC2086
( cd /tmp && "${AQT_VENV}/bin/aqt" install-qt "${QT_HOST}" "${QT_TARGET}" "${QT_VERSION}" "${QT_ARCH}" \
  -O "${QT_OUTDIR}" \
  ${EXTRA_MODULES:+-m ${EXTRA_MODULES}} )

if [ ! -d "${QT_PREFIX}/lib/cmake/Qt6" ]; then
  echo "[hmi/web-setup] ERROR: 期待した Qt prefix が見つかりません: ${QT_PREFIX}" >&2
  echo "[hmi/web-setup] 展開先を確認してください: ls ${QT_OUTDIR}" >&2
  exit 1
fi

write_prefix_marker
echo "[hmi/web-setup] 完了。CMAKE_PREFIX_PATH=${QT_PREFIX}"
echo "[hmi/web-setup] ビルド例: cmake -S . -B build -DCMAKE_PREFIX_PATH=${QT_PREFIX} && cmake --build build"
