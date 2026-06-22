#!/usr/bin/env python3
"""手動テスト用ソフト OPC-UA サーバ（asyncua / opcua-asyncio）。

`tests/e2e/opcua_server.py`（E2E 用・固定値 1 ノードの最小サーバ）とは別物で、こちらは
**人が hmi_simulator / hmi_runtime を手で動作確認するための「実サーバ代用」**。実 PLC が無くても
OP-3 相当（実サーバ読込追従）をローカルで何度でも試せるよう、**複数の型・値がライブで動くノード**と
**書込可ノード（OP-4 の書込確認用）**を持つ。セキュリティ None・匿名。

公開ノード（既定 `ns=2`）:

| NodeId                     | 型      | 動き                                   | 用途 |
|----------------------------|---------|----------------------------------------|------|
| `ns=2;s=Demo.Counter`      | Int32   | 周期ごとに +1                          | 読み（int） |
| `ns=2;s=Demo.Temperature`  | Double  | 25±5 の正弦波                          | 読み（real） |
| `ns=2;s=Demo.Running`      | Boolean | 周期ごとに反転                         | 読み（bool） |
| `ns=2;s=Demo.Setpoint`     | Double  | **書込可**（初期 50.0）。書いた値を保持 | 書き（OP-4） |

使い方::

    pip install asyncua            # 未導入なら（/usr/bin/python3 の venv 推奨。本リポの罠参照）
    python3 scripts/opcua/test_server.py                       # 127.0.0.1:4840（ローカル）
    python3 scripts/opcua/test_server.py --host 192.168.1.10   # LAN 上の別マシン/実機から繋ぐ場合は実IP
    python3 scripts/opcua/test_server.py --port 4841 --interval 0.25

起動すると endpoint と NodeId 一覧を表示するので、`Docs/samples/opcua-demo.json` の endpoint を
合わせて `hmi_simulator --open Docs/samples/opcua-demo.json` で追従を確認する。SIGTERM / SIGINT で停止。

注意:
- **endpoint のホスト名**：discovery でサーバが返す endpoint URL がクライアントから到達可能でないと
  繋がらない。同一マシンなら既定 `127.0.0.1` で良いが、別マシン/実機から繋ぐときは `--host <実IP>` を
  指定する（0.0.0.0 で待ち受けつつ報告 URL を実IPにする）。
- **値の型**：hmi_simulator 側の変数 `type`（int/real/bool）をノードの型に合わせる（coerce で寄せる）。
"""

from __future__ import annotations

import argparse
import asyncio
import math
import signal
import sys


async def _serve(host: str, port: int, expected_ns_index: int, interval: float) -> None:
    # 遅延 import：asyncua 不在環境では分かりやすいメッセージで終了する。
    try:
        from asyncua import Server, ua
    except ImportError:
        print(
            "asyncua がありません。`pip install asyncua` を実行してください "
            "(Homebrew python3.14 は pyexpat 破損のため /usr/bin/python3 の venv を推奨)。",
            file=sys.stderr,
        )
        raise SystemExit(1)

    server = Server()
    await server.init()
    # 0.0.0.0 で待ち受けつつ、discovery で返す endpoint URL は host（既定 127.0.0.1 / LAN は実IP）にする。
    server.set_endpoint(f"opc.tcp://{host}:{port}/hmi/demo/")
    if host not in ("127.0.0.1", "localhost"):
        # 別マシンから繋ぐとき、待ち受けは全 IF に広げる（報告 URL は上の host のまま）。
        try:
            server.socket_address = ("0.0.0.0", port)  # asyncua 1.x
            # 全 IF 公開 + security None / anonymous は LAN 上で無防備。誤運用防止に 1 回警告する。
            print(
                f"warning: listening on ALL interfaces (0.0.0.0:{port}) with security "
                "None / anonymous - use only on a trusted network.",
                file=sys.stderr,
            )
        except Exception as exc:  # noqa: BLE001
            print(
                f"warning: failed to set listen address (host={host}, port={port}): {exc}",
                file=sys.stderr,
            )

    # register_namespace() の戻り index が名前空間 index の正（既定構成では 2）。--expected-ns は
    # 検証専用で、ズレたら fixture を実 index に合わせるよう警告するだけ（index 自体は制御しない）。
    idx = await server.register_namespace("urn:hmi:demo")
    if idx != expected_ns_index:
        print(
            f"note: actual namespace index={idx} (expected {expected_ns_index}); "
            f"set fixture nodeId to ns={idx}.",
            file=sys.stderr,
        )

    objects = server.nodes.objects
    demo = await objects.add_object(ua.NodeId("Demo", idx), "Demo")
    counter = await demo.add_variable(
        ua.NodeId("Demo.Counter", idx), "Counter", ua.Variant(0, ua.VariantType.Int32)
    )
    temperature = await demo.add_variable(
        ua.NodeId("Demo.Temperature", idx), "Temperature",
        ua.Variant(25.0, ua.VariantType.Double),
    )
    running = await demo.add_variable(
        ua.NodeId("Demo.Running", idx), "Running", ua.Variant(False, ua.VariantType.Boolean)
    )
    setpoint = await demo.add_variable(
        ua.NodeId("Demo.Setpoint", idx), "Setpoint", ua.Variant(50.0, ua.VariantType.Double)
    )
    await setpoint.set_writable()  # OP-4（書込）確認用。

    print(f"OPC-UA test server: opc.tcp://{host}:{port}  (security None / anonymous)")
    print("  ns={0};s=Demo.Counter      Int32   (+1 / tick)".format(idx))
    print("  ns={0};s=Demo.Temperature  Double  (25±5 sine)".format(idx))
    print("  ns={0};s=Demo.Running      Boolean (toggles)".format(idx))
    print("  ns={0};s=Demo.Setpoint     Double  (writable; echoes written value)".format(idx))
    sys.stdout.flush()

    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:
            pass

    tick = 0
    async with server:
        while not stop.is_set():
            tick += 1
            await counter.write_value(ua.Variant(tick, ua.VariantType.Int32))
            await temperature.write_value(
                ua.Variant(25.0 + 5.0 * math.sin(tick / 10.0), ua.VariantType.Double)
            )
            await running.write_value(ua.Variant(bool(tick % 2), ua.VariantType.Boolean))
            try:
                await asyncio.wait_for(stop.wait(), timeout=interval)
            except asyncio.TimeoutError:
                pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--host", default="127.0.0.1",
                        help="discovery で返す endpoint ホスト（別マシンから繋ぐときは実IP）")
    parser.add_argument("--port", type=int, default=4840)
    parser.add_argument("--expected-ns", type=int, default=2,
                        help="期待する名前空間 index（検証専用・既定 2。ズレたら警告のみ）")
    parser.add_argument("--interval", type=float, default=0.5, help="値更新周期 [秒]")
    args = parser.parse_args()
    if not (1 <= args.port <= 65535):
        parser.error("--port は 1..65535 の範囲で指定してください")
    if args.interval <= 0:
        parser.error("--interval は 0 より大きい値を指定してください")
    try:
        asyncio.run(_serve(args.host, args.port, args.expected_ns, args.interval))
    except KeyboardInterrupt:
        pass
    except SystemExit as exc:
        return int(exc.code or 0)
    except Exception as exc:  # noqa: BLE001
        print(f"test_server error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
