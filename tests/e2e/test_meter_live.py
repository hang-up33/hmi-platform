"""Phase 10 Task M-D: Meter の針追従を観測する cross-app E2E。

Phase 10 で追加した新 Widget 種別「Meter」（車のスピードメーター風＝円弧（アーク）＋針の
QML ``Canvas`` 自描画）は、既存 ``bindings``（``{property:"value", variable:X}``）の「読み」を
再利用して変数の現在値を針の指す値にする（読み取り専用表示＝書きはしない）。本テストは
Phase 10 の締めとして：

1. **Editor 段（round-trip 担保）**：``vehicleSpeed``（int）変数と、それに ``value`` binding で
   結ばれた Meter（``meter001``）+ 同じ変数に ``value`` binding で結ばれた操作用
   NumericField（``speeder001``）を持つ JSON を Editor に ``--open`` で読ませ、``saveTo`` で
   別パスへ保存する。保存 JSON を Python で直接 assert：``type:"Meter"`` / Meter の value
   binding / スケール範囲（``meterMin``/``meterMax``）が round-trip すること。
2. **Simulator 段（本 E2E の主眼＝針追従観測）**：保存 JSON を Simulator に ``--open`` で
   読ませ、Meter（``HmiMeter``, objectName ``hmiMeter``）の公開プロパティを ``getStringProperty``
   で読む。Canvas のピクセルは offscreen で不可視なので **公開プロパティ ``displayValue`` /
   ``needleAngle`` だけ**で「変数変化 → 針追従」を観測する。操作用 NumericField の内部
   ``TextField.text`` を ``setStringProperty`` で設定し **公開メソッド ``commitValue()`` を
   ``invokeMethod`` で叩いて確定を模す**（Spix は実テキスト入力 = ``editingFinished`` を発火
   できない＝Phase 6 Task 52 と同手法）。確定で ``vehicleSpeed`` が更新され、Meter の delegate
   が ``boundValue("value")`` 経由で ``value`` を更新 → HmiMeter が ``displayValue`` を clamp し
   ``needleAngle`` を弧の角度域へ線形マッピングする。これを **異なる値で複数回**繰り返し、
   各回で ``displayValue`` が書いた値（範囲外は端へ clamp）へ、``needleAngle`` が期待角度へ
   追従することを観測する。**期待角度は HmiMeter の公開 ``startAngle``/``spanAngle`` を実行時に
   読んで計算する**（既定角度の定数〔135°/270°〕へテストを結合しない。plan リスク 2 で
   「乖離したら同コミットで plan 更新」＝角度既定は変わりうる）。

Canvas のピクセル検証はしない（offscreen で不可視）。観測は公開 real プロパティの文字列化
（``getStringProperty``）に限る（plan §テスト方針 3「公開 ``displayValue``/``needleAngle`` を
``getStringProperty`` で観測」）。

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

# 値源変数（int）。操作用 NumericField で値を書き換えると、同じ変数を value binding で読む
# Meter が boundValue("value") 経由で取り込み、針が追従する。
_VAR_NAME = "vehicleSpeed"
_VAR_INITIAL = 0

# Meter のスケール範囲（round-trip で保存 JSON に乗ることを assert する）。負値でない 0/180 だが
# presence フラグ方式で meterMin/meterMax キーとして書かれることを検証する。
_METER_MIN = 0
_METER_MAX = 180

# 操作用 NumericField で順に確定する値。最後の "200" は meterMax=180 を超える＝端へ clamp される
# ことを displayValue で観測する（範囲内 2 値 + 範囲外 1 値）。
_TYPED_SEQUENCE = ["60", "120", "200"]

# needleAngle の期待値と実測の許容誤差[deg]（real の文字列化・浮動小数演算の丸め対策）。
_ANGLE_TOL = 0.5


def _fixture_json() -> dict:
    """vehicleSpeed 変数 + Meter（value binding + 範囲）+ 操作用 NumericField（value binding）。"""
    return {
        "project": "Task M-D Meter live E2E",
        "variables": [
            {"name": _VAR_NAME, "type": "int", "initial": _VAR_INITIAL},
        ],
        "screens": [
            {
                "name": "Main",
                "widgets": [
                    {
                        "id": "meter001",
                        "type": "Meter",
                        "x": 40,
                        "y": 40,
                        "width": 200,
                        "height": 200,
                        "backgroundColor": "#0b1d2a",
                        "arcColor": "#4cc9f0",
                        "needleColor": "#ff595e",
                        "meterMin": _METER_MIN,
                        "meterMax": _METER_MAX,
                        "tickCount": 12,
                        "unit": "km/h",
                        "bindings": [
                            {"property": "value", "variable": _VAR_NAME}
                        ],
                    },
                    {
                        "id": "speeder001",
                        "type": "NumericField",
                        "x": 40,
                        "y": 260,
                        "width": 160,
                        "height": 48,
                        "text": "0",
                        "bindings": [
                            {"property": "value", "variable": _VAR_NAME}
                        ],
                    },
                ],
            }
        ],
    }


def _get_str_property(url: str, path: str, prop: str) -> str:
    """getStringProperty のレスポンスから文字列値を取り出す（既存 E2E と同方針）。

    displayValue / needleAngle / startAngle / spanAngle（いずれも real）も QVariant 文字列化で
    取得できる。
    """
    body = call_method(url, "getStringProperty", path, prop)
    m = re.search(r"<value>(?:<string>)?(.*?)(?:</string>)?</value>", body, re.DOTALL)
    if not m:
        raise RuntimeError(
            f"Failed to extract {prop} from {path}. Response head: {body[:300]!r}"
        )
    return m.group(1).strip()


def _get_num(url: str, path: str, prop: str) -> float:
    """公開数値プロパティ（displayValue / needleAngle 等）を取得して float 化する。"""
    return float(_get_str_property(url, path, prop))


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
    （test_trend_live / test_numeric_input と同方針）。
    """
    with spix_app(editor_binary, port, extra_args=("--open", fixture_path)) as url:
        call_method(url, "waitForItem", f"{_EDITOR_WIN}/widget_meter001", 3000)
        if not _exists_and_visible(url, f"{_EDITOR_WIN}/widget_meter001"):
            raise RuntimeError("Editor did not load fixture widget_meter001")
        if not _exists_and_visible(url, f"{_EDITOR_WIN}/widget_speeder001"):
            raise RuntimeError("Editor did not load fixture widget_speeder001")

        if not _invoke_save_to(url, save_path):
            err = call_method(url, "getErrors")
            raise RuntimeError(
                f"saveTo returned false for {save_path!r}. Errors: {err[:500]!r}"
            )

    if not os.path.isfile(save_path):
        raise RuntimeError(f"saved JSON not found: {save_path}")


