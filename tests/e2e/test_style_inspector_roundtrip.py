"""Phase 4 Task 30: スタイル編集 → 保存 → Simulator 描画の cross-app E2E。

Editor で btn001 を **選択** し、スタイル（text / backgroundColor / textColor）を
編集 → ``saveTo`` で JSON 保存 → 保存 JSON にスタイルが乗っていることを Python で
直接検証 → 同 JSON を Simulator に ``--open`` で読み込ませ、HmiButton にスタイルが
反映されて描画されることを ``getStringProperty`` で確認する。

Task 29 で入れた「選択 + インスペクタのスタイル編集」を end-to-end で固定する位置づけ
（Task 19/20 の座標 round-trip のスタイル版）。

Spix v0.14 制約・回避策（CLAUDE.md / [Docs/phase3-e2e-plan.md]・既存 E2E と同方針）：

- **インスペクタの TextField は ``onTextEdited``（ユーザー入力でのみ発火）で live Item
  へ書き戻す**ため、Spix の ``setStringProperty`` でフィールドの ``text`` を変えても
  発火しない。よって Task 18〜20 と同じく、選択中 EditableWidget（``widget_btn001``）の
  メタ（``widgetText`` / ``widgetBackgroundColor`` / ``widgetTextColor``）へ
  ``setStringProperty`` で直接書き込む（インスペクタが書き戻す先と同一の値経路）。
- 選択は ``widget_btn001`` を ``mouseClick`` して行う（HmiButton の ``clicked`` 中継で
  ``selectedWidgetId`` が更新される＝アプリ実動作と同じ経路）。
- Simulator 側は HmiButton に ``objectName: "hmiButton"`` を付与してあり、
  ``hmiSimulatorWindow/widget_btn001/hmiButton`` の ``backgroundColor`` / ``text`` を
  ``getStringProperty`` で読む。
- スタイル値の真偽は **保存 JSON を Python で直接 assert** することでも担保する
  （Spix のプロパティ読みに依存しない authoritative なチェック）。
- レスポンスは expat を経由しない正規表現で抽出する（Homebrew Python の ``_pyexpat``
  不整合回避、CLAUDE.md 参照）。

実行環境：E2E は macOS / Linux（``HMI_ENABLE_E2E=ON``）でのみ動く。Windows MinGW は
``HMI_ENABLE_E2E=OFF`` のため ctest から除外される（CMakeLists.txt 参照）。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile

from harness import call_method, spix_app

_EDITOR_WIN = "hmiEditorWindow"
_SIM_WIN = "hmiSimulatorWindow"

# Editor で btn001 に与えるスタイル（Simulator まで届くことを検証する）。
_NEW_TEXT = "RUN"
_NEW_BG = "#e63946"
_NEW_FG = "#ffffff"


def _get_str_property(url: str, path: str, prop: str) -> str:
    """getStringProperty のレスポンスから文字列値を取り出す。

    AnyRPC は型タグ有り ``<value><string>X</string></value>`` / 無し
    ``<value>X</value>`` の双方がありうるため両対応で抽出する（既存
    ``_get_int_property`` と同方針）。
    """
    body = call_method(url, "getStringProperty", path, prop)
    m = re.search(r"<value>(?:<string>)?(.*?)(?:</string>)?</value>", body, re.DOTALL)
    if not m:
        raise RuntimeError(
            f"Failed to extract {prop} from {path}. Response head: {body[:300]!r}"
        )
    return m.group(1).strip()


def _exists_and_visible(url: str, path: str) -> bool:
    body = call_method(url, "existsAndVisible", path)
    return "<boolean>1</boolean>" in body


def _invoke_save_to(url: str, save_path: str) -> bool:
    body = call_method(url, "invokeMethod", _EDITOR_WIN, "saveTo", [save_path])
    if "<fault>" in body:
        raise RuntimeError(f"invokeMethod returned fault. Body: {body[:500]!r}")
    return "<boolean>1</boolean>" in body


def _phase1_editor_edit_style_and_save(editor_binary: str, port: int, save_path: str) -> None:
    """Editor で btn001 を選択しスタイルを編集 → 保存する。

    btn001 1 件のみ編集し ``addWidget`` を呼ばないため、Repeater 再生成で値が
    巻き戻る罠（CLAUDE.md「Spix（E2E）統合の罠」節）は発生しない。
    """
    with spix_app(editor_binary, port) as url:
        call_method(url, "waitForItem", f"{_EDITOR_WIN}/widget_btn001", 2000)
        if not _exists_and_visible(url, f"{_EDITOR_WIN}/widget_btn001"):
            raise RuntimeError("initial widget_btn001 missing in Editor")

        # クリックで選択（HmiButton の clicked 中継 → selectedWidgetId 更新）。
        call_method(url, "mouseClick", f"{_EDITOR_WIN}/widget_btn001")
        call_method(url, "wait", 100)
        selected = _get_str_property(url, f"{_EDITOR_WIN}/canvas", "selectedWidgetId")
        if selected != "btn001":
            raise RuntimeError(
                f"selection failed: selectedWidgetId={selected!r} (expected 'btn001')"
            )

        # 選択中 EditableWidget のメタへ直接書き戻す（インスペクタの onTextEdited が
        # 書き戻す先と同一）。HmiButton が即追従し、保存走査 snapshotModel が拾う。
        call_method(url, "setStringProperty", f"{_EDITOR_WIN}/widget_btn001", "widgetText", _NEW_TEXT)
        call_method(url, "setStringProperty", f"{_EDITOR_WIN}/widget_btn001", "widgetBackgroundColor", _NEW_BG)
        call_method(url, "setStringProperty", f"{_EDITOR_WIN}/widget_btn001", "widgetTextColor", _NEW_FG)
        call_method(url, "wait", 100)

        if not _invoke_save_to(url, save_path):
            err = call_method(url, "getErrors")
            raise RuntimeError(
                f"saveTo returned false for {save_path!r}. Errors: {err[:500]!r}"
            )

    if not os.path.isfile(save_path):
        raise RuntimeError(f"saved JSON not found: {save_path}")


def _assert_saved_json_has_style(save_path: str) -> None:
    """保存 JSON に btn001 のスタイルが乗っていることを直接検証する
    （Spix 非依存の authoritative チェック）。"""
    with open(save_path, encoding="utf-8") as f:
        doc = json.load(f)
    widgets = doc["screens"][0]["widgets"]
    btn = next((w for w in widgets if w.get("id") == "btn001"), None)
    if btn is None:
        raise RuntimeError(f"btn001 not found in saved JSON: {save_path}")
    problems = []
    if btn.get("text") != _NEW_TEXT:
        problems.append(f"text={btn.get('text')!r} != {_NEW_TEXT!r}")
    if btn.get("backgroundColor") != _NEW_BG:
        problems.append(f"backgroundColor={btn.get('backgroundColor')!r} != {_NEW_BG!r}")
    if btn.get("textColor") != _NEW_FG:
        problems.append(f"textColor={btn.get('textColor')!r} != {_NEW_FG!r}")
    if problems:
        raise RuntimeError("saved JSON style mismatch: " + "; ".join(problems))


def _phase2_simulator_renders_style(simulator_binary: str, port: int, save_path: str) -> None:
    """Simulator を ``--open`` で起動し、HmiButton にスタイルが届いていることを確認。"""
    with spix_app(simulator_binary, port, extra_args=("--open", save_path)) as url:
        wrapper = f"{_SIM_WIN}/widget_btn001"
        button = f"{wrapper}/hmiButton"
        call_method(url, "waitForItem", wrapper, 3000)
        if not _exists_and_visible(url, wrapper):
            raise RuntimeError(f"simulator missing widget_btn001. JSON: {save_path}")
        call_method(url, "waitForItem", button, 3000)

        text = _get_str_property(url, button, "text")
        bg = _get_str_property(url, button, "backgroundColor")
        fg = _get_str_property(url, button, "textColor")
        problems = []
        if text != _NEW_TEXT:
            problems.append(f"text={text!r} != {_NEW_TEXT!r}")
        if bg != _NEW_BG:
            problems.append(f"backgroundColor={bg!r} != {_NEW_BG!r}")
        if fg != _NEW_FG:
            problems.append(f"textColor={fg!r} != {_NEW_FG!r}")
        if problems:
            raise RuntimeError("simulator HmiButton style mismatch: " + "; ".join(problems))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor-binary", required=True)
    parser.add_argument("--simulator-binary", required=True)
    parser.add_argument("--editor-port", type=int, default=9876)
    parser.add_argument("--simulator-port", type=int, default=9877)
    args = parser.parse_args()

    fd, save_path = tempfile.mkstemp(prefix="hmi_task30_", suffix=".json")
    os.close(fd)
    try:
        os.unlink(save_path)
    except FileNotFoundError:
        pass

    try:
        _phase1_editor_edit_style_and_save(
            args.editor_binary, args.editor_port, save_path
        )
        _assert_saved_json_has_style(save_path)
        _phase2_simulator_renders_style(
            args.simulator_binary, args.simulator_port, save_path
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
        "OK: editor style edit -> saved JSON -> simulator rendered "
        f"text={_NEW_TEXT!r} backgroundColor={_NEW_BG!r} textColor={_NEW_FG!r}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
