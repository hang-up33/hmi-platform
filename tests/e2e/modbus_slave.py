"""Phase 7 / MB-2 E2E 用：pymodbus ソフト Modbus TCP スレーブ。

``test_modbus_read.py`` から **サブプロセス**として起動する独立スクリプト。
holding register に固定値を載せた最小スレーブを ``127.0.0.1:<port>`` で listen する。
``ModbusController``（Simulator）がこれを周期ポーリングして変数ストア → binding 経路で
UI へ流す。実 PLC は CI / Web から不達なため、自動検証はこのソフトスレーブで固定する
（Docs/phase7-modbus-plan.md「Simulator の自動検証相手」）。

使い方::

    python3 modbus_slave.py --port 15020 --hr-address 3 --hr-value 1234

pymodbus 3.13 の SimData / SimDevice API を使う（旧 ModbusSlaveContext /
ModbusSequentialDataBlock は 3.13 で deprecated かつ setValues が機能しないため）。
非特権ポート（502 は root 権限が要るので使わない）で起動する。SIGTERM / SIGINT で停止。
"""

from __future__ import annotations

import argparse
import asyncio
import signal
import sys


async def _serve(port: int, hr_address: int, hr_value: int) -> None:
    # 遅延 import：pymodbus 不在環境ではテスト側が importorskip 相当でスキップする
    # （本スクリプトは _wait_for_port が失敗 → テストが明示スキップ/失敗を判断）。
    from pymodbus.server import ModbusTcpServer
    from pymodbus.simulator import DataType, SimData, SimDevice

    # holding register を 0..hr_address に確保し、対象アドレスに固定値を載せる。
    count = hr_address + 1
    values = [0] * count
    values[hr_address] = hr_value
    hr = SimData(0, values=values, datatype=DataType.REGISTERS)
    device = SimDevice(1, simdata=[hr])

    server = ModbusTcpServer(context=device, address=("127.0.0.1", port))

    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:
            pass  # 一部プラットフォームは未対応

    serve_task = asyncio.create_task(server.serve_forever())
    await stop.wait()
    await server.shutdown()
    serve_task.cancel()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=15020)
    parser.add_argument("--hr-address", type=int, default=3)
    parser.add_argument("--hr-value", type=int, default=1234)
    args = parser.parse_args()
    try:
        asyncio.run(_serve(args.port, args.hr_address, args.hr_value))
    except KeyboardInterrupt:
        pass
    except Exception as exc:  # noqa: BLE001
        print(f"modbus_slave error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
