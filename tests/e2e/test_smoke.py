"""Phase 3-A Task 17: E2E smoke。

Editor を ``--e2e`` 付きで起動し、Spix XML-RPC エンドポイントが
``system.listMethods`` に応答することを確認する。Task 18 以降は同じ
ハーネスを土台にして mouseClick / drag / getProperty など本物の RPC
呼び出しを追加していく。

実装メモ：``xmlrpc.client.ServerProxy`` を使うのが筋だが、Python 3.14 系の
一部ビルド（Homebrew 経由など）で ``_pyexpat`` 拡張モジュールが macOS の
libexpat とシンボル不整合を起こし import 時点で落ちる。XML-RPC は本質的に
HTTP POST と XML body の組合せなので、smoke 1 件目は標準 ``urllib`` で
リクエストを送り、レスポンスに ``methodResponse`` 要素が含まれることを
文字列レベルで確認する。expat に依存しないため、ローカル / CI の Python
ビルドの差異に左右されない。
"""

from __future__ import annotations

import argparse
import sys
import urllib.error
import urllib.request

from harness import spix_app

_LIST_METHODS_REQUEST = (
    '<?xml version="1.0"?>'
    "<methodCall>"
    "<methodName>system.listMethods</methodName>"
    "<params></params>"
    "</methodCall>"
)


def _call_list_methods(url: str, timeout: float = 10.0) -> str:
    req = urllib.request.Request(
        url,
        data=_LIST_METHODS_REQUEST.encode("utf-8"),
        headers={"Content-Type": "text/xml"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read().decode("utf-8", errors="replace")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--editor-binary",
        required=True,
        help="Path to the hmi_editor executable",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=9876,
        help="Spix endpoint port (default 9876, matches Editor default)",
    )
    args = parser.parse_args()

    with spix_app(args.editor_binary, args.port) as url:
        try:
            body = _call_list_methods(url)
        except urllib.error.URLError as exc:
            print(f"FAIL: HTTP request to {url} failed: {exc}", file=sys.stderr)
            return 1

        if "<methodResponse>" not in body:
            print(
                "FAIL: Spix response missing <methodResponse> element. "
                f"Body head: {body[:200]!r}",
                file=sys.stderr,
            )
            return 1

        # Spix が標準で持つ system.listMethods は AnyRPC の introspection
        # を経由する。最低限「mouseClick」「getProperty」のどちらかが
        # メソッド一覧に出ていることまで確認する（Task 18 以降で使う API
        # が確実に登録されているという shake-out も兼ねる）。
        if "mouseClick" not in body and "getProperty" not in body:
            print(
                "FAIL: Spix method list missing both mouseClick and "
                f"getProperty. Body head: {body[:300]!r}",
                file=sys.stderr,
            )
            return 1

        print(f"OK: Spix responded with methodResponse ({len(body)} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
