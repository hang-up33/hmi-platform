"""Phase 6 Task 52: NumericField の typed-write を検証する cross-app E2E。

Task 49（Label）の ``test_label_roundtrip`` は binding の **読み**（変数 → 表示の追従）
だけを見ていた。本テストは Phase 6 の締めとして、入力 Widget = NumericField の
**読み書き両用 binding**（表示=読み・入力確定=書き）を初めて E2E で観測する：

1. **Editor 段**：``setpoint``（int）変数と、それに ``value`` binding で結ばれた
   NumericField（``num001``）+ 同じ変数に ``text`` binding で結ばれた観測用 Label
   （``echo001``）を持つ JSON を Editor に ``--open`` で読ませ、``saveTo`` で別パスへ保存する。
2. **JSON 直接検証**：保存 JSON に ``type:"NumericField"`` / binding ``{property:"value"}`` /
   ``setpoint`` 変数が乗っていることを Python で直接 assert する（Spix 非依存）。
3. **Simulator 段（本 E2E の主眼）**：保存 JSON を Simulator に ``--open`` で読ませ、
   - **読み**：``num001`` の ``HmiNumericField`` text と観測用 ``echo001`` の ``HmiLabel`` text が
     ともに ``setpoint`` 初期値 ``10`` に追従していること（静的値ではない）を確認。
   - **書き**：Spix は実テキスト入力（``editingFinished``）を発火できないため、
     ``setStringProperty(num001/hmiNumericField, "text", "42")`` で入力テキストを設定し、
     **公開メソッド ``commitValue()`` を ``invokeMethod`` で叩いて確定を模す**。これで
     ``valueCommitted`` → delegate の ``writeBoundValue("value", "42")`` →
     ``setpoint`` が ``42`` に更新され、同じ変数を読む ``echo001`` Label が ``"42"`` へ
     追従するのを ``getStringProperty`` で観測する。

**なぜ Editor 段は NumericField 追加 UI を駆動せず fixture を ``--open`` するのか**：
binding / 変数定義は Spix の ``setStringProperty`` で直接設定できず、追加ボタン経由だと
Repeater 再生成の巻き戻り罠を踏むため（test_action_roundtrip と同じ理由）。Editor が
NumericField データを **保存経路で round-trip する**ことを ``--open`` → ``saveTo`` →
JSON 直接 assert で担保し、追加 UI 自体は手動スクショで担保する。

Spix v0.14 制約・回避策は既存 E2E と同方針（正規表現抽出 / 保存 JSON 直接 assert）。
実行環境：E2E は macOS / Linux（``HMI_ENABLE_E2E=ON``）のみ。Windows MinGW は除外。
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import tempfile
import time

from harness import call_method, spix_app

_EDITOR_WIN = "hmiEditorWindow"
_SIM_WIN = "hmiSimulatorWindow"

# 読み書き両用 binding のデモ値。
#   - 変数 setpoint（int）: 初期 10
#   - num001: NumericField、value binding（setpoint 追従＝表示の読み / 確定で書き）
#   - echo001: Label、text binding（setpoint 追従＝書き戻しの観測用）
_VAR_NAME = "setpoint"
_VAR_INITIAL = 10
_TYPED_VALUE = "42"


def _fixture_json() -> dict:
    """setpoint 変数 + NumericField（value binding）+ 観測用 Label（text binding）。"""
    return {
        "project": "Task 52 NumericField E2E",
        "variables": [
            {"name": _VAR_NAME, "type": "int", "initial": _VAR_INITIAL},
        ],
        "screens": [
            {
                "name": "Main",
                "widgets": [
                    {
                        "id": "num001",
                        "type": "NumericField",
                        "x": 60,
                        "y": 60,
                        "width": 160,
                        "height": 48,
                        "text": "0",
                        "bindings": [
                            {"property": "value", "variable": _VAR_NAME}
                        ],
                    },
                    {
                        "id": "echo001",
                        "type": "Label",
                        "x": 60,
                        "y": 140,
                        "width": 160,
                        "height": 40,
                        "text": "?",
                        "bindings": [
                            {"property": "text", "variable": _VAR_NAME}
                        ],
                    },
                ],
            }
        ],
    }


def _get_str_property(url: str, path: str, prop: str) -> str:
    """getStringProperty のレスポンスから文字列値を取り出す（既存 E2E と同方針）。"""
    body = call_method(url, "getStringProperty", path, prop)
    m = re.search(r"<value>(?:<string>)?(.*?)(?:</string>)?</value>", body, re.DOTALL)
    if not m:
        raise RuntimeError(
            f"Failed to extract {prop} from {path}. Response head: {body[:300]!r}"
        )
    return m.group(1).strip()


def _exists_and_visible(url: str, path: str) -> bool:
    """対象パスの Item が存在し可視かを Spix の existsAndVisible で確認する。"""
    body = call_method(url, "existsAndVisible", path)
    return "<boolean>1</boolean>" in body


def _invoke_save_to(url: str, save_path: str) -> bool:
    """Editor Window の ``saveTo(path)`` を invokeMethod で呼び、成功可否を返す。"""
    body = call_method(url, "invokeMethod", _EDITOR_WIN, "saveTo", [save_path])
    if "<fault>" in body:
        raise RuntimeError(f"invokeMethod returned fault. Body: {body[:500]!r}")
    return "<boolean>1</boolean>" in body


def _phase1_editor_roundtrips_numeric(editor_binary: str, port: int,
                                      fixture_path: str, save_path: str) -> None:
    """Editor に fixture を ``--open`` で読ませ ``saveTo`` で保存する。

    num001 / echo001 の 2 件のみで ``addWidget`` を呼ばないため Repeater 再生成の
    巻き戻り罠は発生しない（test_action_roundtrip と同方針）。
    """
    with spix_app(editor_binary, port, extra_args=("--open", fixture_path)) as url:
        call_method(url, "waitForItem", f"{_EDITOR_WIN}/widget_num001", 3000)
        if not _exists_and_visible(url, f"{_EDITOR_WIN}/widget_num001"):
            raise RuntimeError("Editor did not load fixture widget_num001")

        if not _invoke_save_to(url, save_path):
            err = call_method(url, "getErrors")
            raise RuntimeError(
                f"saveTo returned false for {save_path!r}. Errors: {err[:500]!r}"
            )

    if not os.path.isfile(save_path):
        raise RuntimeError(f"saved JSON not found: {save_path}")


def _assert_saved_json_has_numeric(save_path: str) -> None:
    """保存 JSON に NumericField / value binding / 変数が乗っていることを直接検証する。"""
    with open(save_path, encoding="utf-8") as f:
        doc = json.load(f)

    problems = []

    variables = doc.get("variables", [])
    var = next((v for v in variables if v.get("name") == _VAR_NAME), None)
    if var is None:
        problems.append(f"variable {_VAR_NAME!r} missing in saved JSON")
    elif str(var.get("initial")) != str(_VAR_INITIAL):
        problems.append(f"variable initial={var.get('initial')!r} != {_VAR_INITIAL!r}")
    elif var.get("type") != "int":
        problems.append(f"variable type={var.get('type')!r} != 'int'")

    widgets = doc["screens"][0]["widgets"]
    num = next((w for w in widgets if w.get("id") == "num001"), None)
    if num is None:
        raise RuntimeError(f"num001 not found in saved JSON: {save_path}")
    if num.get("type") != "NumericField":
        problems.append(f"num001 type={num.get('type')!r} != 'NumericField'")

    bindings = num.get("bindings", [])
    bind = next((b for b in bindings if b.get("property") == "value"), None)
    if bind is None:
        problems.append("value binding missing on num001")
    elif bind.get("variable") != _VAR_NAME:
        problems.append(f"binding variable={bind.get('variable')!r} != {_VAR_NAME!r}")

    echo = next((w for w in widgets if w.get("id") == "echo001"), None)
    if echo is None:
        problems.append("echo001 (observer Label) missing in saved JSON")

    if problems:
        raise RuntimeError("saved JSON NumericField mismatch: " + "; ".join(problems))


def _phase2_simulator_typed_write(simulator_binary: str, port: int, save_path: str) -> None:
    """Simulator を ``--open`` で起動し、commitValue → 変数 write → Label 追従 を観測する。"""
    with spix_app(simulator_binary, port, extra_args=("--open", save_path)) as url:
        num_wrapper = f"{_SIM_WIN}/widget_num001"
        numeric = f"{num_wrapper}/hmiNumericField"
        echo = f"{_SIM_WIN}/widget_echo001/hmiLabel"
        call_method(url, "waitForItem", numeric, 3000)
        call_method(url, "waitForItem", echo, 3000)
        if not _exists_and_visible(url, num_wrapper):
            raise RuntimeError(f"simulator missing widget_num001. JSON: {save_path}")

        # 読み：NumericField text と観測用 Label text がともに setpoint 初期値 "10" に追従
        # （静的 text "0" / "?" ではない）。
        initial_num = _get_str_property(url, numeric, "text")
        if initial_num != str(_VAR_INITIAL):
            raise RuntimeError(
                f"initial numeric text={initial_num!r} != {str(_VAR_INITIAL)!r} "
                "(value binding did not follow variable initial)"
            )
        initial_echo = _get_str_property(url, echo, "text")
        if initial_echo != str(_VAR_INITIAL):
            raise RuntimeError(
                f"initial echo text={initial_echo!r} != {str(_VAR_INITIAL)!r} "
                "(text binding did not follow variable initial)"
            )

        # 書き：入力テキストを setStringProperty で設定し、commitValue() を invokeMethod で
        # 叩いて確定を模す（Spix は editingFinished を発火できない）。確定で setpoint が
        # "42" に更新され、同じ変数を読む echo001 Label が追従する。
        call_method(url, "setStringProperty", numeric, "text", _TYPED_VALUE)
        body = call_method(url, "invokeMethod", numeric, "commitValue", [])
        if "<fault>" in body:
            raise RuntimeError(f"commitValue invokeMethod fault. Body: {body[:500]!r}")

        # 反映は同期的だが CI 負荷時の false negative を避けて短いポーリングで待つ。
        deadline = time.monotonic() + 3.0
        after = ""
        while time.monotonic() < deadline:
            after = _get_str_property(url, echo, "text")
            if after == _TYPED_VALUE:
                break
            time.sleep(0.05)
        if after != _TYPED_VALUE:
            raise RuntimeError(
                f"after commit echo text={after!r} != {_TYPED_VALUE!r} "
                "(typed-write did not update variable, or binding did not follow)"
            )


def main() -> int:
    """fixture 生成 → Editor round-trip 保存 → JSON 検証 → Simulator typed-write を順に走らせる。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor-binary", required=True)
    parser.add_argument("--simulator-binary", required=True)
    parser.add_argument("--editor-port", type=int, default=9876)
    parser.add_argument("--simulator-port", type=int, default=9877)
    args = parser.parse_args()

    fixture_path = ""
    save_path = ""
    try:
        fd, fixture_path = tempfile.mkstemp(prefix="hmi_task52_fixture_", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(_fixture_json(), f, ensure_ascii=False, indent=2)

        fd2, save_path = tempfile.mkstemp(prefix="hmi_task52_saved_", suffix=".json")
        os.close(fd2)
        os.unlink(save_path)

        _phase1_editor_roundtrips_numeric(
            args.editor_binary, args.editor_port, fixture_path, save_path
        )
        _assert_saved_json_has_numeric(save_path)
        _phase2_simulator_typed_write(
            args.simulator_binary, args.simulator_port, save_path
        )
    except Exception as exc:
        print(f"FAIL: {exc}", file=sys.stderr)
        return 1
    finally:
        for p in (fixture_path, save_path):
            if not p:
                continue
            try:
                os.unlink(p)
            except FileNotFoundError:
                pass

    print(
        "OK: editor round-trips NumericField/value-binding -> saved JSON -> "
        f"simulator commitValue drives {_VAR_NAME} {_VAR_INITIAL!r} -> {_TYPED_VALUE!r} "
        "via writeBoundValue + text binding follow"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
