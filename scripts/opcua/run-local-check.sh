#!/usr/bin/env bash
# OPC-UA 読込/購読 + 書込を「1 コマンドで再現実行」する self-check（Claude Code / 開発者 / 将来の CI 用）。
#
# 何をするか：
#   1. asyncua が動く Python を見つけて venv を用意する（無ければ作って `pip install asyncua`）。
#      ※ Homebrew python3.14 は pyexpat 破損で asyncua を import/install できないため、
#        expat が健全な Python（/usr/bin/python3 等）を自動選択する（dev-environment.md 参照）。
#   2. OPC-UA 込みでビルドされた hmi_simulator を探す。
#   3. 既存 E2E を回す：
#        - `tests/e2e/test_opcua_read.py`（OP-2：asyncua ソフトサーバ → 購読 → Label 追従）
#        - `tests/e2e/test_opcua_write.py`（OP-4：HMI 入力確定 → writeVariable → サーバノード書込）
#
# ctest 既定の Python では asyncua が入らず e2e_opcua_* が SKIP されるため、この経路だと
# 実際の round-trip を確認できる。終了コード：両方 OK=0 / どちらか FAIL=1 / 両方 SKIP=77。
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

# 3) 既存 E2E を実行（offscreen でウィンドウシステム不要）。read → write の順で両方回す。
echo "OPC-UA self-check: $("$VENV/bin/python" -c 'import asyncua;print("asyncua",asyncua.__version__)')"
echo "  simulator: $SIM"
cd "$ROOT/tests/e2e"

run_e2e() {
    # 個別 E2E を回し、exit code（0=OK / 77=SKIP / それ以外=FAIL）を表示して返す。
    local script="$1"
    echo "--- $script ---"
    set +e
    QT_QPA_PLATFORM=offscreen "$VENV/bin/python" "$script" --simulator-binary "$SIM"
    local rc=$?
    set -e
    return $rc
}

# set -e 下では run_e2e が 77(SKIP) や FAIL を返した時点で次行の代入に達する前にシェルが
# 終了し、両方実行して集計するロジックが働かない（Codex PR #145 [Major]）。errexit 対象外の
# `|| read_rc=$?` で終了コードを捕捉する（成功時は 0 を保つよう既定 0 を入れておく）。
read_rc=0;  run_e2e test_opcua_read.py  || read_rc=$?
write_rc=0; run_e2e test_opcua_write.py || write_rc=$?

echo "=== OPC-UA self-check 結果: read=$read_rc write=$write_rc (0=OK / 77=SKIP / 他=FAIL) ==="
# 判定（OP-4 検証手順として「片方 SKIP を成功扱いしない」＝Codex PR #145 [Major]）：
#   - どちらかが FAIL（0/77 以外）なら 1。
#   - **read/write の両方が 0（実際に検証できた）ときだけ 0**。
#   - それ以外（少なくとも片方が SKIP・FAIL なし）は 77＝未検証として SKIP 扱い。
#     例：write がポート衝突/サーバ起動失敗で 77 でも read 成功なら、書込を未検証のまま 0 にしない。
if { [ "$read_rc" != 0 ] && [ "$read_rc" != 77 ]; } \
   || { [ "$write_rc" != 0 ] && [ "$write_rc" != 77 ]; }; then
    exit 1
fi
if [ "$read_rc" = 0 ] && [ "$write_rc" = 0 ]; then
    exit 0
fi
exit 77
