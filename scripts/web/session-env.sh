#!/usr/bin/env bash
# SessionStart hook: クラウド（Web）セッションで Qt の場所を CMAKE_PREFIX_PATH に通す。
#
# setup.sh が /opt/Qt に Qt を入れた後、ビルド時に毎回 -DCMAKE_PREFIX_PATH を渡さなくて済むよう、
# セッション開始時に CMAKE_PREFIX_PATH を $CLAUDE_ENV_FILE へ書き出す（以降の Bash に引き継がれる）。
#
# ローカル（macOS / Windows）では CLAUDE_CODE_REMOTE!=true なので即 no-op。既存の Qt 設定を壊さない。
set -euo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" != "true" ] && exit 0

# /opt/Qt/<version>/gcc_64 を探す（最新を採用）
QT_PREFIX="$(ls -d /opt/Qt/*/gcc_64 2>/dev/null | sort -V | tail -1 || true)"
[ -z "${QT_PREFIX}" ] && exit 0
[ ! -d "${QT_PREFIX}/lib/cmake/Qt6" ] && exit 0

# $CLAUDE_ENV_FILE があれば、そこへ書くと後続の Bash コマンドに環境変数が引き継がれる
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "CMAKE_PREFIX_PATH=${QT_PREFIX}" >> "${CLAUDE_ENV_FILE}"
  echo "[hmi/web] CMAKE_PREFIX_PATH=${QT_PREFIX} を設定しました"
fi
