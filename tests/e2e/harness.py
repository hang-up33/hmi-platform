"""Phase 3-A E2E 共通ハーネス：Editor / Simulator を `--e2e` で起動し、
Spix XML-RPC エンドポイントの URL を返す。

設計指針（Docs/phase3-e2e-plan.md）：
- Python 標準ライブラリのみで動く（pytest 等の追加依存を避ける）。
- 起動時は ``QT_QPA_PLATFORM=offscreen`` をデフォルトに設定し、CI / オフ
  スクリーンランナーでも動かす。
- Spix RPC は XML-RPC over HTTP（AnyRPC）。Task 17 では smoke として URL を
  返すだけにとどめ、リクエスト送信は呼び出し側で選択する（``xmlrpc.client`` /
  ``urllib`` どちらでも使える形に保つ）。
"""

from __future__ import annotations

import os
import socket
import subprocess
import time
import urllib.request
from contextlib import contextmanager
from typing import Iterator, Sequence
from xml.sax.saxutils import escape as _xml_escape


def _wait_for_port(host: str, port: int, timeout: float = 15.0) -> bool:
    """TCP ポートが connect 可能になるまで待つ。"""
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            with socket.create_connection((host, port), timeout=0.5):
                return True
        except OSError:
            time.sleep(0.2)
    return False


@contextmanager
def spix_app(
    binary: str,
    port: int,
    extra_args: Sequence[str] = (),
    startup_timeout: float = 15.0,
) -> Iterator[str]:
    """``--e2e --e2e-port <port>`` でアプリを起動し、Spix エンドポイントの
    URL を yield する。終了時に subprocess を terminate し、5 秒で抜けない
    場合は kill する。
    """
    if not os.path.isfile(binary):
        raise FileNotFoundError(
            f"App binary not found: {binary} "
            "(run `cmake --build build` first)"
        )

    env = os.environ.copy()
    env.setdefault("QT_QPA_PLATFORM", "offscreen")

    cmd = [binary, "--e2e", "--e2e-port", str(port), *extra_args]
    proc = subprocess.Popen(cmd, env=env)
    try:
        if not _wait_for_port("127.0.0.1", port, timeout=startup_timeout):
            raise RuntimeError(
                f"Spix endpoint on port {port} did not become ready "
                f"within {startup_timeout}s"
            )
        yield f"http://127.0.0.1:{port}/"
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
            proc.wait(timeout=2)


def _encode_value(value) -> str:
    """単一の XML-RPC <value> 要素をエンコードする（params / array 共通）。"""
    if isinstance(value, bool):
        return f"<value><boolean>{1 if value else 0}</boolean></value>"
    if isinstance(value, int):
        return f"<value><int>{value}</int></value>"
    if isinstance(value, float):
        return f"<value><double>{value!r}</double></value>"
    if isinstance(value, str):
        return f"<value><string>{_xml_escape(value)}</string></value>"
    if isinstance(value, (list, tuple)):
        inner = "".join(_encode_value(v) for v in value)
        # AnyRPC は <array><data>...</data></array> 形式を要求する。空配列も
        # data タグは残す必要がある。
        return f"<value><array><data>{inner}</data></array></value>"
    raise TypeError(
        f"Unsupported XML-RPC value type: {type(value).__name__}"
    )


def _encode_param(value) -> str:
    """単純な XML-RPC 引数を <param>...</param> 文字列にエンコードする。
    invokeMethod の第 3 引数のように array が必要な場合は list / tuple を渡す。
    """
    return f"<param>{_encode_value(value)}</param>"


def call_method(url: str, method: str, *params, timeout: float = 10.0) -> str:
    """Spix の XML-RPC メソッドを呼び、レスポンス XML 文字列を返す。

    ``xmlrpc.client`` を使わず ``urllib.request`` で生 XML-RPC を投げる
    ことで Homebrew Python 3.14 の ``_pyexpat`` 不整合を回避する
    （詳細は CLAUDE.md「Spix（E2E）統合の罠」節）。
    引数は ``bool``/``int``/``float``/``str`` のみサポート。複雑な型を
    扱いたくなったら ``xmlrpc.client`` の利用と引き換えに検討する。
    """
    payload = (
        '<?xml version="1.0"?>'
        '<methodCall>'
        f'<methodName>{_xml_escape(method)}</methodName>'
        f'<params>{"".join(_encode_param(p) for p in params)}</params>'
        '</methodCall>'
    ).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "text/xml"},
    )
    with urllib.request.urlopen(req, timeout=timeout) as response:
        return response.read().decode("utf-8", errors="replace")
