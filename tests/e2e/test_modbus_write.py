"""Phase 7 / MB-4: Modbus TCP 書込 + 接続状態の cross-app E2E。

MB-2（``test_modbus_read.py``）は PLC → HMI の **読み**（ポーリング → 変数 → binding 追従）を
見た。本 E2E は逆向きの **書き**（HMI 操作 → PLC レジスタ更新）を初めて観測する：

1. **ソフトスレーブ起動**：``modbus_slave.py`` を ``127.0.0.1:<port>`` で起動し、holding
   register addr 2 を初期値 ``0`` で用意する。
2. **fixture JSON**：``connections[]`` にそのスレーブ、``setpoint``（int）変数に
   ``source={connection,reg:"holding",address:2,poll}`` を付け、その変数を ``value`` binding で
   読み書きする NumericField（``num001``）を持つプロジェクトを書く。
3. **Simulator 段（本 E2E の主眼）**：fixture を Simulator に ``--open`` で読ませると、
   ``Main.qml`` が ``modbusController.configure`` を呼び、接続状態が ``connected`` になる。
   NumericField の入力テキストを ``setStringProperty`` で設定し、公開メソッド ``commitValue()``
   を ``invokeMethod`` で叩いて確定を模す（Spix は ``editingFinished`` を発火できない）。確定で
   ``writeBoundValue`` が ``VariableStore.setValue`` + ``ModbusController.writeVariable`` を呼び、
   PLC（ソフトスレーブ）の holding register が書き換わる。
4. **検証**：Python 側で別の pymodbus client を使ってスレーブの holding[2] を読み返し、
   入力値（``4242``）に変わったことを assert する。

読込（variableUpdated → setValue）由来の変化では writeVariable を呼ばない（経路で分離）ので、
読込ループ無しで「ユーザー操作 → PLC write」だけが成立することを E2E で担保する。

実行環境：E2E は macOS / Linux（``HMI_ENABLE_E2E=ON``）+ pymodbus がある環境のみ。pymodbus
不在 / スレーブ起動失敗時は SKIP（exit 77）して緑を妨げない。
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

# ソフトスレーブの固定パラメータ。
_SLAVE_PORT = 15021
_HR_ADDRESS = 2
_VAR_NAME = "setpoint"
_TYPED_VALUE = "4242"
_POLL_MS = 200

# ctest が SKIP として扱う終了コード（CMakeLists の SKIP_RETURN_CODE と一致させる）。
_SKIP_EXIT = 77


def _fixture_json(port: int) -> dict:
    """connection + source 付き変数 + NumericField（value binding）を持つプロジェクト。"""
    return {
        "project": "MB-4 Modbus write E2E",
        "connections": [
            {
                "id": "plc1",
                "proto": "modbusTcp",
                "host": "127.0.0.1",
                "port": port,
                "unitId": 1,
            }
        ],
        "variables": [
            {
                "name": _VAR_NAME,
                "type": "int",
                "initial": "0",
                "source": {
                    "connection": "plc1",
                    "reg": "holding",
                    "address": _HR_ADDRESS,
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
                        "text": "0",
                        "bindings": [{"property": "value", "variable": _VAR_NAME}],
                    }
                ],
            }
        ],
    }


def _start_slave(port: int) -> subprocess.Popen:
    """modbus_slave.py をサブプロセスで起動し、listen するまで待つ（holding[addr]=0 初期）。"""
    slave_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "modbus_slave.py")
    proc = subprocess.Popen(
        [
            sys.executable,
            slave_script,
            "--port",
            str(port),
            "--hr-address",
            str(_HR_ADDRESS),
            "--hr-value",
            "0",
        ]
    )
    if not _wait_for_port("127.0.0.1", port, timeout=10.0):
        _stop_slave(proc)
        raise RuntimeError(f"Modbus slave did not listen on 127.0.0.1:{port}")
    return proc


def _stop_slave(proc: subprocess.Popen) -> None:
    proc.terminate()
    try:
        proc.wait(timeout=5)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)


def _read_slave_holding(port: int, address: int) -> int | None:
    """別の pymodbus client でスレーブの holding register を読み返す（write 検証用）。

    pymodbus のバージョン差（同期 client のキーワード引数名）を吸収して読む。失敗時は None。
    """
    try:
        from pymodbus.client import ModbusTcpClient
    except ImportError:
        return None
    client = ModbusTcpClient("127.0.0.1", port=port)
    try:
        if not client.connect():
            return None
        # pymodbus 3.x は read_holding_registers(address, count=..., slave=...) 系。
        # バージョン差で count/slave のキーワード名が異なるため複数を試す。
        rr = None
        for kwargs in (
            {"count": 1, "slave": 1},
            {"count": 1, "device_id": 1},
            {"count": 1},
        ):
            try:
                rr = client.read_holding_registers(address, **kwargs)
                break
            except TypeError:
                continue
        if rr is None or rr.isError() or not getattr(rr, "registers", None):
            return None
        return int(rr.registers[0])
    finally:
        client.close()


def _simulator_writes_slave(simulator_binary: str, sim_port: int, slave_port: int,
                            save_path: str) -> None:
    """Simulator を ``--open`` で起動し、commitValue → writeVariable → PLC 書込を観測する。"""
    with spix_app(simulator_binary, sim_port, extra_args=("--open", save_path)) as url:
        num_wrapper = f"{_SIM_WIN}/widget_num001"
        numeric = f"{num_wrapper}/hmiNumericField"
        call_method(url, "waitForItem", numeric, 3000)

        # 接続確立 → 初回 read（holding[2]=0）→ binding 追従で text が "0" になるのを待つ。
        # （接続が立つまで commitValue しても write は ConnectedState 待ちでスキップされるため、
        #  読みの追従で接続確立を確認してから書く。）
        deadline = time.monotonic() + 8.0
        while time.monotonic() < deadline:
            body = call_method(url, "getStringProperty", numeric, "text")
            if "<value>" in body:
                import re

                m = re.search(r"<value>(?:<string>)?(.*?)(?:</string>)?</value>", body, re.DOTALL)
                if m and m.group(1).strip() == "0":
                    break
            time.sleep(0.1)

        # 書き：入力テキストを設定し commitValue() で確定を模す。確定で writeBoundValue が
        # VariableStore.setValue + ModbusController.writeVariable を呼び、PLC へ書く。
        call_method(url, "setStringProperty", numeric, "text", _TYPED_VALUE)
        body = call_method(url, "invokeMethod", numeric, "commitValue", [])
        if "<fault>" in body:
            raise RuntimeError(f"commitValue invokeMethod fault. Body: {body[:500]!r}")

        # スレーブ側の holding[2] が入力値へ変わるのを Python から読み返して確認する。
        deadline = time.monotonic() + 8.0
        observed = None
        while time.monotonic() < deadline:
            observed = _read_slave_holding(slave_port, _HR_ADDRESS)
            if observed == int(_TYPED_VALUE):
                break
            time.sleep(0.1)
        if observed != int(_TYPED_VALUE):
            raise RuntimeError(
                f"slave holding[{_HR_ADDRESS}]={observed!r} != {int(_TYPED_VALUE)!r} "
                "(HMI commit did not write to PLC via ModbusController.writeVariable)"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator-binary", required=True)
    parser.add_argument("--simulator-port", type=int, default=9878)
    parser.add_argument("--slave-port", type=int, default=_SLAVE_PORT)
    args = parser.parse_args()

    # pymodbus 不在なら SKIP（緑を妨げない）。
    try:
        import pymodbus  # noqa: F401
    except ImportError:
        print("SKIP: pymodbus not installed", file=sys.stderr)
        return _SKIP_EXIT

    save_path = ""
    slave: subprocess.Popen | None = None
    try:
        fd, save_path = tempfile.mkstemp(prefix="hmi_mb4_fixture_", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(_fixture_json(args.slave_port), f, ensure_ascii=False, indent=2)

        try:
            slave = _start_slave(args.slave_port)
        except RuntimeError as exc:
            print(f"SKIP: {exc}", file=sys.stderr)
            return _SKIP_EXIT

        _simulator_writes_slave(
            args.simulator_binary, args.simulator_port, args.slave_port, save_path
        )
    except Exception as exc:  # noqa: BLE001
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    finally:
        if slave is not None:
            _stop_slave(slave)
        if save_path:
            try:
                os.unlink(save_path)
            except FileNotFoundError:
                pass

    print(
        f"OK: simulator commit writes NumericField value -> ModbusController.writeVariable -> "
        f"slave holding[{_HR_ADDRESS}] becomes {_TYPED_VALUE}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
