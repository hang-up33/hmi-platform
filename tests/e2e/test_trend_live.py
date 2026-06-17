"""Phase 8 Task T-D: Trend のライブサンプリングを観測する cross-app E2E。

Phase 8 で追加した新 Widget 種別「Trend」（QML ``Canvas`` 自描画のライブ折れ線）は、
既存 ``bindings``（``{property:"value", variable:X}``）の「読み」を再利用して
変数の現在値をサンプル源にする。本テストは Phase 8 の締めとして：

1. **Editor 段（round-trip 担保）**：``sensorTemp``（int）変数と、それに ``value`` binding で
   結ばれた Trend（``trend001``）+ 同じ変数に ``value`` binding で結ばれた操作用
   NumericField（``feeder001``）を持つ JSON を Editor に ``--open`` で読ませ、
   ``saveTo`` で別パスへ保存する。保存 JSON を Python で直接 assert：
   ``type:"Trend"`` / Trend の value binding / ``pointCount`` が round-trip すること。
2. **Simulator 段（本 E2E の主眼＝ライブサンプリング観測）**：保存 JSON を Simulator に
   ``--open`` で読ませ、Trend（``HmiTrend``, objectName ``hmiTrend``）の初期 ``sampleCount`` を
   ``getStringProperty`` で読む。Canvas のピクセルは offscreen で不可視なので **公開
   プロパティ ``sampleCount`` / ``lastValue`` だけ**で「変数変化 → サンプル取り込み」を観測する。
   操作用 NumericField の内部 ``TextField.text`` を ``setStringProperty`` で設定し
   **公開メソッド ``commitValue()`` を ``invokeMethod`` で叩いて確定を模す**（Spix は
   実テキスト入力 = ``editingFinished`` を発火できない＝Phase 6 Task 52 と同手法）。
   確定で ``sensorTemp`` が更新され、Trend の delegate が ``boundValue("value")`` 経由で
   ``value`` を更新 → HmiTrend の ``onValueChanged`` がリングバッファへ 1 点 push する。
   これを **異なる値で複数回**繰り返し、各回で ``sampleCount`` が増加し ``lastValue`` が
   最後に書いた値へ追従することを観測する。

Canvas のピクセル検証はしない（offscreen で不可視）。観測は公開 int/real プロパティの
文字列化（``getStringProperty``）に限る（plan §Task D「公開 ``sampleCount``/``lastValue`` を
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

# サンプル源変数（int）。操作用 NumericField で値を書き換えると、同じ変数を value binding で
# 読む Trend が boundValue("value") 経由で取り込む。
_VAR_NAME = "sensorTemp"
_VAR_INITIAL = 10
# 操作用 NumericField で順に確定する値（異なる値＝lastValue 追従を一意に観測できる）。
_TYPED_SEQUENCE = ["25", "40", "15"]
# Trend の点数（round-trip で保存 JSON に乗ることを assert する）。
_POINT_COUNT = 80


def _fixture_json() -> dict:
    """sensorTemp 変数 + Trend（value binding）+ 操作用 NumericField（value binding）。"""
    return {
        "project": "Task T-D Trend live E2E",
        "variables": [
            {"name": _VAR_NAME, "type": "int", "initial": _VAR_INITIAL},
        ],
        "screens": [
            {
                "name": "Main",
                "widgets": [
                    {
                        "id": "trend001",
                        "type": "Trend",
                        "x": 40,
                        "y": 40,
                        "width": 320,
                        "height": 160,
                        "backgroundColor": "#0b1d2a",
                        "lineColor": "#4cc9f0",
                        "pointCount": _POINT_COUNT,
                        "yMin": 0,
                        "yMax": 100,
                        "bindings": [
                            {"property": "value", "variable": _VAR_NAME}
                        ],
                    },
                    {
                        "id": "feeder001",
                        "type": "NumericField",
                        "x": 40,
                        "y": 220,
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

    sampleCount（int）/ lastValue（real）も QVariant 文字列化で取得できる。
    """
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


def _phase1_editor_roundtrips(editor_binary: str, port: int,
                              fixture_path: str, save_path: str) -> None:
    """Editor に fixture を ``--open`` で読ませ ``saveTo`` で保存する。

    addWidget を呼ばないため Repeater 再生成の巻き戻り罠は発生しない
    （test_numeric_input / test_action_roundtrip と同方針）。
    """
    with spix_app(editor_binary, port, extra_args=("--open", fixture_path)) as url:
        call_method(url, "waitForItem", f"{_EDITOR_WIN}/widget_trend001", 3000)
        if not _exists_and_visible(url, f"{_EDITOR_WIN}/widget_trend001"):
            raise RuntimeError("Editor did not load fixture widget_trend001")
        if not _exists_and_visible(url, f"{_EDITOR_WIN}/widget_feeder001"):
            raise RuntimeError("Editor did not load fixture widget_feeder001")

        if not _invoke_save_to(url, save_path):
            err = call_method(url, "getErrors")
            raise RuntimeError(
                f"saveTo returned false for {save_path!r}. Errors: {err[:500]!r}"
            )

    if not os.path.isfile(save_path):
        raise RuntimeError(f"saved JSON not found: {save_path}")


