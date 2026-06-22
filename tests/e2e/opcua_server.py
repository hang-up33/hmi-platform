"""Phase 9 / OP-2 E2E 用：asyncua ソフト OPC-UA サーバ。

``test_opcua_read.py`` から **サブプロセス**として起動する独立スクリプト。
``ns=2;s=<ident>`` のスカラ値ノードに固定値を載せた最小サーバを
``opc.tcp://127.0.0.1:<port>`` で listen する（セキュリティ None・匿名）。
``OpcUaController``（Simulator）がこれを購読（MonitoredItem）して変数ストア →
binding 経路で UI へ流す。実 OPC-UA サーバ / PLC は CI / Web から不達なため、
自動検証はこのソフトサーバで固定する（Modbus の pymodbus ソフトスレーブに相当）。

Qt OPC-UA（open62541 client backend）はサーバ機能を持たないため、サーバ側は
Python の ``asyncua``（opcua-asyncio）で立てる（C++ ユニットテストでは実購読を
回せないので、購読 round-trip はこの E2E が担う）。

使い方::

    python3 opcua_server.py --port 14840 --ident Temp --value 1234

``--ns`` は名前空間 index（既定 2＝register_namespace 後の最初のユーザ ns）。
SIGTERM / SIGINT で停止する。
"""

from __future__ import annotations

import argparse
import asyncio
import signal
import sys


async def _serve(port: int, ns_index: int, ident: str, value: int) -> None:
    # 遅延 import：asyncua 不在環境ではテスト側が SKIP（exit 77）を返す。
    from asyncua import Server, ua

    server = Server()
    await server.init()
    # セキュリティ None・匿名を許可（既定）。エンドポイントは 127.0.0.1 で報告させる
    # （OPC-UA は discovery でサーバが自分のエンドポイント URL を返すため、ホスト名置換で
    # クライアントが到達不能 URL を掴む罠を避ける）。
    server.set_endpoint(f"opc.tcp://127.0.0.1:{port}/hmi/e2e/")

    idx = await server.register_namespace("urn:hmi:e2e")
    if idx != ns_index:
        # register_namespace() の戻り index は asyncua のバージョン/構成で必ず 2 とは限らない。
        # fixture の nodeId は ns=2;s=Temp で固定なので、index がずれるとノードが一致せず購読が
        # 黙って届かない（紛らわしい timeout FAIL になる）。ここで即 fail させてサーバ起動を失敗に
        # し、テスト側を SKIP（_start_server の listen 待ちが落ちる）へ落とす（CodeRabbit PR #143）。
        raise RuntimeError(
            f"opcua_server: namespace index mismatch (actual={idx}, expected={ns_index})"
        )

    objects = server.nodes.objects
    # ns=<idx>;s=<ident> の Int32 ノードを固定値で公開する。MonitoredItem 購読作成時に
    # open62541 クライアントが初期値を読むため、固定値でも変化通知（初回）として届く。
    await objects.add_variable(
        ua.NodeId(ident, idx),
        ident,
        ua.Variant(value, ua.VariantType.Int32),
    )

    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    for sig in (signal.SIGTERM, signal.SIGINT):
        try:
            loop.add_signal_handler(sig, stop.set)
        except NotImplementedError:
            pass  # 一部プラットフォームは未対応

    async with server:
        await stop.wait()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, default=14840)
    parser.add_argument("--ns", type=int, default=2)
    parser.add_argument("--ident", default="Temp")
    parser.add_argument("--value", type=int, default=1234)
    args = parser.parse_args()
    try:
        asyncio.run(_serve(args.port, args.ns, args.ident, args.value))
    except KeyboardInterrupt:
        pass
    except Exception as exc:  # noqa: BLE001
        print(f"opcua_server error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
