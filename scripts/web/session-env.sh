#!/usr/bin/env bash
# SessionStart hook: クラウド（Web）セッションで Qt の場所を CMAKE_PREFIX_PATH に通す。
#
# setup.sh が /opt/Qt に Qt を入れた後、ビルド時に毎回 -DCMAKE_PREFIX_PATH を渡さなくて済むよう、
# セッション開始時に CMAKE_PREFIX_PATH を $CLAUDE_ENV_FILE へ書き出す（以降の Bash に引き継がれる）。
#
# ローカル（macOS / Windows）では CLAUDE_CODE_REMOTE!=true なので即 no-op。既存の Qt 設定を壊さない。
set -euo pipefail

[ "${CLAUDE_CODE_REMOTE:-}" != "true" ] && exit 0

# 1) setup.sh が残したマーカーを最優先で読む（HMI_QT_OUTDIR でカスタム出力先にしても追従。Codex PR #70 P2）
# 2) 無ければ ${HMI_QT_OUTDIR:-/opt/Qt}/<version>/gcc_64 を glob で探索（最新を採用）
QT_PREFIX_FILE="${HMI_QT_PREFIX_FILE:-/opt/hmi-web-qt-prefix}"
QT_OUTDIR="${HMI_QT_OUTDIR:-/opt/Qt}"
QT_PREFIX=""
if [ -f "${QT_PREFIX_FILE}" ]; then
  QT_PREFIX="$(cat "${QT_PREFIX_FILE}" 2>/dev/null || true)"
fi
if [ -z "${QT_PREFIX}" ] || [ ! -d "${QT_PREFIX}/lib/cmake/Qt6" ]; then
  QT_PREFIX="$(ls -d "${QT_OUTDIR}"/*/gcc_64 2>/dev/null | sort -V | tail -1 || true)"
fi
[ -z "${QT_PREFIX}" ] && exit 0
[ ! -d "${QT_PREFIX}/lib/cmake/Qt6" ] && exit 0

# $CLAUDE_ENV_FILE には "export KEY=value" 形式で書く（公式 hooks docs 準拠）。
# 単なる "KEY=value" だと後続シェルの変数にはなっても export されず、子プロセスの
# cmake に環境変数として渡らない（Codex PR #70 指摘 P1）。
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export CMAKE_PREFIX_PATH=${QT_PREFIX}" >> "${CLAUDE_ENV_FILE}"
  echo "[hmi/web] CMAKE_PREFIX_PATH=${QT_PREFIX} を設定しました"
fi