def _assert_saved_json(save_path: str) -> None:
    """保存 JSON に Trend / value binding / pointCount が乗っていることを直接検証する。"""
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

    trend = next((w for w in widgets if w.get("id") == "trend001"), None)
    if trend is None:
        raise RuntimeError(f"trend001 not found in saved JSON: {save_path}")
    if trend.get("type") != "Trend":
        problems.append(f"trend001 type={trend.get('type')!r} != 'Trend'")
    if trend.get("pointCount") != _POINT_COUNT:
        problems.append(
            f"trend001 pointCount={trend.get('pointCount')!r} != {_POINT_COUNT!r}"
        )
    tbind = next((b for b in trend.get("bindings", [])
                  if b.get("property") == "value"), None)
    if tbind is None or tbind.get("variable") != _VAR_NAME:
        problems.append("trend001 value binding (sample source) missing/mismatched")

    feeder = next((w for w in widgets if w.get("id") == "feeder001"), None)
    if feeder is None:
        problems.append("feeder001 (control NumericField) missing in saved JSON")
    elif feeder.get("type") != "NumericField":
        problems.append(f"feeder001 type={feeder.get('type')!r} != 'NumericField'")

    if problems:
        raise RuntimeError("saved JSON Trend mismatch: " + "; ".join(problems))


def _get_int(url: str, path: str, prop: str) -> int:
    """公開 int プロパティ（sampleCount 等）を取得して int 化する。"""
    return int(_get_str_property(url, path, prop))


def _get_num(url: str, path: str, prop: str) -> float:
    """公開数値プロパティ（lastValue 等）を取得して float 化する。"""
    return float(_get_str_property(url, path, prop))


def _phase2_simulator_live(simulator_binary: str, port: int, save_path: str) -> None:
    """Simulator を ``--open`` で起動し、変数変化 → Trend サンプル取り込みを観測する。"""
    with spix_app(simulator_binary, port, extra_args=("--open", save_path)) as url:
        trend = f"{_SIM_WIN}/widget_trend001/hmiTrend"
        # NumericField は root（HmiNumericField, objectName "hmiNumericField"）を指す。
        # commitValue() は root のメソッドなので invoke も root に対して行う
        # （test_numeric_input / test_numeric_extend と同じ参照粒度）。
        feeder = f"{_SIM_WIN}/widget_feeder001/hmiNumericField"
        for p in (trend, feeder):
            call_method(url, "waitForItem", p, 3000)
        if not _exists_and_visible(url, f"{_SIM_WIN}/widget_trend001"):
            raise RuntimeError(f"simulator missing widget_trend001. JSON: {save_path}")
        if not _exists_and_visible(url, f"{_SIM_WIN}/widget_feeder001"):
            raise RuntimeError(f"simulator missing widget_feeder001. JSON: {save_path}")

        # 初期サンプル数を記録する。Trend は live:true なので value（= 変数初期値）への
        # 初回バインド評価で 0〜1 点取り込まれている可能性がある。差分で増加を観測するため
        # 絶対値ではなく初期値からの増分を見る。
        prev_count = _get_int(url, trend, "sampleCount")

        # 操作用 NumericField から同じ変数を異なる値で複数回確定する。各確定後に
        # sampleCount が増加し lastValue が直近の書込値へ追従することを観測する。
        for typed in _TYPED_SEQUENCE:
            call_method(url, "setStringProperty", feeder, "text", typed)
            body = call_method(url, "invokeMethod", feeder, "commitValue", [])
            if "<fault>" in body:
                raise RuntimeError(
                    f"commitValue invokeMethod fault for {typed!r}. Body: {body[:500]!r}"
                )

            expected_last = float(typed)
            deadline = time.monotonic() + 3.0
            count = prev_count
            last = None
            while time.monotonic() < deadline:
                count = _get_int(url, trend, "sampleCount")
                last = _get_num(url, trend, "lastValue")
                if count > prev_count and last == expected_last:
                    break
                time.sleep(0.05)

            if not (count > prev_count):
                raise RuntimeError(
                    f"after commit {typed!r}: sampleCount={count} did not increase "
                    f"from {prev_count} (variable change did not produce a sample)"
                )
            if last != expected_last:
                raise RuntimeError(
                    f"after commit {typed!r}: lastValue={last!r} != {expected_last!r} "
                    "(Trend did not take the latest variable value as a sample)"
                )
            prev_count = count


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
        fd, fixture_path = tempfile.mkstemp(prefix="hmi_taskTD_fixture_", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(_fixture_json(), f, ensure_ascii=False, indent=2)

        fd2, save_path = tempfile.mkstemp(prefix="hmi_taskTD_saved_", suffix=".json")
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
        "OK: editor round-trips Trend/value-binding/pointCount -> saved JSON -> "
        f"simulator commitValue drives {_VAR_NAME} through {_TYPED_SEQUENCE} -> "
        "Trend takes live samples (sampleCount increases, lastValue follows) "
        "via boundValue('value')"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