def _assert_saved_json(save_path: str) -> None:
    """保存 JSON に Meter / value binding / スケール範囲が乗っていることを直接検証する。"""
    with open(save_path, encoding="utf-8") as f:
        doc = json.load(f)

    problems = []

    variables = doc.get("variables", [])
    var = next((v for v in variables if v.get("name") == _VAR_NAME), None)
    if var is None:
        problems.append(f"variable {_VAR_NAME!r} missing in saved JSON")
    elif var.get("type") != "int":
        problems.append(f"variable {_VAR_NAME!r} type={var.get('type')!r} != 'int'")

    widgets = doc["screens"][0]["widgets"]

    meter = next((w for w in widgets if w.get("id") == "meter001"), None)
    if meter is None:
        raise RuntimeError(f"meter001 not found in saved JSON: {save_path}")
    if meter.get("type") != "Meter":
        problems.append(f"meter001 type={meter.get('type')!r} != 'Meter'")
    # スケール範囲は presence フラグ方式＝キーが存在し値が round-trip すること。
    if meter.get("meterMin") != _METER_MIN:
        problems.append(f"meter001 meterMin={meter.get('meterMin')!r} != {_METER_MIN!r}")
    if meter.get("meterMax") != _METER_MAX:
        problems.append(f"meter001 meterMax={meter.get('meterMax')!r} != {_METER_MAX!r}")
    mbind = next((b for b in meter.get("bindings", [])
                  if b.get("property") == "value"), None)
    if mbind is None or mbind.get("variable") != _VAR_NAME:
        problems.append("meter001 value binding (needle source) missing/mismatched")

    speeder = next((w for w in widgets if w.get("id") == "speeder001"), None)
    if speeder is None:
        problems.append("speeder001 (control NumericField) missing in saved JSON")
    elif speeder.get("type") != "NumericField":
        problems.append(f"speeder001 type={speeder.get('type')!r} != 'NumericField'")

    if problems:
        raise RuntimeError("saved JSON Meter mismatch: " + "; ".join(problems))


