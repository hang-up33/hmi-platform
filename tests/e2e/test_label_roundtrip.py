"""Phase 5 Task 49: Label の round-trip + binding を検証する cross-app E2E。

Phase 5 で追加した **Label（表示専用 Widget）** が、Editor の保存経路を通って
Simulator まで届き、`HmiLabel`（``objectName: "hmiLabel"``）として正しく描画される
ことを検証する。Button 用の test_style_roundtrip / test_action_roundtrip の Label 版。

検証スコープ：

1. **Editor 段**：Label を 2 件持つ JSON（静的 Label + binding Label）と変数定義を
   Editor に ``--open`` で読み込ませ、``saveTo`` で別パスへ保存する。Editor の
   **load → snapshotModel → ProjectIo.save** が ``type:"Label"`` / 文字スタイル /
   bindings / variables を round-trip することを検証する。
2. **JSON 直接検証**：保存 JSON に Label（``type:"Label"`` + ``text`` + ``textColor``）・
   binding・変数が乗っていることを Python で直接 assert する（Spix 非依存の
   authoritative チェック）。
3. **Simulator 段**：保存 JSON を Simulator に ``--open`` で読み込ませ、
   - **静的 Label**（``lbl_title``）：``HmiLabel`` の ``text`` / ``textColor`` が
     JSON 値どおりに描画される（静的 round-trip）。
   - **binding Label**（``lbl_status``）：``text`` バインディングが変数 ``statusVar``
     （初期 ``"BOUND"``）へ追従し、静的 ``text`` ``"STATIC"`` ではなく ``"BOUND"`` が
     描画される（binding を Simulator で追従確認＝既存 ``boundValue`` 経路の再利用）。
   いずれも ``getStringProperty`` で観測する。

**Label は表示専用**＝クリックアクションを持たないため、test_action_roundtrip のような
実クリックでの状態遷移は見ない（binding の「読み」だけを検証する）。

Spix v0.14 制約・回避策は test_style_roundtrip.py / 既存 E2E と同方針：
- レスポンスは expat を経由しない正規表現で抽出（Homebrew Python の ``_pyexpat`` 回避）。
- 値の真偽は **保存 JSON を Python で直接 assert** することでも担保する。

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

# 静的 Label（lbl_title）：text / textColor が round-trip して描画される。
# textColor は HmiLabel の resolved 既定 "#1d3557" とあえて別値にし、伝播失敗時の
# フォールバックと取り違えないようにする（test_style_roundtrip と同じ考え方）。
_TITLE_TEXT = "TITLE"
_TITLE_COLOR = "#2a9d8f"

# binding Label（lbl_status）：静的 text は "STATIC" だが、text バインディングで
# 変数 statusVar（初期 "BOUND"）へ追従するため、Simulator では "BOUND" が描画される。
_STATIC_TEXT = "STATIC"
_VAR_NAME = "statusVar"
_VAR_INITIAL = "BOUND"


def _fixture_json() -> dict:
    """Label 2 件（静的 + binding）と変数定義を持つ最小プロジェクト。"""
    return {
        "project": "Task 49 Label E2E",
        "variables": [
            {"name": _VAR_NAME, "type": "string", "initial": _VAR_INITIAL},
        ],
        "screens": [
            {
                "name": "Main",
                "widgets": [
                    {
                        "id": "lbl_title",
                        "type": "Label",
                        "x": 60,
                        "y": 40,
                        "width": 320,
                        "height": 50,
                        "text": _TITLE_TEXT,
                        "textColor": _TITLE_COLOR,
                        "fontSize": 28,
                    },
                    {
                        "id": "lbl_status",
                        "type": "Label",
                        "x": 60,
                        "y": 120,
                        "width": 320,
                        "height": 40,
                        "text": _STATIC_TEXT,
                        "bindings": [
                            {"property": "text", "variable": _VAR_NAME}
                        ],
                    },
                ],
            }
        ],
    }


def _get_str_property(url: str, path: str, prop: str) -> str:
    """getStringProperty のレスポンスから文字列値を取り出す（test_style_roundtrip と同方針）。"""
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


def _phase1_editor_roundtrips_labels(editor_binary: str, port: int,
                                     fixture_path: str, save_path: str) -> None:
    """Editor に Label 入り fixture を ``--open`` で読ませ ``saveTo`` で保存する。

    既存 Widget の編集のみで ``addWidget`` を呼ばないため Repeater 再生成の
    巻き戻り罠（CLAUDE.md「Spix（E2E）統合の罠」節）は発生しない。
    """
    with spix_app(editor_binary, port, extra_args=("--open", fixture_path)) as url:
        call_method(url, "waitForItem", f"{_EDITOR_WIN}/widget_lbl_title", 3000)
        if not _exists_and_visible(url, f"{_EDITOR_WIN}/widget_lbl_title"):
            raise RuntimeError("Editor did not load fixture widget_lbl_title")

        if not _invoke_save_to(url, save_path):
            err = call_method(url, "getErrors")
            raise RuntimeError(
                f"saveTo returned false for {save_path!r}. Errors: {err[:500]!r}"
            )

    if not os.path.isfile(save_path):
        raise RuntimeError(f"saved JSON not found: {save_path}")


def _assert_saved_json_has_labels(save_path: str) -> None:
    """保存 JSON に Label（type/text/textColor）・binding・変数が乗っていることを直接検証する。"""
    with open(save_path, encoding="utf-8") as f:
        doc = json.load(f)

    problems = []

    variables = doc.get("variables", [])
    var = next((v for v in variables if v.get("name") == _VAR_NAME), None)
    if var is None:
        problems.append(f"variable {_VAR_NAME!r} missing in saved JSON")
    elif str(var.get("initial")) != _VAR_INITIAL:
        problems.append(f"variable initial={var.get('initial')!r} != {_VAR_INITIAL!r}")

    widgets = doc["screens"][0]["widgets"]

    title = next((w for w in widgets if w.get("id") == "lbl_title"), None)
    if title is None:
        raise RuntimeError(f"lbl_title not found in saved JSON: {save_path}")
    if title.get("type") != "Label":
        problems.append(f"lbl_title type={title.get('type')!r} != 'Label'")
    if title.get("text") != _TITLE_TEXT:
        problems.append(f"lbl_title text={title.get('text')!r} != {_TITLE_TEXT!r}")
    if title.get("textColor") != _TITLE_COLOR:
        problems.append(f"lbl_title textColor={title.get('textColor')!r} != {_TITLE_COLOR!r}")

    status = next((w for w in widgets if w.get("id") == "lbl_status"), None)
    if status is None:
        raise RuntimeError(f"lbl_status not found in saved JSON: {save_path}")
    if status.get("type") != "Label":
        problems.append(f"lbl_status type={status.get('type')!r} != 'Label'")
    bindings = status.get("bindings", [])
    bind = next((b for b in bindings if b.get("property") == "text"), None)
    if bind is None:
        problems.append("text binding missing on lbl_status")
    elif bind.get("variable") != _VAR_NAME:
        problems.append(f"binding variable={bind.get('variable')!r} != {_VAR_NAME!r}")

    if problems:
        raise RuntimeError("saved JSON label mismatch: " + "; ".join(problems))


def _phase2_simulator_renders_labels(simulator_binary: str, port: int, save_path: str) -> None:
    """Simulator を ``--open`` で起動し、HmiLabel の静的描画 + binding 追従を確認する。"""
    with spix_app(simulator_binary, port, extra_args=("--open", save_path)) as url:
        title_wrapper = f"{_SIM_WIN}/widget_lbl_title"
        title_label = f"{title_wrapper}/hmiLabel"
        status_label = f"{_SIM_WIN}/widget_lbl_status/hmiLabel"

        call_method(url, "waitForItem", title_wrapper, 3000)
        if not _exists_and_visible(url, title_wrapper):
            raise RuntimeError(f"simulator missing widget_lbl_title. JSON: {save_path}")
        call_method(url, "waitForItem", title_label, 3000)
        call_method(url, "waitForItem", status_label, 3000)

        problems = []

        # 静的 Label：text / textColor が JSON 値どおりに描画される。
        title_text = _get_str_property(url, title_label, "text")
        title_color = _get_str_property(url, title_label, "textColor")
        if title_text != _TITLE_TEXT:
            problems.append(f"lbl_title text={title_text!r} != {_TITLE_TEXT!r}")
        if title_color != _TITLE_COLOR:
            problems.append(f"lbl_title textColor={title_color!r} != {_TITLE_COLOR!r}")

        # binding Label：text が変数 statusVar の初期値 "BOUND" へ追従している
        # （静的 text "STATIC" ではない）。
        status_text = _get_str_property(url, status_label, "text")
        if status_text != _VAR_INITIAL:
            problems.append(
                f"lbl_status text={status_text!r} != {_VAR_INITIAL!r} "
                "(text binding did not follow variable)"
            )

        if problems:
            raise RuntimeError("simulator HmiLabel mismatch: " + "; ".join(problems))


def main() -> int:
    """fixture 生成 → Editor round-trip 保存 → JSON 検証 → Simulator 描画確認を順に走らせる。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor-binary", required=True)
    parser.add_argument("--simulator-binary", required=True)
    parser.add_argument("--editor-port", type=int, default=9876)
    parser.add_argument("--simulator-port", type=int, default=9877)
    args = parser.parse_args()

    fixture_path = ""
    save_path = ""
    try:
        fd, fixture_path = tempfile.mkstemp(prefix="hmi_task49_fixture_", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(_fixture_json(), f, ensure_ascii=False, indent=2)

        fd2, save_path = tempfile.mkstemp(prefix="hmi_task49_saved_", suffix=".json")
        os.close(fd2)
        os.unlink(save_path)

        _phase1_editor_roundtrips_labels(
            args.editor_binary, args.editor_port, fixture_path, save_path
        )
        _assert_saved_json_has_labels(save_path)
        _phase2_simulator_renders_labels(
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
        "OK: editor round-trips Label (type/text/textColor/binding) -> saved JSON -> "
        f"simulator renders HmiLabel text={_TITLE_TEXT!r} textColor={_TITLE_COLOR!r} "
        f"and bound text follows {_VAR_NAME!r} -> {_VAR_INITIAL!r}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
