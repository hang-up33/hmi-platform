"""Phase 7 / MB-2: Modbus TCP 読込ポーリングの cross-app E2E。

``ModbusController``（Simulator 共有ソース＝Runtime も継承）が **Modbus TCP マスタ**として
PLC レジスタを周期ポーリングし、既存の変数ストア + binding 経路へ流すことを検証する。
実 PLC は CI / Web から不達なので、自動検証は **pymodbus ソフトスレーブ**相手に行う
（``modbus_slave.py`` をサブプロセスで起動）。

シナリオ：

1. **ソフトスレーブ起動**：``modbus_slave.py`` を ``127.0.0.1:<port>`` で起動し、holding
   register addr 3 に固定値 ``1234`` を載せる。``127.0.0.1:<port>`` が listen するまで待つ。
2. **fixture JSON**：``connections[]`` にそのスレーブ（host/port/unitId）、``tankLevel``（int）変数に
   ``source={connection,reg:"holding",address:3,poll}`` を付け、その変数を ``text`` binding で読む
   観測用 Label（``echo001``）を持つプロジェクトを書く。
3. **Simulator 段（本 E2E の主眼）**：fixture を Simulator に ``--open`` で読ませると、
   ``Main.qml`` が ``modbusController.configure`` を呼んでポーリングを開始し、read 結果が
   ``variableUpdated`` → ``VariableStore.setValue("tankLevel", 1234)`` → ``text`` binding 追従で
   ``echo001`` Label に反映される。Label text が ``"1234"`` になるのを ``getStringProperty`` で観測する。

これまでの E2E（binding 追従はローカル変数 / アクション由来）と異なり、**外部デバイス（Modbus
スレーブ）からの読込値**が UI へ流れる初の E2E。Spix v0.14 制約・回避策は既存 E2E と同方針。
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
_SLAVE_PORT = 15020
_HR_ADDRESS = 3
_HR_VALUE = 1234
_VAR_NAME = "tankLevel"
_POLL_MS = 100

# ctest が SKIP として扱う終了コード（CMakeLists の SKIP_RETURN_CODE と一致させる）。
_SKIP_EXIT = 77


def _fixture_json(port: int) -> dict:
    """connection + source 付き変数 + 観測用 Label（text binding）を持つプロジェクト。"""
    return {
        "project": "MB-2 Modbus read E2E",
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


def _start_slave(port: int) -> subprocess.Popen:
    """modbus_slave.py をサブプロセスで起動し、listen するまで待つ。"""
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
            str(_HR_VALUE),
        ]
    )
    if not _wait_for_port("127.0.0.1", port, timeout=10.0):
        # 起動失敗時もちゃんと reap する（terminate だけだとゾンビが残り E2E 再試行で蓄積。
        # CodeRabbit PR #121）。_stop_slave と同じ wait→kill フォールバックを使う。
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


def _simulator_reads_slave(simulator_binary: str, port: int, save_path: str) -> None:
    """Simulator を ``--open`` で起動し、Modbus 読込値が Label へ追従するのを観測する。"""
    with spix_app(simulator_binary, port, extra_args=("--open", save_path)) as url:
        echo = f"{_SIM_WIN}/widget_echo001/hmiLabel"
        call_method(url, "waitForItem", echo, 3000)

        # ポーリング（poll=100ms）+ 接続確立 + 非同期 read finished を経て Label text が
        # スレーブの holding register 値 "1234" へ追従する。短いポーリングで待つ。
        deadline = time.monotonic() + 8.0
        text = ""
        while time.monotonic() < deadline:
            text = _get_str_property(url, echo, "text")
            if text == str(_HR_VALUE):
                break
            time.sleep(0.1)
        if text != str(_HR_VALUE):
            raise RuntimeError(
                f"echo Label text={text!r} != {str(_HR_VALUE)!r} "
                "(Modbus read did not flow to variable/binding)"
            )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--simulator-binary", required=True)
    parser.add_argument("--simulator-port", type=int, default=9877)
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
        fd, save_path = tempfile.mkstemp(prefix="hmi_mb2_fixture_", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(_fixture_json(args.slave_port), f, ensure_ascii=False, indent=2)

        try:
            slave = _start_slave(args.slave_port)
        except RuntimeError as exc:
            print(f"SKIP: {exc}", file=sys.stderr)
            return _SKIP_EXIT

        _simulator_reads_slave(args.simulator_binary, args.simulator_port, save_path)
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
        f"OK: simulator polls Modbus slave (holding[{_HR_ADDRESS}]={_HR_VALUE}) -> "
        f"variable {_VAR_NAME} -> Label text follows to {_HR_VALUE!r}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
