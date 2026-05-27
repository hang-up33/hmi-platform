"""Phase 3-A Task 20: Simulator 表示 E2E。

Editor → Simulator の cross-app 連携を end-to-end で検証する：

フェーズ 1（Editor で JSON を作る）：
1. Editor を ``--e2e`` で起動し、初期 ``widget_btn001`` の座標を確認
2. 「追加」ボタンを mouseClick → ``widget_btn002`` を出現させる
3. それぞれの widget を ``setStringProperty`` で別座標へ移動
4. ``saveTo(path)`` を ``invokeMethod`` で呼んで一時 JSON ファイルへ書き出す
5. Editor を終了

フェーズ 2（Simulator で読込・表示を検証）：
6. 同じ JSON を ``--e2e --open <path>`` で Simulator として起動
7. ``widget_btn001`` / ``widget_btn002`` が描画されている
   （``existsAndVisible``）ことを確認
8. それぞれの x / y がフェーズ 1 で保存した座標と一致することを確認

Task 19 の test_save_load_roundtrip.py との違い：
- フェーズ 2 の起動先が **Editor → Simulator** に切り替わる
- 検証は読み取り専用（Simulator は編集機能を持たない）
- ポートは Editor=9876 / Simulator=9877 に分けて同時起動衝突を避ける
  （main.cpp 既定値・[Docs/phase3-e2e-plan.md] と整合）

Spix v0.14 制約・回避策（CLAUDE.md「Spix（E2E）統合の罠」節）：
- ``invokeMethod`` の第 3 引数は array：list で渡す（``_encode_value``）。
- ``getStringProperty`` のレスポンスは型タグ無し ``<value>...</value>`` も
  ありうるため、正規表現は両対応で書く（Task 19 と同じ）。
- ``waitForItem`` は 2 引数（path, ms）必須。
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile

from harness import call_method, spix_app

_EDITOR_WIN = "hmiEditorWindow"
_SIM_WIN = "hmiSimulatorWindow"


def _get_int_property(url: str, path: str, prop: str) -> int:
    body = call_method(url, "getStringProperty", path, prop)
    m = re.search(
        r"<value>(?:<string>)?\s*(-?\d+(?:\.\d+)?)\s*(?:</string>)?</value>",
        body,
    )
    if not m:
        raise RuntimeError(
            f"Failed to extract {prop} from {path}. Response head: {body[:300]!r}"
        )
    return int(float(m.group(1)))


def _exists_and_visible(url: str, path: str) -> bool:
    body = call_method(url, "existsAndVisible", path)
    return "<boolean>1</boolean>" in body


def _set_pos(url: str, item_path: str, x: int, y: int) -> None:
    call_method(url, "setStringProperty", item_path, "x", str(x))
    call_method(url, "setStringProperty", item_path, "y", str(y))


def _invoke_save_to(url: str, save_path: str) -> bool:
    """Editor Main.qml の Window.saveTo(path) を invokeMethod で呼ぶ。"""
    body = call_method(url, "invokeMethod", _EDITOR_WIN, "saveTo", [save_path])
    if "<fault>" in body:
        raise RuntimeError(f"invokeMethod returned fault. Body: {body[:500]!r}")
    return "<boolean>1</boolean>" in body


def _phase1_editor_save(editor_binary: str, port: int, save_path: str) -> dict:
    """Editor で JSON を編集 → 保存し、期待座標を返す。

    Repeater 再生成で座標が巻き戻る罠を避けるため、Task 19 と同じく
    「Repeater のサイズ変更（追加クリック） → まとめて座標変更」の順序を固定する
    （CLAUDE.md「Spix（E2E）統合の罠」節）。
    """
    expected: dict[str, tuple[int, int]] = {}
    with spix_app(editor_binary, port) as url:
        call_method(url, "waitForItem", f"{_EDITOR_WIN}/widget_btn001", 2000)
        if not _exists_and_visible(url, f"{_EDITOR_WIN}/widget_btn001"):
            raise RuntimeError("initial widget_btn001 missing in Editor")

        call_method(url, "mouseClick", f"{_EDITOR_WIN}/addWidgetButton")
        call_method(url, "waitForItem", f"{_EDITOR_WIN}/widget_btn002", 2000)
        if not _exists_and_visible(url, f"{_EDITOR_WIN}/widget_btn002"):
            raise RuntimeError("widget_btn002 did not appear after Add click")

        new_btn001 = (320, 140)
        new_btn002 = (420, 260)
        _set_pos(url, f"{_EDITOR_WIN}/widget_btn001", *new_btn001)
        _set_pos(url, f"{_EDITOR_WIN}/widget_btn002", *new_btn002)

        # binding 反映待ち（Task 18/19 と同等の保険）
        call_method(url, "wait", 100)

        if not _invoke_save_to(url, save_path):
            err = call_method(url, "getErrors")
            raise RuntimeError(
                f"saveTo returned false for {save_path!r}. Errors: {err[:500]!r}"
            )

        expected["btn001"] = new_btn001
        expected["btn002"] = new_btn002

    if not os.path.isfile(save_path):
        raise RuntimeError(f"saved JSON not found: {save_path}")
    return expected


def _phase2_simulator_display(
    simulator_binary: str, port: int, save_path: str, expected: dict
) -> None:
    """Simulator を `--open <path>` で起動し、widget が描画されることを確認。"""
    with spix_app(simulator_binary, port, extra_args=("--open", save_path)) as url:
        for widget_id, (ex_x, ex_y) in expected.items():
            path = f"{_SIM_WIN}/widget_{widget_id}"
            call_method(url, "waitForItem", path, 3000)
            if not _exists_and_visible(url, path):
                raise RuntimeError(
                    f"simulator missing widget {widget_id}. JSON: {save_path}"
                )
            x_after = _get_int_property(url, path, "x")
            y_after = _get_int_property(url, path, "y")
            if (x_after, y_after) != (ex_x, ex_y):
                raise RuntimeError(
                    f"simulator widget {widget_id} position mismatch. "
                    f"expected=({ex_x},{ex_y}) actual=({x_after},{y_after})"
                )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor-binary", required=True)
    parser.add_argument("--simulator-binary", required=True)
    parser.add_argument("--editor-port", type=int, default=9876)
    parser.add_argument("--simulator-port", type=int, default=9877)
    args = parser.parse_args()

    fd, save_path = tempfile.mkstemp(prefix="hmi_task20_", suffix=".json")
    os.close(fd)
    # mkstemp は空ファイルを残すため saveTo が新規作成扱いになるよう一旦削除
    try:
        os.unlink(save_path)
    except FileNotFoundError:
        pass

    try:
        expected = _phase1_editor_save(
            args.editor_binary, args.editor_port, save_path
        )
        _phase2_simulator_display(
            args.simulator_binary, args.simulator_port, save_path, expected
        )
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    finally:
        try:
            os.unlink(save_path)
        except FileNotFoundError:
            pass

    print(
        "OK: simulator displayed widgets from editor-saved JSON: "
        + ", ".join(
            f"{k}=({v[0]},{v[1]})" for k, v in expected.items()
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
