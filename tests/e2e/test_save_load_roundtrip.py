"""Phase 3-A Task 19: JSON 保存 → 読込ループ E2E。

Editor を 2 回起動して以下を確認する。

フェーズ 1（編集セッション）：
1. Editor を ``--e2e`` で起動し、初期 ``widget_btn001`` の座標を変更
2. 「追加」ボタンを mouseClick → ``widget_btn002`` を出現させ、別座標へ移動
3. Window 直下の QML 関数 ``saveTo(path)`` を Spix の ``invokeMethod`` で呼び、
   一時 JSON ファイルへ書き出す
4. Editor を終了

フェーズ 2（再現セッション）：
5. 同じ JSON を ``--e2e --open <path>`` で別プロセスとして Editor を再起動
6. ``widget_btn001`` / ``widget_btn002`` が存在し、x / y がフェーズ 1 で保存した
   座標と一致していることを確認

Spix v0.14 制約・回避策（Task 18 で確立、CLAUDE.md「Spix（E2E）統合の罠」節）：

- FileDialog は AppleScript / Spix から自動操作できないため、本テストは
  ``saveDialog.onAccepted`` を直接実行する代わりに Main.qml に Task 19 で生やした
  ``saveTo(path)`` ラッパー関数を ``invokeMethod`` で呼ぶ。
- 「ドラッグして座標変更」は Spix の ``mouseBeginDrag`` / ``mouseEndDrag`` が
  自由座標を取れないため、Task 18 と同じく ``setStringProperty`` で代替する。
- XML-RPC レスポンスは expat を経由しない正規表現で抽出する（Homebrew Python
  3.14 の ``_pyexpat`` 不整合回避、CLAUDE.md 参照）。
"""

from __future__ import annotations

import argparse
import os
import re
import sys
import tempfile

from harness import call_method, spix_app

_WIN = "hmiEditorWindow"


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
    """Main.qml の Window.saveTo(path) を invokeMethod 経由で呼ぶ。
    Spix の invokeMethod は ``(path, method, any[] args)`` で、第 3 引数は
    array なので list を渡す（harness の _encode_value が array を生成する）。
    """
    body = call_method(url, "invokeMethod", _WIN, "saveTo", [save_path])
    if "<fault>" in body:
        raise RuntimeError(f"invokeMethod returned fault. Body: {body[:500]!r}")
    # saveTo の戻り値（bool）。AnyRPC は <value><boolean>1</boolean></value>。
    return "<boolean>1</boolean>" in body


def _phase1_edit_and_save(editor_binary: str, port: int, save_path: str) -> dict:
    """フェーズ 1：座標を変更して JSON に保存し、期待座標を返す。

    実行順の注意：
    Canvas.qml の ``addWidget()`` は ``widgetModel = widgetModel.concat(...)``
    で配列を入れ替えるため、Repeater が delegate を再生成し、既存 widget の
    ``x: modelData.x`` バインディングも再評価される。先に btn001 の座標を
    setStringProperty で動かしてから「追加」を押すと、再生成によって btn001 の
    座標が初期値（100, 50）に戻ってしまう。順序は「追加 → まとめて座標変更」
    に固定する。
    """
    expected: dict[str, tuple[int, int]] = {}
    with spix_app(editor_binary, port) as url:
        # 初期 btn001 の出現確認
        call_method(url, "waitForItem", f"{_WIN}/widget_btn001", 2000)
        if not _exists_and_visible(url, f"{_WIN}/widget_btn001"):
            raise RuntimeError("initial widget_btn001 missing")

        # 追加ボタンで btn002 を出現させる（先に Repeater を最終形にする）
        call_method(url, "mouseClick", f"{_WIN}/addWidgetButton")
        call_method(url, "waitForItem", f"{_WIN}/widget_btn002", 2000)
        if not _exists_and_visible(url, f"{_WIN}/widget_btn002"):
            raise RuntimeError("widget_btn002 did not appear after Add click")

        # 全 widget が出揃ってから座標変更（Repeater 再生成で座標が巻き戻る
        # のを避けるための順序固定）
        new_btn001 = (300, 150)
        new_btn002 = (400, 250)
        _set_pos(url, f"{_WIN}/widget_btn001", *new_btn001)
        _set_pos(url, f"{_WIN}/widget_btn002", *new_btn002)

        # binding 反映待ち（Task 18 と同等の保険）
        call_method(url, "wait", 100)

        # ファイル保存
        if not _invoke_save_to(url, save_path):
            # 反映確認 / 失敗詳細を errors から取得
            err = call_method(url, "getErrors")
            raise RuntimeError(
                f"saveTo returned false for {save_path!r}. Errors: {err[:500]!r}"
            )

        expected["btn001"] = new_btn001
        expected["btn002"] = new_btn002

    # コンテキスト終了で Editor が terminate される。ファイルが残っていることを確認。
    if not os.path.isfile(save_path):
        raise RuntimeError(f"saved JSON not found: {save_path}")
    return expected


def _phase2_reopen_and_verify(
    editor_binary: str, port: int, save_path: str, expected: dict
) -> None:
    """フェーズ 2：別プロセスで `--open` 起動し、widgets が再現されることを確認。"""
    with spix_app(editor_binary, port, extra_args=("--open", save_path)) as url:
        # 起動時自動ロード → Repeater 再構築の完了待ち
        for widget_id in expected:
            path = f"{_WIN}/widget_{widget_id}"
            call_method(url, "waitForItem", path, 3000)
            if not _exists_and_visible(url, path):
                raise RuntimeError(
                    f"reopened editor missing widget {widget_id}. "
                    f"JSON: {save_path}"
                )
            x_after = _get_int_property(url, path, "x")
            y_after = _get_int_property(url, path, "y")
            ex_x, ex_y = expected[widget_id]
            if (x_after, y_after) != (ex_x, ex_y):
                raise RuntimeError(
                    f"widget {widget_id} position mismatch after reopen. "
                    f"expected=({ex_x},{ex_y}) actual=({x_after},{y_after})"
                )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor-binary", required=True)
    parser.add_argument("--port", type=int, default=9876)
    args = parser.parse_args()

    # Editor を 2 回起動するため、JSON は tempfile で確保し最後にクリーンアップする
    # （NamedTemporaryFile を使わないのは Windows で open 中 unlink が拒否される
    #  ためだが、本テストは POSIX 限定 (HMI_ENABLE_E2E=OFF on MinGW) なので
    #  単純な mkstemp + os.unlink で十分かつ可搬性も問題ない）。
    fd, save_path = tempfile.mkstemp(prefix="hmi_task19_", suffix=".json")
    os.close(fd)
    # mkstemp は空ファイルを残すため、saveTo が新規作成扱いになるよう一旦削除
    try:
        os.unlink(save_path)
    except FileNotFoundError:
        pass

    try:
        expected = _phase1_edit_and_save(args.editor_binary, args.port, save_path)
        _phase2_reopen_and_verify(
            args.editor_binary, args.port, save_path, expected
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
        "OK: save -> reopen roundtrip preserved widgets "
        + ", ".join(
            f"{k}=({v[0]},{v[1]})" for k, v in expected.items()
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
