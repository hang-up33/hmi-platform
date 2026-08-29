"""Phase 3-A Task 18: Editor 配置 + 座標反映 E2E。

Editor を ``--e2e`` で起動し、Spix RPC 経由で以下を確認する。

1. 初期状態で ``widget_btn001`` が存在する（既存の MVP 初期値）
2. 「追加」ボタン (``addWidgetButton``) を mouseClick すると ``widget_btn002`` が
   出現する（``mouseClick`` で Editor の onClicked ハンドラが発火する）
3. ``widget_btn002`` の初期座標を ``getStringProperty`` で取得
4. ``setStringProperty`` で x/y を別座標に書き換える
5. ``getStringProperty`` で新座標が反映されていることを確認

なぜ「ドラッグ」ではなく ``setStringProperty`` か：
Spix v0.14 の ``mouseBeginDrag(path)`` / ``mouseEndDrag(path)`` は
**item の中央間** に絞った drag&drop モデルで自由座標を取れない。さらに
Qt 6.11 + ``-platform offscreen`` 環境では ``QGuiApplication::postEvent``
による中間 ``mouseMove`` が drag 閾値判定にうまく届かず、検証時に widget
が動かないことを確認した。Task 18 の本質「E2E から QML プロパティを
変更 → 反映パスが通る」は ``setStringProperty`` で十分担保できる。本物の
マウスドラッグの動作確認は Phase 3-B（実機 / Yocto）の手動テストか、
Spix の Qt 6 サポートが改善した段階で改めて追加する想定（[Docs/archive/phase3-e2e-plan.md] 参照）。

Spix v0.14 の RPC：``getProperty`` は存在せず ``getStringProperty`` のみ
（数値プロパティでも文字列として返る）。XML-RPC レスポンスは expat に
依存しない正規表現で抽出する（test_smoke.py と同じ理由）。
"""

from __future__ import annotations

import argparse
import re
import sys

from harness import call_method, spix_app

_WIN = "hmiEditorWindow"


def _get_int_property(url: str, path: str, prop: str) -> int:
    body = call_method(url, "getStringProperty", path, prop)
    # XML-RPC では「型タグなしの value」は string とみなされる。AnyRPC は
    # `<value>50</value>` と `<value><string>50</string></value>` の両方を
    # 返す可能性があるため両対応で抽出する。
    m = re.search(
        r"<value>(?:<string>)?\s*(-?\d+(?:\.\d+)?)\s*(?:</string>)?</value>",
        body,
    )
    if not m:
        raise RuntimeError(
            f"Failed to extract {prop} from {path}. Response head: {body[:300]!r}"
        )
    # QML の x/y は real（double）。整数化して比較する。
    return int(float(m.group(1)))


def _exists_and_visible(url: str, path: str) -> bool:
    body = call_method(url, "existsAndVisible", path)
    # AnyRPC の boolean は <boolean>0</boolean> / <boolean>1</boolean>
    return "<boolean>1</boolean>" in body


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor-binary", required=True)
    parser.add_argument("--port", type=int, default=9876)
    args = parser.parse_args()

    with spix_app(args.editor_binary, args.port) as url:
        # 1. 初期 Widget が見えること
        call_method(url, "waitForItem", f"{_WIN}/widget_btn001", 2000)
        if not _exists_and_visible(url, f"{_WIN}/widget_btn001"):
            print("FAIL: initial widget_btn001 is not visible", file=sys.stderr)
            return 1

        # 2. 追加ボタンを 1 回押す → btn002 が出現するはず
        call_method(url, "mouseClick", f"{_WIN}/addWidgetButton")
        # 追加後の Repeater 再生成を待つ。Spix の waitForItem は
        # `(path, millisecondsToWait)` の 2 引数必須（ms を省略すると
        # AnyRPC が引数不足エラーで即 false を返す）。
        call_method(url, "waitForItem", f"{_WIN}/widget_btn002", 2000)
        if not _exists_and_visible(url, f"{_WIN}/widget_btn002"):
            print("FAIL: widget_btn002 did not appear after Add click", file=sys.stderr)
            return 1

        # 3. 初期座標を記録（Canvas.addWidget の既定は x=50, y=200）
        x_before = _get_int_property(url, f"{_WIN}/widget_btn002", "x")
        y_before = _get_int_property(url, f"{_WIN}/widget_btn002", "y")

        # 4. setStringProperty で別座標へ移動。drop 先座標を選びやすい
        #    値（既定 (50, 200) → (250, 320)）。文字列で渡すと AnyRPC が
        #    QML の real プロパティに変換する。
        new_x = x_before + 200
        new_y = y_before + 120
        call_method(url, "setStringProperty",
                    f"{_WIN}/widget_btn002", "x", str(new_x))
        call_method(url, "setStringProperty",
                    f"{_WIN}/widget_btn002", "y", str(new_y))
        # binding 反映を確実にするため軽く待つ
        call_method(url, "wait", 100)

        # 5. 新座標が反映されていることを確認
        x_after = _get_int_property(url, f"{_WIN}/widget_btn002", "x")
        y_after = _get_int_property(url, f"{_WIN}/widget_btn002", "y")
        if x_after != new_x or y_after != new_y:
            print(
                "FAIL: setStringProperty did not update x/y. "
                f"before=({x_before},{y_before}) "
                f"requested=({new_x},{new_y}) "
                f"after=({x_after},{y_after})",
                file=sys.stderr,
            )
            return 1

        print(
            f"OK: widget_btn002 moved ({x_before},{y_before}) -> "
            f"({x_after},{y_after}) via setStringProperty"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
