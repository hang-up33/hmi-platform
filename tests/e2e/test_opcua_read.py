"""Phase 9 / OP-2: OPC-UA 購読読込の cross-app E2E。

``OpcUaController``（Simulator 共有ソース＝Runtime も継承）が **OPC-UA クライアント**として
サーバのノードを MonitoredItem 購読し、既存の変数ストア + binding 経路へ流すことを検証する。
実 OPC-UA サーバ / PLC は CI / Web から不達なので、自動検証は **asyncua ソフトサーバ**相手に
行う（``opcua_server.py`` をサブプロセスで起動）。

シナリオ：

1. **ソフトサーバ起動**：``opcua_server.py`` を ``opc.tcp://127.0.0.1:<port>`` で起動し、
   ``ns=2;s=Temp``（Int32）に固定値 ``1234`` を載せる。``127.0.0.1:<port>`` が listen するまで待つ。
2. **fixture JSON**：``connections[]`` にそのサーバ（proto=opcua / endpoint）、``temp``（int）変数に
   ``source={connection,nodeId:"ns=2;s=Temp",poll}`` を付け、その変数を ``text`` binding で読む
   観測用 Label（``echo001``）を持つプロジェクトを書く。
3. **Simulator 段（本 E2E の主眼）**：fixture を Simulator に ``--open`` で読ませると、
   ``Main.qml`` が ``opcuaController.configure`` を呼んで接続 → 購読を開始し、ノードの初期値が
   ``variableUpdated`` → ``VariableStore.setValue("temp", 1234)`` → ``text`` binding 追従で
   ``echo001`` Label に反映される。Label text が ``"1234"`` になるのを ``getStringProperty`` で観測する。

Modbus 読込 E2E（``test_modbus_read.py``）の OPC-UA 版。Qt OPC-UA はサーバ機能を持たないため、
C++ ユニットでは実購読を回せず、購読 round-trip はこの E2E が担う。実行環境：E2E は
macOS / Linux（``HMI_ENABLE_E2E=ON``）+ asyncua + Qt OPC-UA backend（open62541）がある環境のみ。
asyncua 不在 / サーバ起動失敗時は SKIP（exit 77）して緑を妨げない。
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time

from harness import _wait_for_port, call_method, spix_app

_SIM_WIN = "hmiSimulatorWindow"

# ソフトサーバの固定パラメータ。
_SERVER_PORT = 14840
_NODE_IDENT = "Temp"
_NODE_NS = 2
_NODE_VALUE = 1234
_NODE_ID = f"ns={_NODE_NS};s={_NODE_IDENT}"
_VAR_NAME = "temp"
_POLL_MS = 100

# ctest が SKIP として扱う終了コード（CMakeLists の SKIP_RETURN_CODE と一致させる）。
_SKIP_EXIT = 77


def _fixture_json(port: int) -> dict:
    """opcua connection + source(nodeId) 付き変数 + 観測用 Label（text binding）を持つプロジェクト。"""
    return {
        "project": "OP-2 OPC-UA read E2E",
        "connections": [
            {
                "id": "srv1",
                "proto": "opcua",
                "endpoint": f"opc.tcp://127.0.0.1:{port}",
            }
        ],
        "variables": [
            {
                "name": _VAR_NAME,
                "type": "int",
                "initial": "0",
                "source": {
                    "connection": "srv1",
                    "nodeId": _NODE_ID,
                    "poll": _POLL_MS,
                },
            }
        ],
        "screens": [
            {
                "name": "Main",
                "widgets": [
                    {
                        "id": "echo001",
                        "type": "Label",
                        "x": 60,
                        "y": 60,
                        "width": 200,
                        "height": 40,
                        "text": "?",
                        "bindings": [{"property": "text", "variable": _VAR_NAME}],
                    }
                ],
            }
        ],
    }


def _get_str_property(url: str, path: str, prop: str) -> str:
    import re

    body = call_method(url, "getStringProperty", path, prop)
    m = re.search(r"<value>(?:<string>)?(.*?)(?:</string>)?</value>", body, re.DOTALL)
    if not m:
        raise RuntimeError(
            f"Failed to extract {prop} from {path}. Response head: {body[:300]!r}"
        )
    return m.group(1).strip()


def _start_server(port: int) -> subprocess.Popen:
    """opcua_server.py をサブプロセスで起動し、listen するまで待つ。"""
    server_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "opcua_server.py")
    proc = subprocess.Popen(
        [
            sys.executable,
            server_script,
            "--port",
            str(port),
            "--ns",
            str(_NODE_NS),
            "--ident",
            _NODE_IDENT,
            "--value",
            str(_NODE_VALUE),
        ]
    )
    if not _wait_for_port("127.0.0.1", port, timeout=15.0):
        _stop_server(proc)
        raise RuntimeError(f"OPC-UA server did not listen on 127.0.0.1:{port}")
    return proc


def _stop_server(proc: subprocess.Popen) -> None:
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


def _simulator_reads_server(simulator_binary: str, port: int, save_path: str) -> None:
    """Simulator を ``--open`` で起動し、OPC-UA 購読値が Label へ追従するのを観測する。"""
    with spix_app(simulator_binary, port, extra_args=("--open", save_path)) as url:
        echo = f"{_SIM_WIN}/widget_echo001/hmiLabel"
        call_method(url, "waitForItem", echo, 3000)

        # 接続確立（discovery → connectToEndpoint）+ 購読作成 + 初期値通知を経て Label text が
        # サーバのノード値 "1234" へ追従する。短いポーリングで待つ。
        deadline = time.monotonic() + 12.0
        text = ""
        while time.monotonic() < deadline:
            text = _get_str_property(url, echo, "text")
            if text == str(_NODE_VALUE):
                break
            time.sleep(0.2)
        if text != str(_NODE_VALUE):
            raise RuntimeError(
                f"echo Label text={text!r} != {str(_NODE_VALUE)!r} "
                "(OPC-UA subscription did not flow to variable/binding)"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator-binary", required=True)
    parser.add_argument("--simulator-port", type=int, default=9877)
    parser.add_argument("--server-port", type=int, default=_SERVER_PORT)
    args = parser.parse_args()

    # asyncua 不在なら SKIP（緑を妨げない）。
    try:
        import asyncua  # noqa: F401
    except ImportError:
        print("SKIP: asyncua not installed", file=sys.stderr)
        return _SKIP_EXIT

    save_path = ""
    server: subprocess.Popen | None = None
    try:
        fd, save_path = tempfile.mkstemp(prefix="hmi_op2_fixture_", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(_fixture_json(args.server_port), f, ensure_ascii=False, indent=2)

        try:
            server = _start_server(args.server_port)
        except RuntimeError as exc:
            print(f"SKIP: {exc}", file=sys.stderr)
            return _SKIP_EXIT

        _simulator_reads_server(args.simulator_binary, args.simulator_port, save_path)
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    finally:
        if server is not None:
            _stop_server(server)
        if save_path:
            try:
                os.unlink(save_path)
            except FileNotFoundError:
                pass

    print(
        f"OK: simulator subscribes OPC-UA node ({_NODE_ID}={_NODE_VALUE}) -> "
        f"variable {_VAR_NAME} -> Label text follows to {_NODE_VALUE!r}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
