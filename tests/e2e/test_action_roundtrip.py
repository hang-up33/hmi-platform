"""Phase 4 拡張 Task 43: アクション / バインディングの「動き」を検証する cross-app E2E。

これまでの E2E（test_style_roundtrip ほか）は**静的な round-trip**（保存した値が
そのまま描画される）を見ていた。本テストはトラック B（変数 / アクション / バインディング）
の締めとして、**実際にクリックして状態が遷移する「動き」** を初めて E2E で観測する：

1. **Editor 段**：変数・アクション・バインディングを持つ JSON を Editor に ``--open`` で
   読み込ませ、``saveTo`` で別パスへ保存する。Editor の **load → snapshotModel → ProjectIo.save**
   がアクションサブシステム（``variables`` / ``actions`` / ``bindings``）を round-trip
   することを検証する。
2. **JSON 直接検証**：保存 JSON に変数定義・``btn001`` のアクション・バインディングが
   乗っていることを Python で直接 assert する（Spix 非依存の authoritative チェック）。
3. **Simulator 段（新規ポイント）**：保存 JSON を Simulator に ``--open`` で読み込ませ、
   ``HmiButton`` を **Spix の ``mouseClick`` で実際にクリック** → ``runClickActions`` が
   ``setVariable`` を実行 → ``label`` 変数が更新 → ``text`` バインディングが追従、を
   ``getStringProperty`` で観測する（初期 ``"OFF"`` → クリック後 ``"ON"``）。

**なぜ Editor 段はアクション編集 UI を駆動せず fixture を ``--open`` するのか**：
アクション / バインディングは ``var`` 配列、変数定義は Project レベル
（``rootWindow.projectVariables``）であり、Spix の ``setStringProperty`` で
直接設定できない。さらにアクション編集 UI は ``ComboBox`` で、Spix は
``onActivated`` / ``onTextEdited`` を実ユーザー入力でのみ発火させる制約があり
駆動できない（test_style_roundtrip がインスペクタ ``TextField`` を駆動しないのと同じ
理由）。よって「Editor がアクションデータを **保存経路で正しく round-trip する**」ことを
fixture の ``--open`` → ``saveTo`` → JSON 直接 assert で担保し、アクション編集 UI 自体は
手動スクショ（``Docs/screenshots/task-40-action-inspector.png`` 系）で担保する。
**「動き」（クリック → 変数 → 追従）の検証は Simulator 段の実クリックで行う**のが本 E2E の主眼。

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
import time

from harness import call_method, spix_app

_EDITOR_WIN = "hmiEditorWindow"
_SIM_WIN = "hmiSimulatorWindow"

# アクション / バインディングのデモ値。
#   - 変数 label（string）: 初期 "OFF"
#   - btn001: text バインディング（label 追従）＋ setVariable アクション（label="ON"）
# クリックで label が "OFF" → "ON" に変わり、text バインディングが追従するのを観測する。
_VAR_NAME = "label"
_VAR_INITIAL = "OFF"
_ACTION_VALUE = "ON"


def _fixture_json() -> dict:
    """変数・アクション・バインディングを持つ最小プロジェクト（btn001 1 件）。"""
    return {
        "project": "Task 43 Action E2E",
        "variables": [
            {"name": _VAR_NAME, "type": "string", "initial": _VAR_INITIAL},
        ],
        "screens": [
            {
                "name": "Main",
                "widgets": [
                    {
                        "id": "btn001",
                        "type": "Button",
                        "x": 60,
                        "y": 60,
                        "width": 220,
                        "height": 80,
                        "text": "static",
                        "actions": [
                            {
                                "trigger": "onClick",
                                "op": "setVariable",
                                "target": _VAR_NAME,
                                "value": _ACTION_VALUE,
                            }
                        ],
                        "bindings": [
                            {"property": "text", "variable": _VAR_NAME}
                        ],
                    }
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


def _phase1_editor_roundtrips_actions(editor_binary: str, port: int,
                                      fixture_path: str, save_path: str) -> None:
    """Editor に fixture を ``--open`` で読ませ ``saveTo`` で保存する。

    btn001 1 件のみで ``addWidget`` を呼ばないため Repeater 再生成の巻き戻り罠
    （CLAUDE.md「Spix（E2E）統合の罠」節）は発生しない。
    """
    with spix_app(editor_binary, port, extra_args=("--open", fixture_path)) as url:
        call_method(url, "waitForItem", f"{_EDITOR_WIN}/widget_btn001", 3000)
        if not _exists_and_visible(url, f"{_EDITOR_WIN}/widget_btn001"):
            raise RuntimeError("Editor did not load fixture widget_btn001")

        if not _invoke_save_to(url, save_path):
            err = call_method(url, "getErrors")
            raise RuntimeError(
                f"saveTo returned false for {save_path!r}. Errors: {err[:500]!r}"
            )

    if not os.path.isfile(save_path):
        raise RuntimeError(f"saved JSON not found: {save_path}")


def _assert_saved_json_has_actions(save_path: str) -> None:
    """保存 JSON に変数 / アクション / バインディングが乗っていることを直接検証する。"""
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
    btn = next((w for w in widgets if w.get("id") == "btn001"), None)
    if btn is None:
        raise RuntimeError(f"btn001 not found in saved JSON: {save_path}")

    actions = btn.get("actions", [])
    act = next((a for a in actions if a.get("op") == "setVariable"), None)
    if act is None:
        problems.append("setVariable action missing on btn001")
    else:
        if act.get("target") != _VAR_NAME:
            problems.append(f"action target={act.get('target')!r} != {_VAR_NAME!r}")
        if act.get("value") != _ACTION_VALUE:
            problems.append(f"action value={act.get('value')!r} != {_ACTION_VALUE!r}")

    bindings = btn.get("bindings", [])
    bind = next((b for b in bindings if b.get("property") == "text"), None)
    if bind is None:
        problems.append("text binding missing on btn001")
    elif bind.get("variable") != _VAR_NAME:
        problems.append(f"binding variable={bind.get('variable')!r} != {_VAR_NAME!r}")

    if problems:
        raise RuntimeError("saved JSON action mismatch: " + "; ".join(problems))


def _phase2_simulator_runs_action(simulator_binary: str, port: int, save_path: str) -> None:
    """Simulator を ``--open`` で起動し、クリック → 変数更新 → text 追従 を観測する。"""
    with spix_app(simulator_binary, port, extra_args=("--open", save_path)) as url:
        wrapper = f"{_SIM_WIN}/widget_btn001"
        button = f"{wrapper}/hmiButton"
        call_method(url, "waitForItem", wrapper, 3000)
        if not _exists_and_visible(url, wrapper):
            raise RuntimeError(f"simulator missing widget_btn001. JSON: {save_path}")
        call_method(url, "waitForItem", button, 3000)

        # 初期：text は静的値 "static" ではなく label の初期値 "OFF" に追従している。
        initial = _get_str_property(url, button, "text")
        if initial != _VAR_INITIAL:
            raise RuntimeError(
                f"initial text={initial!r} != {_VAR_INITIAL!r} "
                "(binding did not follow variable initial)"
            )

        # 新規ポイント：実ボタンをクリック → onClick アクション（setVariable）実行
        # → label = "ON" → text バインディングが追従する。
        # 反映は同期的だが、CI 負荷時の false negative を避けるため固定 wait ではなく
        # 短いポーリング（最大 3 秒）で期待値到達を待つ（CodeRabbit PR #87 Major 指摘）。
        call_method(url, "mouseClick", button)
        deadline = time.monotonic() + 3.0
        after = ""
        while time.monotonic() < deadline:
            after = _get_str_property(url, button, "text")
            if after == _ACTION_VALUE:
                break
            time.sleep(0.05)
        if after != _ACTION_VALUE:
            raise RuntimeError(
                f"after click text={after!r} != {_ACTION_VALUE!r} "
                "(action did not update variable, or binding did not follow)"
            )


def main() -> int:
    """fixture 生成 → Editor round-trip 保存 → JSON 検証 → Simulator クリック実行を順に走らせる。"""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--editor-binary", required=True)
    parser.add_argument("--simulator-binary", required=True)
    parser.add_argument("--editor-port", type=int, default=9876)
    parser.add_argument("--simulator-port", type=int, default=9877)
    args = parser.parse_args()

    # mkstemp が万一失敗しても finally で NameError にならないよう先に初期化する
    # （CodeRabbit PR #87 軽微指摘）。save_path は mkstemp 後に一旦 unlink して
    # 「saveTo が実際に生成したか」を _phase1 の isfile チェックで担保できるようにする
    # （空の mkstemp ファイルを残すと saveTo 失敗を取りこぼす）。
    fixture_path = ""
    save_path = ""
    try:
        fd, fixture_path = tempfile.mkstemp(prefix="hmi_task43_fixture_", suffix=".json")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump(_fixture_json(), f, ensure_ascii=False, indent=2)

        fd2, save_path = tempfile.mkstemp(prefix="hmi_task43_saved_", suffix=".json")
        os.close(fd2)
        os.unlink(save_path)

        _phase1_editor_roundtrips_actions(
            args.editor_binary, args.editor_port, fixture_path, save_path
        )
        _assert_saved_json_has_actions(save_path)
        _phase2_simulator_runs_action(
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
        "OK: editor round-trips action/binding -> saved JSON -> "
        f"simulator click drives {_VAR_NAME} {_VAR_INITIAL!r} -> {_ACTION_VALUE!r} "
        "via setVariable + text binding"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
