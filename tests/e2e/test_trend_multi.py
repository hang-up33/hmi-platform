"""Phase 8-B Task 8B-E: Trend 複数系列の「系列ごと独立サンプリング」を観測する cross-app E2E。

Phase 8 の単系列 Trend（test_trend_live.py）を補完し、Phase 8-B の核＝**複数系列**
（1 つの Trend に N 本の折れ線・系列ごとに別変数をサンプル源にする）が
**系列ごとに独立して追従する**ことを公開プロパティで観測する：

1. **Editor 段（round-trip 担保）**：2 系列（``sensorTemp`` / ``sensorPressure``）+ 凡例 ON
   （``showLegend:true`` / ``showGrid:true`` / ``yTickCount``）を持つ Trend（``trend001``）と、
   各系列の変数を ``value`` binding で操作する NumericField 2 つ（``feedA001`` / ``feedB001``）を
   持つ JSON を Editor に ``--open`` で読ませ、``saveTo`` で別パスへ保存する。保存 JSON を
   Python で直接 assert：``type:"Trend"`` / ``series`` 2 件 / 各 ``variable``・``color`` /
   ``showLegend:true``（必要なら ``showGrid``/``yTickCount``）が round-trip すること。
2. **Simulator 段（本 E2E の主眼＝系列ごと独立サンプリング観測）**：保存 JSON を Simulator に
   ``--open`` で読ませ、Trend（``HmiTrend``, objectName ``hmiTrend``）の公開プロパティを
   ``getStringProperty`` で読む。Canvas のピクセルは offscreen で不可視なので **系列ごとの
   公開メソッド ``sampleCountAt(i)`` / ``lastValueAt(i)``**（QVariant 文字列化）だけで観測する。
   操作用 NumericField A/B の内部 ``TextField.text`` を ``setStringProperty`` で設定し
   **公開メソッド ``commitValue()`` を ``invokeMethod`` で叩いて確定を模す**（Spix は
   実テキスト入力 = ``editingFinished`` を発火できない＝Phase 6 Task 52 / Phase 8 Task T-D と同手法）。
   確定で対応変数が更新され、Trend の delegate が ``seriesValues``（VariableStore から組む）を
   再評価 → HmiTrend が ``onSeriesValuesChanged`` で全系列を 1 点ずつ push する。
   **系列 A だけ / 系列 B だけ更新する手順を交互に走らせ、更新した系列の ``lastValueAt`` が
   その値へ追従し、両系列の ``sampleCountAt`` が増えること**を観測する（系列の独立性は
   lastValueAt が「直近にその系列へ書いた値」へ一致することで担保する）。

Canvas のピクセル検証はしない（offscreen で不可視）。観測は公開メソッドの返り値の
文字列化（``getStringProperty`` ではメソッドは読めないため ``invokeMethod`` の返り値）に限る。

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

# 2 系列のサンプル源変数（int）。各操作用 NumericField で値を書き換えると、同じ変数を
# series[i].variable に持つ Trend が seriesValues 経由で系列 i に取り込む。
_VAR_A = "sensorTemp"
_VAR_B = "sensorPressure"
_VAR_A_INITIAL = 10
_VAR_B_INITIAL = 20
_COLOR_A = "#4cc9f0"
_COLOR_B = "#f72585"
_LABEL_A = "Temp"
_LABEL_B = "Pressure"

# 系列ごとに「どちらの変数を・どの値で確定するか」の手順（系列を交互に動かして独立性を観測）。
#   各要素 = (系列 index, 書き込む値)
_SEQUENCE = [
    (0, 25),  # 系列 A（Temp）を 25 へ
    (1, 55),  # 系列 B（Pressure）を 55 へ
    (0, 40),  # 系列 A を 40 へ（B は変えない）
    (1, 70),  # 系列 B を 70 へ（A は変えない）
]

# Trend の点数（round-trip で保存 JSON に乗ることを assert する）。
_POINT_COUNT = 80
_Y_TICK_COUNT = 5


def _fixture_json() -> dict:
    """2 系列 Trend（showGrid/showLegend ON）+ 各変数の操作用 NumericField。"""
    return {
        "project": "Task 8B-E Trend multi-series E2E",
        "variables": [
            {"name": _VAR_A, "type": "int", "initial": _VAR_A_INITIAL},
            {"name": _VAR_B, "type": "int", "initial": _VAR_B_INITIAL},
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
                        "width": 360,
                        "height": 180,
                        "backgroundColor": "#0b1d2a",
                        "pointCount": _POINT_COUNT,
                        "yMin": 0,
                        "yMax": 100,
                        "showGrid": True,
                        "showLegend": True,
                        "yTickCount": _Y_TICK_COUNT,
                        "series": [
                            {"variable": _VAR_A, "color": _COLOR_A, "label": _LABEL_A},
                            {"variable": _VAR_B, "color": _COLOR_B, "label": _LABEL_B},
                        ],
                    },
                    {
                        "id": "feedA001",
                        "type": "NumericField",
                        "x": 40,
                        "y": 240,
                        "width": 160,
                        "height": 48,
                        "text": "0",
                        "bindings": [
                            {"property": "value", "variable": _VAR_A}
                        ],
                    },
                    {
                        "id": "feedB001",
                        "type": "NumericField",
                        "x": 220,
                        "y": 240,
                        "width": 160,
                        "height": 48,
                        "text": "0",
                        "bindings": [
                            {"property": "value", "variable": _VAR_B}
                        ],
                    },
                ],
            }
        ],
    }


def _extract_value(body: str, what: str) -> str:
    """XML-RPC レスポンスから <value> のスカラ文字列を取り出す。

    getStringProperty は型タグ無し / <string> で返るが、invokeMethod の返り値は
    Qt/AnyRPC が typed タグ（<i4>/<int>/<double>/<boolean>/<string>）を付けて返す。
    どの型タグでも中身の文字列を取り出せるよう、既知のスカラ型タグを剥がす
    （既存 E2E が string 専用だった正規表現を typed 返り値へ一般化）。
    """
    m = re.search(r"<value>\s*(.*?)\s*</value>", body, re.DOTALL)
    if not m:
        raise RuntimeError(
            f"Failed to extract {what}. Response head: {body[:300]!r}"
        )
    inner = m.group(1).strip()
    tag = re.match(
        r"<(i4|int|double|boolean|string)>(.*?)</\1>", inner, re.DOTALL
    )
    if tag:
        inner = tag.group(2).strip()
    return inner


def _get_str_property(url: str, path: str, prop: str) -> str:
    body = call_method(url, "getStringProperty", path, prop)
    return _extract_value(body, f"{prop} from {path}")


def _invoke_int(url: str, path: str, method: str, args: list) -> int:
    """sampleCountAt(i) のような int を返す公開メソッドを invokeMethod で呼ぶ。"""
    body = call_method(url, "invokeMethod", path, method, args)
    if "<fault>" in body:
        raise RuntimeError(f"{method}{args} fault. Body: {body[:500]!r}")
    return int(float(_extract_value(body, f"{method}{args} on {path}")))


def _invoke_num(url: str, path: str, method: str, args: list) -> float:
    """lastValueAt(i) のような数値を返す公開メソッドを invokeMethod で呼ぶ。"""
    body = call_method(url, "invokeMethod", path, method, args)
    if "<fault>" in body:
        raise RuntimeError(f"{method}{args} fault. Body: {body[:500]!r}")
    return float(_extract_value(body, f"{method}{args} on {path}"))


def _exists_and_visible(url: str, path: str) -> bool:
    body = call_method(url, "existsAndVisible", path)
    return "<boolean>1</boolean>" in body


def _invoke_save_to(url: str, save_path: str) -> bool:
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
        call_method(url, "waitForItem", f"{_EDITOR_WIN}/widget_trend001", 3000)
        for wid in ("widget_trend001", "widget_feedA001", "widget_feedB001"):
            if not _exists_and_visible(url, f"{_EDITOR_WIN}/{wid}"):
                raise RuntimeError(f"Editor did not load fixture {wid}")

        if not _invoke_save_to(url, save_path):
            err = call_method(url, "getErrors")
            raise RuntimeError(
                f"saveTo returned false for {save_path!r}. Errors: {err[:500]!r}"
            )

    if not os.path.isfile(save_path):
        raise RuntimeError(f"saved JSON not found: {save_path}")


def _assert_saved_json(save_path: str) -> None:
    """保存 JSON に Trend / 2 系列 / 凡例フラグが乗っていることを直接検証する。"""
    with open(save_path, encoding="utf-8") as f:
        doc = json.load(f)

    problems = []

    variables = {v.get("name"): v for v in doc.get("variables", [])}
    for vn in (_VAR_A, _VAR_B):
        if vn not in variables:
            problems.append(f"variable {vn!r} missing in saved JSON")
        elif variables[vn].get("type") != "int":
            problems.append(
                f"variable {vn!r} type={variables[vn].get('type')!r} != 'int'"
            )

    widgets = doc["screens"][0]["widgets"]

    trend = next((w for w in widgets if w.get("id") == "trend001"), None)
    if trend is None:
        raise RuntimeError(f"trend001 not found in saved JSON: {save_path}")
    if trend.get("type") != "Trend":
        problems.append(f"trend001 type={trend.get('type')!r} != 'Trend'")
    if trend.get("showLegend") is not True:
        problems.append(f"trend001 showLegend={trend.get('showLegend')!r} != True")
    if trend.get("showGrid") is not True:
        problems.append(f"trend001 showGrid={trend.get('showGrid')!r} != True")
    if trend.get("yTickCount") != _Y_TICK_COUNT:
        problems.append(
            f"trend001 yTickCount={trend.get('yTickCount')!r} != {_Y_TICK_COUNT!r}"
        )

    series = trend.get("series")
    if not isinstance(series, list) or len(series) != 2:
        problems.append(
            f"trend001 series should be a 2-item list, got {series!r}"
        )
    else:
        expected = [
            (_VAR_A, _COLOR_A, _LABEL_A),
            (_VAR_B, _COLOR_B, _LABEL_B),
        ]
        for idx, (var, color, label) in enumerate(expected):
            s = series[idx]
            if s.get("variable") != var:
                problems.append(
                    f"series[{idx}].variable={s.get('variable')!r} != {var!r}"
                )
            if s.get("color") != color:
                problems.append(
                    f"series[{idx}].color={s.get('color')!r} != {color!r}"
                )
            if s.get("label") != label:
                problems.append(
                    f"series[{idx}].label={s.get('label')!r} != {label!r}"
                )

    for wid, var in (("feedA001", _VAR_A), ("feedB001", _VAR_B)):
        feeder = next((w for w in widgets if w.get("id") == wid), None)
        if feeder is None:
            problems.append(f"{wid} (control NumericField) missing in saved JSON")
            continue
        if feeder.get("type") != "NumericField":
            problems.append(f"{wid} type={feeder.get('type')!r} != 'NumericField'")
        fbind = next((b for b in feeder.get("bindings", [])
                      if b.get("property") == "value"), None)
        if fbind is None or fbind.get("variable") != var:
            problems.append(f"{wid} value binding to {var!r} missing/mismatched")

    if problems:
        raise RuntimeError("saved JSON Trend multi mismatch: " + "; ".join(problems))


def _phase2_simulator_multi(simulator_binary: str, port: int, save_path: str) -> None:
    """Simulator を ``--open`` で起動し、系列ごとの独立サンプリングを観測する。"""
    with spix_app(simulator_binary, port, extra_args=("--open", save_path)) as url:
        trend = f"{_SIM_WIN}/widget_trend001/hmiTrend"
        # NumericField は root（HmiNumericField, objectName "hmiNumericField"）を指す。
        # commitValue() / 系列メソッドはいずれも root に対して invoke する
        # （test_trend_live / test_numeric_input と同じ参照粒度）。
        feeders = {
            0: f"{_SIM_WIN}/widget_feedA001/hmiNumericField",
            1: f"{_SIM_WIN}/widget_feedB001/hmiNumericField",
        }
        for p in (trend, feeders[0], feeders[1]):
            call_method(url, "waitForItem", p, 3000)
        for wid in ("widget_trend001", "widget_feedA001", "widget_feedB001"):
            if not _exists_and_visible(url, f"{_SIM_WIN}/{wid}"):
                raise RuntimeError(
                    f"simulator missing {wid}. JSON: {save_path}"
                )

        # 系列数が 2 であることを確認する（series 2 件が描画側で実効系列になっている）。
        series_count = int(_get_str_property(url, trend, "seriesCount"))
        if series_count != 2:
            raise RuntimeError(
                f"Trend seriesCount={series_count} != 2 (multi-series not applied)"
            )

        # 各系列の初期サンプル数を記録（live:true で初回バインド評価分が乗りうるので増分で観測）。
        prev_counts = {
            0: _invoke_int(url, trend, "sampleCountAt", [0]),
            1: _invoke_int(url, trend, "sampleCountAt", [1]),
        }
        # 各系列へ「最後に書いた値」を追跡し、毎ステップ両系列の lastValueAt を期待表と
        # 突き合わせて系列の独立性（取り違え無し）を担保する。初期値は変数初期値。
        expected_per_series = {0: float(_VAR_A_INITIAL), 1: float(_VAR_B_INITIAL)}

        for series_idx, value in _SEQUENCE:
            feeder = feeders[series_idx]
            typed = str(value)
            call_method(url, "setStringProperty", feeder, "text", typed)
            body = call_method(url, "invokeMethod", feeder, "commitValue", [])
            if "<fault>" in body:
                raise RuntimeError(
                    f"commitValue invokeMethod fault for series {series_idx} "
                    f"value {typed!r}. Body: {body[:500]!r}"
                )

            expected_last = float(value)
            # seriesValues 変化で全系列が 1 点ずつ push される（onSeriesValuesChanged）。
            # よって両系列の sampleCount が増え、更新した系列の lastValue が新値へ追従する。
            deadline = time.monotonic() + 3.0
            ok = False
            cur_counts = dict(prev_counts)
            last_updated = None
            while time.monotonic() < deadline:
                cur_counts[0] = _invoke_int(url, trend, "sampleCountAt", [0])
                cur_counts[1] = _invoke_int(url, trend, "sampleCountAt", [1])
                last_updated = _invoke_num(url, trend, "lastValueAt", [series_idx])
                if (cur_counts[series_idx] > prev_counts[series_idx]
                        and last_updated == expected_last):
                    ok = True
                    break
                time.sleep(0.05)

            if not ok:
                raise RuntimeError(
                    f"series {series_idx} commit {typed!r}: "
                    f"sampleCountAt({series_idx})={cur_counts[series_idx]} "
                    f"(prev {prev_counts[series_idx]}), "
                    f"lastValueAt({series_idx})={last_updated!r} != {expected_last!r}"
                )

            # 系列の独立性：更新した系列の lastValue は新値、他系列は「その系列に最後に
            # 書いた値」のまま（取り違えなら他系列が今回値へ動く）。両系列の lastValueAt を
            # 期待表（最後に各系列へ書いた値）と突き合わせる。値表は重複しない（25/40 と
            # 55/70）ので、取り違えれば必ず不一致になる。
            expected_per_series[series_idx] = expected_last
            for sidx, exp in expected_per_series.items():
                actual = _invoke_num(url, trend, "lastValueAt", [sidx])
                if actual != exp:
                    raise RuntimeError(
                        f"series independence broken after writing {value} to series "
                        f"{series_idx}: lastValueAt({sidx})={actual!r} != expected "
                        f"{exp!r} (each series must track only its own variable)"
                    )

            prev_counts = dict(cur_counts)


def main() -> int:
    """fixture 生成 → Editor round-trip 保存 → JSON 検証 → Simulator 系列独立観測。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor-binary", required=True)
    parser.add_argument("--simulator-binary", required=True)
    parser.add_argument("--editor-port", type=int, default=9876)
    parser.add_argument("--simulator-port", type=int, default=9877)
    args = parser.parse_args()

    fixture_path = ""
    save_path = ""
    try:
        fd, fixture_path = tempfile.mkstemp(prefix="hmi_task8be_fixture_", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(_fixture_json(), f, ensure_ascii=False, indent=2)

        fd2, save_path = tempfile.mkstemp(prefix="hmi_task8be_saved_", suffix=".json")
        os.close(fd2)
        os.unlink(save_path)

        _phase1_editor_roundtrips(
            args.editor_binary, args.editor_port, fixture_path, save_path
        )
        _assert_saved_json(save_path)
        _phase2_simulator_multi(
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
        "OK: editor round-trips Trend/2-series/showLegend -> saved JSON -> "
        "simulator commitValue drives each series variable independently -> "
        "Trend takes per-series live samples (sampleCountAt(i) increases, "
        "lastValueAt(i) follows the value written to that series)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
