#!/usr/bin/env bash
# OPC-UA 読込/購読を「1 コマンドで再現実行」する self-check（Claude Code / 開発者 / 将来の CI 用）。
#
# 何をするか：
#   1. asyncua が動く Python を見つけて venv を用意する（無ければ作って `pip install asyncua`）。
#      ※ Homebrew python3.14 は pyexpat 破損で asyncua を import/install できないため、
#        expat が健全な Python（/usr/bin/python3 等）を自動選択する（dev-environment.md 参照）。
#   2. OPC-UA 込みでビルドされた hmi_simulator を探す。
#   3. 既存 E2E `tests/e2e/test_opcua_read.py`（asyncua ソフトサーバ → 購読 → Label 追従）を回す。
#
# ctest 既定の Python では asyncua が入らず e2e_opcua_read が SKIP されるため、この経路だと
# 実際の購読 round-trip を確認できる。終了コードは E2E に従う（0=OK / 77=SKIP / 1=FAIL）。
#
# 使い方:
#   bash scripts/opcua/run-local-check.sh
#   HMI_SIM=/path/to/hmi_simulator bash scripts/opcua/run-local-check.sh   # バイナリを明示
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VENV="${HMI_OPCUA_VENV:-$ROOT/build/opcua-venv}"

# 1) hmi_simulator バイナリの解決（macOS .app / Linux 直下 / 明示指定）。
resolve_sim() {
    if [ -n "${HMI_SIM:-}" ]; then echo "$HMI_SIM"; return; fi
    local mac="$ROOT/build/Simulator/hmi_simulator.app/Contents/MacOS/hmi_simulator"
    local lin="$ROOT/build/Simulator/hmi_simulator"
    if [ -x "$mac" ]; then echo "$mac"; elif [ -x "$lin" ]; then echo "$lin"; else echo ""; fi
}
SIM="$(resolve_sim)"
if [ -z "$SIM" ] || [ ! -x "$SIM" ]; then
    echo "ERROR: hmi_simulator が見つからない。OPC-UA 込みでビルドしてから実行する:" >&2
    echo "  cmake -S . -B build -DCMAKE_PREFIX_PATH=/opt/homebrew/opt/qt && cmake --build build --target hmi_simulator" >&2
    echo "  （Qt OPC-UA kit が要る。手順は .claude/rules/dev-environment.md）" >&2
    exit 1
fi

# 2) asyncua が動く venv を用意（expat 健全な Python を選ぶ）。
if [ ! -x "$VENV/bin/python" ]; then
    PY=""
    for cand in python3.13 python3.12 python3.11 /usr/bin/python3 python3; do
        if command -v "$cand" >/dev/null 2>&1 && "$cand" -c "import xml.parsers.expat" >/dev/null 2>&1; then
            PY="$cand"; break
        fi
    done
    if [ -z "$PY" ]; then
        echo "ERROR: xml.parsers.expat が動く Python が見つからない（asyncua に必須）。" >&2
        exit 1
    fi
    echo "venv 作成: $PY -> $VENV"
    "$PY" -m venv "$VENV"
fi
if ! "$VENV/bin/python" -c "import asyncua" >/dev/null 2>&1; then
    echo "asyncua を導入中..."
    "$VENV/bin/pip" install --quiet --upgrade pip
    "$VENV/bin/pip" install --quiet asyncua
fi

# 3) 既存 E2E を実行（offscreen でウィンドウシステム不要）。
echo "OPC-UA self-check: $("$VENV/bin/python" -c 'import asyncua;print("asyncua",asyncua.__version__)')"
echo "  simulator: $SIM"
cd "$ROOT/tests/e2e"
QT_QPA_PLATFORM=offscreen "$VENV/bin/python" test_opcua_read.py --simulator-binary "$SIM"
