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
from contextlib import contextmanager
from typing import Iterator, Sequence


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