def _expected_angle(start_angle: float, span_angle: float,
                    lo: float, hi: float, display: float) -> float:
    """HmiMeter の値→針角度マッピング（線形 + clamp）を Python 側で再現する。

    HmiMeter.needleAngle = startAngle + (displayValue - min)/(max - min) * spanAngle。
    定数（startAngle=135 / spanAngle=270）へは結合せず、実行時に読んだ実値で計算する。
    """
    if hi <= lo:
        return start_angle
    frac = (display - lo) / (hi - lo)
    return start_angle + frac * span_angle


def _phase2_simulator_live(simulator_binary: str, port: int, save_path: str) -> None:
    """Simulator を ``--open`` で起動し、変数変化 → Meter 針追従を観測する。"""
    with spix_app(simulator_binary, port, extra_args=("--open", save_path)) as url:
        meter = f"{_SIM_WIN}/widget_meter001/hmiMeter"
        # NumericField は root（HmiNumericField, objectName "hmiNumericField"）を指す。
        # commitValue() は root のメソッドなので invoke も root に対して行う
        # （test_numeric_input / test_trend_live と同じ参照粒度）。
        speeder = f"{_SIM_WIN}/widget_speeder001/hmiNumericField"
        for p in (meter, speeder):
            call_method(url, "waitForItem", p, 3000)
        if not _exists_and_visible(url, f"{_SIM_WIN}/widget_meter001"):
            raise RuntimeError(f"simulator missing widget_meter001. JSON: {save_path}")
        if not _exists_and_visible(url, f"{_SIM_WIN}/widget_speeder001"):
            raise RuntimeError(f"simulator missing widget_speeder001. JSON: {save_path}")

        # 弧の角度域と解決済みスケール範囲を実行時に読む（定数へ結合せず期待角度を計算する）。
        start_angle = _get_num(url, meter, "startAngle")
        span_angle = _get_num(url, meter, "spanAngle")
        lo = _get_num(url, meter, "resolvedMeterMin")
        hi = _get_num(url, meter, "resolvedMeterMax")

        # 操作用 NumericField から同じ変数を異なる値で複数回確定する。各確定後に displayValue が
        # 書いた値（範囲外は端へ clamp）へ、needleAngle が期待角度へ追従することを観測する。
        for typed in _TYPED_SEQUENCE:
            call_method(url, "setStringProperty", speeder, "text", typed)
            body = call_method(url, "invokeMethod", speeder, "commitValue", [])
            if "<fault>" in body:
                raise RuntimeError(
                    f"commitValue invokeMethod fault for {typed!r}. Body: {body[:500]!r}"
                )

            # 期待表示値は resolved 範囲へ clamp した値（"200" は max=180 へ張り付く）。
            expected_display = max(lo, min(hi, float(typed)))
            expected_angle = _expected_angle(
                start_angle, span_angle, lo, hi, expected_display
            )

            deadline = time.monotonic() + 3.0
            display = None
            angle = None
            while time.monotonic() < deadline:
                display = _get_num(url, meter, "displayValue")
                angle = _get_num(url, meter, "needleAngle")
                if (display == expected_display
                        and abs(angle - expected_angle) <= _ANGLE_TOL):
                    break
                time.sleep(0.05)

            if display != expected_display:
                raise RuntimeError(
                    f"after commit {typed!r}: displayValue={display!r} != "
                    f"{expected_display!r} (Meter did not follow the variable / clamp "
                    "to scale range)"
                )
            if abs(angle - expected_angle) > _ANGLE_TOL:
                raise RuntimeError(
                    f"after commit {typed!r}: needleAngle={angle!r} != "
                    f"{expected_angle!r} (±{_ANGLE_TOL}) — needle did not map to the "
                    "arc angle range for the new value"
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
        fd, fixture_path = tempfile.mkstemp(prefix="hmi_taskMD_fixture_", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(_fixture_json(), f, ensure_ascii=False, indent=2)

        fd2, save_path = tempfile.mkstemp(prefix="hmi_taskMD_saved_", suffix=".json")
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
        "OK: editor round-trips Meter/value-binding/meterMin-meterMax -> saved JSON -> "
        f"simulator commitValue drives {_VAR_NAME} through {_TYPED_SEQUENCE} -> "
        "Meter follows (displayValue clamps to scale range, needleAngle maps to arc) "
        "via boundValue('value')"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
