"""Phase 9 / OP-4: OPC-UA 書込 + 接続状態の cross-app E2E。

OP-2（``test_opcua_read.py``）は OPC-UA サーバ → HMI の **読み**（購読 → 変数 → binding 追従）を
見た。本 E2E は逆向きの **書き**（HMI 操作 → OPC-UA ノード更新）を初めて観測する（Modbus 書込
E2E ``test_modbus_write.py`` の OPC-UA 版）：

1. **書込可能ソフトサーバ起動**：``opcua_server.py --writable`` を
   ``opc.tcp://127.0.0.1:<port>`` で起動し、``ns=2;s=Setpoint``（Int32）を初期値 ``0`` で公開する
   （``set_writable(True)`` でクライアント書込を許可）。
2. **fixture JSON**：``connections[]`` にそのサーバ（proto=opcua / endpoint）、``setpoint``（int）
   変数に ``source={connection,nodeId:"ns=2;s=Setpoint",poll}`` を付け、その変数を ``value``
   binding で読み書きする NumericField（``num001``）を持つプロジェクトを書く。
3. **Simulator 段（本 E2E の主眼）**：fixture を Simulator に ``--open`` で読ませると、
   ``Main.qml`` が ``opcuaController.configure`` を呼び、接続 → 購読を開始する（初期値 0 を購読で
   受けて binding 追従するのを待ち、接続確立を確認してから書く）。NumericField の入力テキストを
   ``setStringProperty`` で設定し、公開メソッド ``commitValue()`` を ``invokeMethod`` で叩いて確定を
   模す（Spix は ``editingFinished`` を発火できない）。確定で ``writeBoundValue`` が
   ``VariableStore.setValue`` + ``OpcUaController.writeVariable`` を呼び、サーバのノードが書き換わる。
4. **検証**：Python 側で別の asyncua client を使ってサーバのノードを読み返し、入力値（``4242``）に
   変わったことを assert する。

読込（variableUpdated → setValue）由来の変化では writeVariable を呼ばない（経路で分離）ので、
読込ループ無しで「ユーザー操作 → OPC-UA write」だけが成立することを E2E で担保する。

実行環境：E2E は macOS / Linux（``HMI_ENABLE_E2E=ON``）+ asyncua + Qt OPC-UA backend
（open62541）がある環境のみ。asyncua 不在 / サーバ起動失敗時は SKIP（exit 77）して緑を妨げない。
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import re
import subprocess
import sys
import tempfile
import time

from harness import _wait_for_port, call_method, spix_app

_SIM_WIN = "hmiSimulatorWindow"

# 書込可能ソフトサーバの固定パラメータ。
_SERVER_PORT = 14841
_NODE_IDENT = "Setpoint"
_NODE_NS = 2
# サーバ初期値は **HMI 側の初期値（_HMI_INITIAL）と必ず別の値**にする。両方 0 だと、購読が届く前の
# NumericField の静的/初期表示も "0" なので「接続確立待ち」が初回チェックで即 break し、未接続のまま
# commit して writeVariable が skip され書込 E2E がフレークする（Codex PR #145 [Major]）。サーバ値を
# 7 にしておけば、text が "7" に追従した時点で「購読が実際に届いた＝接続確立」を確実に判定できる。
_INITIAL_VALUE = 7
_HMI_INITIAL = "0"
_NODE_ID = f"ns={_NODE_NS};s={_NODE_IDENT}"
_VAR_NAME = "setpoint"
_TYPED_VALUE = "4242"
_POLL_MS = 100

# ctest が SKIP として扱う終了コード（CMakeLists の SKIP_RETURN_CODE と一致させる）。
_SKIP_EXIT = 77


def _fixture_json(port: int) -> dict:
    """opcua connection + source(nodeId) 付き変数 + NumericField（value binding）を持つプロジェクト。"""
    return {
        "project": "OP-4 OPC-UA write E2E",
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
                "initial": _HMI_INITIAL,
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
                        "id": "num001",
                        "type": "NumericField",
                        "x": 60,
                        "y": 60,
                        "width": 160,
                        "height": 48,
                        "text": _HMI_INITIAL,
                        "bindings": [{"property": "value", "variable": _VAR_NAME}],
                    }
                ],
            }
        ],
    }


def _start_server(port: int) -> subprocess.Popen:
    """opcua_server.py --writable をサブプロセスで起動し、listen するまで待つ。"""
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
            str(_INITIAL_VALUE),
            "--writable",
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


def _read_server_node(port: int, ns: int, ident: str) -> int | None:
    """別の asyncua client でサーバのノード値を読み返す（write 検証用）。失敗時は None。"""

    async def _read() -> int | None:
        from asyncua import Client

        client = Client(f"opc.tcp://127.0.0.1:{port}")
        try:
            await client.connect()
            node = client.get_node(f"ns={ns};s={ident}")
            return int(await node.read_value())
        finally:
            try:
                await client.disconnect()
            except Exception:  # noqa: BLE001
                pass

    try:
        return asyncio.run(_read())
    except Exception:  # noqa: BLE001
        return None


def _get_str_property(url: str, path: str, prop: str) -> str:
    body = call_method(url, "getStringProperty", path, prop)
    m = re.search(r"<value>(?:<string>)?(.*?)(?:</string>)?</value>", body, re.DOTALL)
    if not m:
        raise RuntimeError(
            f"Failed to extract {prop} from {path}. Response head: {body[:300]!r}"
        )
    return m.group(1).strip()


def _simulator_writes_server(simulator_binary: str, sim_port: int, server_port: int,
                             save_path: str) -> None:
    """Simulator を ``--open`` で起動し、commitValue → writeVariable → サーバ書込を観測する。"""
    with spix_app(simulator_binary, sim_port, extra_args=("--open", save_path)) as url:
        num_wrapper = f"{_SIM_WIN}/widget_num001"
        numeric = f"{num_wrapper}/hmiNumericField"
        call_method(url, "waitForItem", numeric, 3000)

        # 接続確立 → 購読を待つ。接続が立つまで commitValue しても write は Connected 待ちで
        # スキップされるため、**サーバ初期値（_INITIAL_VALUE=7、HMI 側初期値 0 とは別値）が購読で
        # 届いて text が "7" に変わる**のを確認してから書く（HMI 初期表示 "0" との一致では接続前でも
        # 即 break してしまうため、必ずサーバ由来の値への追従で接続を判定する）。
        deadline = time.monotonic() + 12.0
        connected = False
        while time.monotonic() < deadline:
            if _get_str_property(url, numeric, "text") == str(_INITIAL_VALUE):
                connected = True
                break
            time.sleep(0.2)
        if not connected:
            raise RuntimeError(
                f"subscription did not deliver server value {_INITIAL_VALUE} to NumericField "
                "(connection not established; write would be skipped while disconnected)"
            )

        # 書き：入力テキストを設定し commitValue() で確定を模す。確定で writeBoundValue が
        # VariableStore.setValue + OpcUaController.writeVariable を呼び、サーバへ書く。
        call_method(url, "setStringProperty", numeric, "text", _TYPED_VALUE)
        body = call_method(url, "invokeMethod", numeric, "commitValue", [])
        if "<fault>" in body:
            raise RuntimeError(f"commitValue invokeMethod fault. Body: {body[:500]!r}")

        # サーバ側のノードが入力値へ変わるのを Python から読み返して確認する。
        deadline = time.monotonic() + 12.0
        observed = None
        while time.monotonic() < deadline:
            observed = _read_server_node(server_port, _NODE_NS, _NODE_IDENT)
            if observed == int(_TYPED_VALUE):
                break
            time.sleep(0.2)
        if observed != int(_TYPED_VALUE):
            raise RuntimeError(
                f"server node {_NODE_ID}={observed!r} != {int(_TYPED_VALUE)!r} "
                "(HMI commit did not write to OPC-UA node via OpcUaController.writeVariable)"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator-binary", required=True)
    parser.add_argument("--simulator-port", type=int, default=9879)
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
        fd, save_path = tempfile.mkstemp(prefix="hmi_op4_fixture_", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(_fixture_json(args.server_port), f, ensure_ascii=False, indent=2)

        try:
            server = _start_server(args.server_port)
        except RuntimeError as exc:
            print(f"SKIP: {exc}", file=sys.stderr)
            return _SKIP_EXIT

        _simulator_writes_server(
            args.simulator_binary, args.simulator_port, args.server_port, save_path
        )
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
        f"OK: simulator commit writes NumericField value -> OpcUaController.writeVariable -> "
        f"server node {_NODE_ID} becomes {_TYPED_VALUE}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
