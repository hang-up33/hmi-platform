"""Phase 11 Task W-E: SimpleButton の長押しトグル round-trip を観測する cross-app E2E。

Phase 11 で追加した新 Widget 種別「SimpleButton」（issue #155 のベゼル無しシンプルボタン＝
QML ``Canvas`` 自描画 + hold-to-actuate）は、既存 ``bindings``（``{property:"checked", variable:X}``）
を読み（変数 → ON/OFF 表示追従）と書き（長押し確定 → 変数へ次値書き戻し）の両方に使う
（NumericField の読み書き両用 binding と同型。Schema / C++ ブリッジ無改変）。本テストは
Phase 11 の締めとして：

1. **Editor 段（round-trip 担保）**：``pumpRunning``（bool）変数と、それに ``checked`` binding で
   結ばれた SimpleButton（``sb001``、shape/theme/accentColor/holdMs 付き）を持つ JSON を
   Editor に ``--open`` で読ませ、``saveTo`` で別パスへ保存する。保存 JSON を Python で直接
   assert：``type:"SimpleButton"`` / SimpleButton 固有フィールド（``shape``/``theme``/
   ``accentColor``/``holdMs``）/ checked binding が round-trip すること。
2. **Simulator 段（本 E2E の主眼＝長押しトグル観測）**：保存 JSON を Simulator に ``--open``
   で読ませ、SimpleButton（``HmiSimpleButton``, objectName ``hmiSimpleButton``）の公開
   プロパティを ``getStringProperty`` で読む。Canvas のピクセルは offscreen で不可視なので
   **公開プロパティ ``checked`` だけ**で「長押し確定 → 変数 → ON/OFF 追従」を観測する。
   Spix は実 press-hold（長押し）を発火できないため、**公開メソッド ``commitHold()`` を
   ``invokeMethod`` で叩いて長押し満了（確定）を模す**（Phase 6 Task 52 の ``commitValue()``
   と同じ「確定点を公開する」前例）。確定で delegate の ``onToggled`` が
   ``writeBoundValue("checked", 次値)`` を呼び、``VariableStore`` の ``pumpRunning`` が更新され、
   ``checked: boundValue("checked")`` バインディングが再評価されて ON/OFF が切り替わる。
   これを **複数回**繰り返し、each 回で ``checked`` が反転（false→true→false）することを観測
   する＝binding の読み（表示追従）と書き（次値書き戻し）の両経路を 1 本の round-trip で見る。

Canvas のピクセル検証はしない（offscreen で不可視）。観測は公開 bool プロパティの文字列化
（``getStringProperty``）に限る（plan §テスト方針 4「公開 ``holdProgress``/``checked`` を観測」）。

Spix v0.14 制約・回避策は既存 E2E と同方針。実行環境：E2E は macOS / Linux
（``HMI_ENABLE_E2E=ON``）のみ。Windows MinGW は除外。
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

# ON/OFF 状態の値源変数（bool）。SimpleButton の checked binding が読み書き両方に使う。
_VAR_NAME = "pumpRunning"

# SimpleButton 固有フィールド（保存 JSON に round-trip することを assert する値）。
_SHAPE = "square"
_THEME = "dark"
_ACCENT = "#ff9f1c"
_HOLD_MS = 400

# commitHold() を繰り返す回数。各回で checked が反転する（false→true→false→true）。
_TOGGLE_COUNT = 3


def _fixture_json() -> dict:
    """pumpRunning 変数 + SimpleButton（checked binding + 固有フィールド）。"""
    return {
        "project": "Task W-E SimpleButton live E2E",
        "variables": [
            {"name": _VAR_NAME, "type": "bool", "initial": "false"},
        ],
        "screens": [
            {
                "name": "Main",
                "widgets": [
                    {
                        "id": "sb001",
                        "type": "SimpleButton",
                        "x": 40,
                        "y": 40,
                        "width": 184,
                        "height": 184,
                        "text": "PUMP",
                        "shape": _SHAPE,
                        "theme": _THEME,
                        "accentColor": _ACCENT,
                        "holdMs": _HOLD_MS,
                        "bindings": [
                            {"property": "checked", "variable": _VAR_NAME}
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


def _get_bool(url: str, path: str, prop: str) -> bool:
    """公開 bool プロパティ（checked / live 等）を取得して bool 化する。

    QVariant(bool) の文字列化は "true"/"false"。
    """
    return _get_str_property(url, path, prop).lower() == "true"


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


def _phase1_editor_roundtrips(editor_binary: str, port: int,
                              fixture_path: str, save_path: str) -> None:
    """Editor に fixture を ``--open`` で読ませ ``saveTo`` で保存する。

    addWidget を呼ばないため Repeater 再生成の巻き戻り罠は発生しない
    （test_meter_live / test_trend_live と同方針）。
    """
    with spix_app(editor_binary, port, extra_args=("--open", fixture_path)) as url:
        call_method(url, "waitForItem", f"{_EDITOR_WIN}/widget_sb001", 3000)
        if not _exists_and_visible(url, f"{_EDITOR_WIN}/widget_sb001"):
            raise RuntimeError("Editor did not load fixture widget_sb001")

        if not _invoke_save_to(url, save_path):
            err = call_method(url, "getErrors")
            raise RuntimeError(
                f"saveTo returned false for {save_path!r}. Errors: {err[:500]!r}"
            )

    if not os.path.isfile(save_path):
        raise RuntimeError(f"saved JSON not found: {save_path}")


def _assert_saved_json(save_path: str) -> None:
    """保存 JSON に SimpleButton 固有フィールド / checked binding が乗っていることを直接検証する。"""
    with open(save_path, encoding="utf-8") as f:
        doc = json.load(f)

    problems = []

    variables = doc.get("variables", [])
    var = next((v for v in variables if v.get("name") == _VAR_NAME), None)
    if var is None:
        problems.append(f"variable {_VAR_NAME!r} missing in saved JSON")
    elif var.get("type") != "bool":
        problems.append(f"variable {_VAR_NAME!r} type={var.get('type')!r} != 'bool'")

    widgets = doc["screens"][0]["widgets"]

    sb = next((w for w in widgets if w.get("id") == "sb001"), None)
    if sb is None:
        raise RuntimeError(f"sb001 not found in saved JSON: {save_path}")
    if sb.get("type") != "SimpleButton":
        problems.append(f"sb001 type={sb.get('type')!r} != 'SimpleButton'")
    # SimpleButton 固有フィールド（W-A の 4 メソッド round-trip が Editor 経由でも保たれること）。
    if sb.get("shape") != _SHAPE:
        problems.append(f"sb001 shape={sb.get('shape')!r} != {_SHAPE!r}")
    if sb.get("theme") != _THEME:
        problems.append(f"sb001 theme={sb.get('theme')!r} != {_THEME!r}")
    if sb.get("accentColor") != _ACCENT:
        problems.append(f"sb001 accentColor={sb.get('accentColor')!r} != {_ACCENT!r}")
    if sb.get("holdMs") != _HOLD_MS:
        problems.append(f"sb001 holdMs={sb.get('holdMs')!r} != {_HOLD_MS!r}")
    sbind = next((b for b in sb.get("bindings", [])
                  if b.get("property") == "checked"), None)
    if sbind is None or sbind.get("variable") != _VAR_NAME:
        problems.append("sb001 checked binding (ON/OFF source) missing/mismatched")

    if problems:
        raise RuntimeError("saved JSON SimpleButton mismatch: " + "; ".join(problems))


def _phase2_simulator_live(simulator_binary: str, port: int, save_path: str) -> None:
    """Simulator を ``--open`` で起動し、長押し確定（commitHold）→ checked トグルを観測する。"""
    with spix_app(simulator_binary, port, extra_args=("--open", save_path)) as url:
        sb = f"{_SIM_WIN}/widget_sb001/hmiSimpleButton"
        call_method(url, "waitForItem", sb, 3000)
        if not _exists_and_visible(url, f"{_SIM_WIN}/widget_sb001"):
            raise RuntimeError(f"simulator missing widget_sb001. JSON: {save_path}")

        # Simulator 側はライブ実行（live:true）で起動していること（Editor は live:false）。
        if not _get_bool(url, sb, "live"):
            raise RuntimeError("simulator SimpleButton is not live (live != true)")

        # 初期状態：変数 initial=false → checked binding 経由で OFF。
        expected = False
        if _get_bool(url, sb, "checked") is not expected:
            raise RuntimeError("initial checked != false (binding initial not applied)")

        # 長押し満了（確定）を commitHold() で模し、each 回で checked が反転することを観測する。
        # 確定 → onToggled → writeBoundValue("checked", 次値) → VariableStore →
        # checked: boundValue("checked") 再評価、の非同期一巡を tryVerify 相当のポーリングで待つ。
        for i in range(_TOGGLE_COUNT):
            body = call_method(url, "invokeMethod", sb, "commitHold", [])
            if "<fault>" in body:
                raise RuntimeError(
                    f"commitHold invokeMethod fault (round {i + 1}). Body: {body[:500]!r}"
                )
            expected = not expected

            deadline = time.monotonic() + 3.0
            checked = None
            while time.monotonic() < deadline:
                checked = _get_bool(url, sb, "checked")
                if checked is expected:
                    break
                time.sleep(0.05)

            if checked is not expected:
                raise RuntimeError(
                    f"after commitHold round {i + 1}: checked={checked!r} != "
                    f"{expected!r} (hold-to-actuate did not toggle the bound variable "
                    "or the checked binding did not follow it)"
                )


def main() -> int:
    """fixture 生成 → Editor round-trip 保存 → JSON 検証 → Simulator ライブ観測。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor-binary", required=True)
    parser.add_argument("--simulator-binary", required=True)
    parser.add_argument("--editor-port", type=int, default=9876)
    parser.add_argument("--simulator-port", type=int, default=9877)
    args = parser.parse_args()

    fixture_path = ""
    save_path = ""
    try:
        fd, fixture_path = tempfile.mkstemp(prefix="hmi_taskWE_fixture_", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(_fixture_json(), f, ensure_ascii=False, indent=2)

        fd2, save_path = tempfile.mkstemp(prefix="hmi_taskWE_saved_", suffix=".json")
        os.close(fd2)
        os.unlink(save_path)

        _phase1_editor_roundtrips(
            args.editor_binary, args.editor_port, fixture_path, save_path
        )
        _assert_saved_json(save_path)
        _phase2_simulator_live(
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
        "OK: editor round-trips SimpleButton shape/theme/accentColor/holdMs + "
        "checked-binding -> saved JSON -> simulator commitHold() toggles "
        f"{_VAR_NAME} {_TOGGLE_COUNT}x -> checked follows via boundValue('checked') "
        "(read) + writeBoundValue (write)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
