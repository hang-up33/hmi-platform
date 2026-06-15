"""Phase 6-B Task 55: NumericField 拡張（real 型 + 数値範囲 clamp）の cross-app E2E。

Phase 6 Task 52（``test_numeric_input.py``）は **int 変数のみ**の typed-write を観測した。
本テストは Phase 6-B の締めとして、Task 53（real 変数型）/ 54（数値範囲 min/max）で
足した 2 軸を初めて E2E で観測する：

1. **real typed-write**：``temperature``（real）変数に ``value`` binding で結ばれた
   NumericField で、``"36.5"`` を確定すると real 変数が ``36.5`` に更新され、同じ変数を
   ``text`` binding で読む観測用 Label が ``"36.5"`` へ追従する。int では切り捨てられる
   小数が **real では保たれる**ことを見る。
2. **範囲 clamp**：max=100 を持つ NumericField（int 変数 ``level``、初期 0）で範囲外
   ``"150"`` を確定すると、**clamp された境界値 ``100``** が変数へ書かれ、観測用 Label が
   ``"100"`` へ追従する（拒否でなく境界へ丸める＝requirements FR-NUM-05）。

検証スタイルは Phase 6 Task 52 を踏襲する：
- **Editor 段**：fixture JSON を ``--open`` → ``saveTo`` で round-trip 保存し、保存 JSON を
  Python で直接 assert（``type:"real"`` 変数 / ``maxValue`` キー / binding が乗ること）。
  追加 UI（変数型 ComboBox / インスペクタ範囲項目）は Spix で駆動できないため手動スクショ担保。
- **Simulator 段（主眼）**：保存 JSON を ``--open`` で読ませ、Spix は実テキスト入力
  （``editingFinished``）を発火できないため ``setStringProperty(.../hmiNumericField, "text", ...)``
  で入力テキストを設定し **公開メソッド ``commitValue()`` を ``invokeMethod`` で叩いて確定を模す**。
  これで real path の小数保持 / clamp 後の境界値 write が ``writeBoundValue`` 経由で変数へ
  反映され、観測用 Label の追従を ``getStringProperty`` で見る。

real の入力文字列は locale 非依存にするため **ASCII の小数点 ``"36.5"`` 固定**にする
（``.claude/rules/numeric-field-real-locale.md``：real は C locale = ASCII 小数点で統一）。

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

# real typed-write 軸：temperature(real, 初期 20.0)。"36.5" を確定 → 小数が保たれる。
_REAL_VAR = "temperature"
_REAL_INITIAL = 20.0
_REAL_TYPED = "36.5"

# clamp 軸：level(int, 初期 0)。max=100 の NumericField に "150" を入れて clamp → 100。
_CLAMP_VAR = "level"
_CLAMP_INITIAL = 0
_CLAMP_MAX = 100.0
_CLAMP_TYPED = "150"
_CLAMP_RESULT = "100"


def _fixture_json() -> dict:
    """real 変数 + clamp 用 int 変数 + それぞれの NumericField / 観測用 Label。"""
    return {
        "project": "Task 55 NumericField extend E2E",
        "variables": [
            {"name": _REAL_VAR, "type": "real", "initial": _REAL_INITIAL},
            {"name": _CLAMP_VAR, "type": "int", "initial": _CLAMP_INITIAL},
        ],
        "screens": [
            {
                "name": "Main",
                "widgets": [
                    # --- real typed-write 軸 ---
                    {
                        "id": "realNum",
                        "type": "NumericField",
                        "x": 60,
                        "y": 40,
                        "width": 160,
                        "height": 48,
                        "text": "0",
                        "bindings": [{"property": "value", "variable": _REAL_VAR}],
                    },
                    {
                        "id": "realEcho",
                        "type": "Label",
                        "x": 60,
                        "y": 100,
                        "width": 160,
                        "height": 40,
                        "text": "?",
                        "bindings": [{"property": "text", "variable": _REAL_VAR}],
                    },
                    # --- clamp 軸（max=100 の NumericField）---
                    {
                        "id": "clampNum",
                        "type": "NumericField",
                        "x": 60,
                        "y": 180,
                        "width": 160,
                        "height": 48,
                        "text": "0",
                        "maxValue": _CLAMP_MAX,
                        "bindings": [{"property": "value", "variable": _CLAMP_VAR}],
                    },
                    {
                        "id": "clampEcho",
                        "type": "Label",
                        "x": 60,
                        "y": 240,
                        "width": 160,
                        "height": 40,
                        "text": "?",
                        "bindings": [{"property": "text", "variable": _CLAMP_VAR}],
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


def _phase1_editor_roundtrips(editor_binary: str, port: int,
                              fixture_path: str, save_path: str) -> None:
    """Editor に fixture を ``--open`` で読ませ ``saveTo`` で保存する。

    addWidget を呼ばないため Repeater 再生成の巻き戻り罠は発生しない
    （test_numeric_input / test_action_roundtrip と同方針）。
    """
    with spix_app(editor_binary, port, extra_args=("--open", fixture_path)) as url:
        call_method(url, "waitForItem", f"{_EDITOR_WIN}/widget_realNum", 3000)
        if not _exists_and_visible(url, f"{_EDITOR_WIN}/widget_realNum"):
            raise RuntimeError("Editor did not load fixture widget_realNum")
        if not _exists_and_visible(url, f"{_EDITOR_WIN}/widget_clampNum"):
            raise RuntimeError("Editor did not load fixture widget_clampNum")

        if not _invoke_save_to(url, save_path):
            err = call_method(url, "getErrors")
            raise RuntimeError(
                f"saveTo returned false for {save_path!r}. Errors: {err[:500]!r}"
            )

    if not os.path.isfile(save_path):
        raise RuntimeError(f"saved JSON not found: {save_path}")


def _assert_saved_json(save_path: str) -> None:
    """保存 JSON に real 変数型 / maxValue / value binding が乗っていることを直接検証する。"""
    with open(save_path, encoding="utf-8") as f:
        doc = json.load(f)

    problems = []

    variables = doc.get("variables", [])
    real_var = next((v for v in variables if v.get("name") == _REAL_VAR), None)
    if real_var is None:
        problems.append(f"variable {_REAL_VAR!r} missing in saved JSON")
    elif real_var.get("type") != "real":
        problems.append(f"variable {_REAL_VAR!r} type={real_var.get('type')!r} != 'real'")

    clamp_var = next((v for v in variables if v.get("name") == _CLAMP_VAR), None)
    if clamp_var is None:
        problems.append(f"variable {_CLAMP_VAR!r} missing in saved JSON")
    elif clamp_var.get("type") != "int":
        problems.append(f"variable {_CLAMP_VAR!r} type={clamp_var.get('type')!r} != 'int'")

    widgets = doc["screens"][0]["widgets"]

    real_num = next((w for w in widgets if w.get("id") == "realNum"), None)
    if real_num is None:
        raise RuntimeError(f"realNum not found in saved JSON: {save_path}")
    if real_num.get("type") != "NumericField":
        problems.append(f"realNum type={real_num.get('type')!r} != 'NumericField'")
    rbind = next((b for b in real_num.get("bindings", [])
                  if b.get("property") == "value"), None)
    if rbind is None or rbind.get("variable") != _REAL_VAR:
        problems.append("realNum value binding missing/mismatched")

    clamp_num = next((w for w in widgets if w.get("id") == "clampNum"), None)
    if clamp_num is None:
        raise RuntimeError(f"clampNum not found in saved JSON: {save_path}")
    # presence フラグ方式：maxValue キーの有無で未指定を表す（Task 54）。
    if "maxValue" not in clamp_num:
        problems.append("clampNum maxValue key missing (presence flag round-trip broken)")
    elif float(clamp_num.get("maxValue")) != _CLAMP_MAX:
        problems.append(f"clampNum maxValue={clamp_num.get('maxValue')!r} != {_CLAMP_MAX!r}")
    # min は未指定なので minValue キーは書かれてはいけない（presence 片側のみ）。
    if "minValue" in clamp_num:
        problems.append("clampNum minValue key present though unspecified (presence leak)")
    cbind = next((b for b in clamp_num.get("bindings", [])
                  if b.get("property") == "value"), None)
    if cbind is None or cbind.get("variable") != _CLAMP_VAR:
        problems.append("clampNum value binding missing/mismatched")

    if problems:
        raise RuntimeError("saved JSON NumericField-extend mismatch: " + "; ".join(problems))


def _commit_and_wait(url: str, numeric: str, echo: str,
                     typed: str, expected: str, what: str) -> None:
    """入力テキストを設定 → commitValue() invoke → 観測 Label が expected へ追従するのを待つ。

    Spix は editingFinished を発火できないため、内部 TextField.text を直接セットして
    公開メソッド commitValue() を叩き「ユーザー入力 → 確定」を模す（Phase 6 Task 52 と同手法）。
    """
    call_method(url, "setStringProperty", numeric, "text", typed)
    body = call_method(url, "invokeMethod", numeric, "commitValue", [])
    if "<fault>" in body:
        raise RuntimeError(f"{what}: commitValue invokeMethod fault. Body: {body[:500]!r}")

    deadline = time.monotonic() + 3.0
    after = ""
    while time.monotonic() < deadline:
        after = _get_str_property(url, echo, "text")
        if after == expected:
            break
        time.sleep(0.05)
    if after != expected:
        raise RuntimeError(
            f"{what}: after commit echo text={after!r} != {expected!r} "
            "(typed-write/clamp did not produce expected value, or binding did not follow)"
        )


def _phase2_simulator(simulator_binary: str, port: int, save_path: str) -> None:
    """Simulator を ``--open`` で起動し、real 小数保持 / clamp 境界 write を観測する。"""
    with spix_app(simulator_binary, port, extra_args=("--open", save_path)) as url:
        # NumericField は root（HmiNumericField, objectName "hmiNumericField"）を指す。
        # setStringProperty(root, "text", …) は root.text を書き、宣言バインド
        # `field.text: root._displayText(root.text)` 経由で内部 TextField へ伝わる。
        # commitValue() は **root のメソッド**なので invoke も root に対して行う
        # （内部 numericTextField を指すと commitValue が無く確定が走らない＝Phase 6
        #  test_numeric_input と同じ参照粒度に揃える）。
        real_numeric = f"{_SIM_WIN}/widget_realNum/hmiNumericField"
        real_echo = f"{_SIM_WIN}/widget_realEcho/hmiLabel"
        clamp_numeric = f"{_SIM_WIN}/widget_clampNum/hmiNumericField"
        clamp_echo = f"{_SIM_WIN}/widget_clampEcho/hmiLabel"
        for p in (real_numeric, real_echo, clamp_numeric, clamp_echo):
            call_method(url, "waitForItem", p, 3000)
        if not _exists_and_visible(url, f"{_SIM_WIN}/widget_realNum"):
            raise RuntimeError(f"simulator missing widget_realNum. JSON: {save_path}")
        if not _exists_and_visible(url, f"{_SIM_WIN}/widget_clampNum"):
            raise RuntimeError(f"simulator missing widget_clampNum. JSON: {save_path}")

        # 読み：real 初期値が小数固定表記で追従（"20" ＝ _toFixedNotation(20.0)）。
        # 観測用 Label は変数を String(v) で表示するため初期 20.0 → "20"。
        initial_real_echo = _get_str_property(url, real_echo, "text")
        if initial_real_echo != "20":
            raise RuntimeError(
                f"initial real echo text={initial_real_echo!r} != '20' "
                "(text binding did not follow real variable initial)"
            )

        # real typed-write：小数 "36.5" が保たれて変数 → Label に届く（int 切り捨てではない）。
        _commit_and_wait(url, real_numeric, real_echo,
                         _REAL_TYPED, _REAL_TYPED, "real typed-write")

        # clamp：max=100 の NumericField に "150" → clamp で 100 が変数へ書かれ Label 追従。
        _commit_and_wait(url, clamp_numeric, clamp_echo,
                         _CLAMP_TYPED, _CLAMP_RESULT, "range clamp")


def main() -> int:
    """fixture 生成 → Editor round-trip 保存 → JSON 検証 → Simulator real/clamp を順に走らせる。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor-binary", required=True)
    parser.add_argument("--simulator-binary", required=True)
    parser.add_argument("--editor-port", type=int, default=9876)
    parser.add_argument("--simulator-port", type=int, default=9877)
    args = parser.parse_args()

    fixture_path = ""
    save_path = ""
    try:
        fd, fixture_path = tempfile.mkstemp(prefix="hmi_task55_fixture_", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(_fixture_json(), f, ensure_ascii=False, indent=2)

        fd2, save_path = tempfile.mkstemp(prefix="hmi_task55_saved_", suffix=".json")
        os.close(fd2)
        os.unlink(save_path)

        _phase1_editor_roundtrips(
            args.editor_binary, args.editor_port, fixture_path, save_path
        )
        _assert_saved_json(save_path)
        _phase2_simulator(
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
        "OK: editor round-trips real var + maxValue -> saved JSON -> "
        f"simulator commitValue keeps real decimal {_REAL_TYPED!r} and clamps "
        f"{_CLAMP_TYPED!r} -> {_CLAMP_RESULT!r} (max={_CLAMP_MAX!r}) "
        "via writeBoundValue + text binding follow"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
