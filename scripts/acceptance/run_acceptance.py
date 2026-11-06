#!/usr/bin/env python3
"""録画付き受け入れ試験。

仮想ディスプレイ（Xvfb）の上で Editor と Simulator を操作し、画面を録画する。
クリックとドラッグは xdotool で本物のマウスを動かして行う。
動画には、カーソルの位置に赤い輪を重ねる。ボタンを押している間は塗りつぶしの丸になる。
部品の位置を調べる・値を読む・保存する、の 3 つは Spix で行う。
手順ごとに合否を判定してスクショを撮り、字幕入りの動画と PR に貼る Markdown の報告を作る。

使い方:
    python3 scripts/acceptance/run_acceptance.py \\
        --editor-binary build/Editor/hmi_editor \\
        --simulator-binary build/Simulator/hmi_simulator \\
        --out build/acceptance

出力（--out の下）:
    acceptance.mp4   字幕入りの録画
    report.md        手順・期待結果・合否・動画の時刻・スクショの一覧
    shots/*.png      手順ごとのスクショ

必要なもの: Xvfb、xdotool、ffmpeg（libass 付き）、日本語フォント（字幕に Noto Sans CJK JP を使う）、
HMI_ENABLE_E2E=ON でビルドしたアプリ。
Linux の Xvfb で Qt の xcb を使うので、libxcb-cursor0 などの xcb 系ライブラリも要る。

判定は 2 段で行う。
1. このスクリプトが、値（プロパティ・保存した JSON）を機械的に確かめる。
2. Claude が shots/ のスクショと動画を見て、表示の崩れや文字化けがないかを確かめ、
   report.md の「所見」欄を書く。
"""

from __future__ import annotations

import argparse
import datetime
import json
import os
import re
import shutil
import socket
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "tests", "e2e"))

from harness import call_method, spix_app  # noqa: E402

SCREEN = "1280x800"
FPS = 15
PAUSE = 1.2          # 手順と手順の間の待ち時間（秒）。人が動画で追えるようにする
ED_WIN = "hmiEditorWindow"
SIM_WIN = "hmiSimulatorWindow"


# ---------------------------------------------------------------------------
# 試験に使う画面（ボタン 1 つとラベル 1 つ。ボタンを押すと変数が変わり、ラベルが追従する）
# ---------------------------------------------------------------------------
def fixture() -> dict:
    return {
        "project": "Acceptance Test",
        "variables": [{"name": "state", "type": "string", "initial": "STOPPED"}],
        "screens": [{
            "name": "Main",
            "widgets": [
                {"id": "bg", "type": "Button", "x": 0, "y": 0, "width": 800, "height": 600, "text": "",
                 "backgroundColor": "#d9dbde", "borderWidth": 0, "radius": 0},
                {"id": "title", "type": "Label", "x": 40, "y": 30, "width": 720, "height": 40,
                 "text": "ACCEPTANCE TEST", "textColor": "#1f2328", "fontSize": 20, "fontBold": True,
                 "hAlign": "left", "vAlign": "middle"},
                {"id": "status", "type": "Label", "x": 40, "y": 110, "width": 400, "height": 60,
                 "text": "static", "textColor": "#1f2328", "fontSize": 28, "fontBold": True,
                 "hAlign": "left", "vAlign": "middle",
                 "bindings": [{"property": "text", "variable": "state"}]},
                {"id": "btnStart", "type": "Button", "x": 40, "y": 200, "width": 180, "height": 60,
                 "text": "START", "backgroundColor": "#c9cdd2", "textColor": "#1f2328", "fontSize": 18,
                 "fontBold": True, "borderColor": "#7d838b", "borderWidth": 1, "radius": 2,
                 "actions": [{"trigger": "onClick", "op": "setVariable", "target": "state", "value": "RUNNING"}]},
                {"id": "btnStop", "type": "Button", "x": 240, "y": 200, "width": 180, "height": 60,
                 "text": "STOP", "backgroundColor": "#c9cdd2", "textColor": "#1f2328", "fontSize": 18,
                 "fontBold": True, "borderColor": "#7d838b", "borderWidth": 1, "radius": 2,
                 "actions": [{"trigger": "onClick", "op": "setVariable", "target": "state", "value": "STOPPED"}]},
            ],
        }],
    }


# ---------------------------------------------------------------------------
# 補助関数
# ---------------------------------------------------------------------------
def get_prop(url: str, path: str, prop: str) -> str:
    body = call_method(url, "getStringProperty", path, prop)
    m = re.search(r"<value>(?:<string>)?(.*?)(?:</string>)?</value>", body, re.DOTALL)
    return m.group(1).strip() if m else ""


def visible(url: str, path: str) -> bool:
    return "<boolean>1</boolean>" in call_method(url, "existsAndVisible", path)


def wait_item(url: str, path: str, timeout_ms: int = 5000) -> bool:
    return "<fault>" not in call_method(url, "waitForItem", path, timeout_ms)


def bbox(url: str, path: str):
    """部品の画面上の位置と大きさ (x, y, 幅, 高さ) を返す。"""
    nums = re.findall(r"<double>([-0-9.eE]+)</double>", call_method(url, "getBoundingBox", path))
    box = tuple(float(n) for n in nums)
    # Spix は部品が見つからないとき、エラーではなく大きさ 0 の枠を返す
    if len(box) != 4 or (box[2] == 0 and box[3] == 0):
        raise RuntimeError("位置を取れなかった: %s" % path)
    return box


def center(url: str, path: str):
    x, y, w, h = bbox(url, path)
    return int(x + w / 2), int(y + h / 2)


class Mouse:
    """xdotool で本物のマウスを動かす。人が目で追えるよう、少しずつ動かす。

    動かした位置とボタンの状態を時刻つきで記録する。
    録画の後、この記録から動画にカーソルの印を重ねる（write_cursor_ass）。
    """

    STEPS = 30
    STEP_SEC = 0.03

    def __init__(self):
        self.clock = None    # 録画開始からの秒数を返す関数。main で Recorder.now を入れる
        self.down = False
        self.pos = (0, 0)    # 最後に動かした位置
        self.log = []        # (時刻, x, y, ボタンを押しているか)

    def _run(self, *args):
        subprocess.run(["xdotool", *args], check=True)

    def _mark(self, x: int, y: int):
        self.pos = (x, y)
        if self.clock:
            self.log.append((self.clock(), x, y, self.down))

    def _press(self, pressed: bool):
        self._run("mousedown" if pressed else "mouseup", "1")
        self.down = pressed
        self._mark(*self.pos)

    def where(self):
        out = subprocess.run(["xdotool", "getmouselocation"], capture_output=True, text=True, check=True).stdout
        m = re.search(r"x:(\d+) y:(\d+)", out)
        return int(m.group(1)), int(m.group(2))

    def move(self, x: int, y: int):
        x0, y0 = self.where()
        for i in range(1, self.STEPS + 1):
            px = round(x0 + (x - x0) * i / self.STEPS)
            py = round(y0 + (y - y0) * i / self.STEPS)
            self._run("mousemove", str(px), str(py))
            self._mark(px, py)
            time.sleep(self.STEP_SEC)

    def click(self, x: int, y: int):
        self.move(x, y)
        time.sleep(0.3)
        self._press(True)
        time.sleep(0.3)      # 押している間の印が動画で見えるよう、少し押したままにする
        self._press(False)

    def drag(self, x0: int, y0: int, x1: int, y1: int, remaining=None):
        """(x0, y0) で押して (x1, y1) まで動かし、離す。

        ドラッグは閾値を超えてから部品が動き出すので、その分だけ部品は手前で止まる。
        remaining を渡すと、ボタンを押したまま「残りの距離」(dx, dy) を測り直して足す。
        """
        self.move(x0, y0)
        time.sleep(0.2)
        self._press(True)
        try:
            self.move(x1, y1)
            for _ in range(3):
                if remaining is None:
                    break
                time.sleep(0.1)
                dx, dy = remaining()
                if dx == 0 and dy == 0:
                    break
                x, y = self.where()
                self.move(int(x + dx), int(y + dy))
            time.sleep(0.2)
        finally:
            # 途中で例外が出ても、ボタンを押したまま次の手順へ進まないようにする
            self._press(False)


MOUSE = Mouse()


def free_port() -> int:
    """空いている TCP ポートを OS に選ばせる（既存の e2e テストや手元のアプリと衝突しないように）。"""
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def cell(text) -> str:
    """Markdown の表のセルに入れられる形にする。"""
    return str(text).replace("|", "\\|").replace("\n", " ")


def wait_prop(url: str, path: str, prop: str, want: str, timeout: float = 3.0) -> str:
    deadline = time.monotonic() + timeout
    got = ""
    while time.monotonic() < deadline:
        got = get_prop(url, path, prop)
        if got == want:
            break
        time.sleep(0.05)
    return got


class Recorder:
    """仮想ディスプレイ全体を録画する。手順の時刻はこの開始時刻からの秒数で記録する。"""

    def __init__(self, path: str, display: str):
        self.path = path
        self.display = display
        self.log_path = path + ".log"
        self.proc = None
        self.t0 = 0.0
        self.wall0 = 0.0

    def start(self):
        with open(self.log_path, "w") as log:
            self.proc = subprocess.Popen(
                ["ffmpeg", "-y", "-nostats", "-loglevel", "info", "-f", "x11grab", "-video_size", SCREEN,
                 "-framerate", str(FPS), "-i", self.display, "-c:v", "libx264", "-preset", "veryfast",
                 "-pix_fmt", "yuv420p", self.path],
                stdin=subprocess.PIPE, stdout=subprocess.DEVNULL, stderr=log)
        time.sleep(0.5)
        if self.proc.poll() is not None:
            raise RuntimeError("ffmpeg の録画が始まらなかった（終了コード %s）" % self.proc.returncode)
        # 手順とマウスの時刻はここを 0 秒として記録する。
        # 録画の実際の開始とはずれるので、録画の後で lag() の分だけ補正する
        self.t0 = time.monotonic()
        self.wall0 = time.time()

    def now(self) -> float:
        return time.monotonic() - self.t0

    def lag(self) -> float:
        """録画の最初のコマが、t0 から何秒後に撮られたかを返す（前なら負の値）。

        x11grab は最初のコマの時刻を UNIX 時刻で「start: 秒」とログに出す。それと t0 の時刻を比べる。
        読み取れないときは警告を出して 0 を返す。
        """
        try:
            with open(self.log_path, errors="replace") as f:
                m = re.search(r"x11grab.*?\n.*?start: ([0-9.]+)", f.read())
            if m:
                return float(m.group(1)) - self.wall0
        except OSError:
            pass
        print("警告: 録画の開始時刻を読めなかった。字幕と印がずれることがある", file=sys.stderr)
        return 0.0

    def stop(self):
        if not self.proc:
            return
        try:
            self.proc.communicate(b"q", timeout=15)
        except subprocess.TimeoutExpired:
            self.proc.kill()
            self.proc.wait()


def snapshot(display: str, path: str) -> bool:
    r = subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "x11grab", "-video_size", SCREEN,
                        "-i", display, "-frames:v", "1", path])
    return r.returncode == 0


def fmt_time(t: float) -> str:
    return "%02d:%02d" % (int(t) // 60, int(t) % 60)


def srt_time(t: float) -> str:
    ms = int(round(t * 1000))
    return "%02d:%02d:%02d,%03d" % (ms // 3600000, ms // 60000 % 60, ms // 1000 % 60, ms % 1000)


# ---------------------------------------------------------------------------
# 試験の本体
# ---------------------------------------------------------------------------
class Run:
    def __init__(self, out: str, rec: Recorder):
        self.out = out
        self.rec = rec
        self.results = []
        os.makedirs(os.path.join(out, "shots"), exist_ok=True)

    def step(self, acc: str, action: str, expected: str, fn):
        """1 手順を実行する。fn は (合否, 実際の結果) を返す。"""
        no = len(self.results) + 1
        start = self.rec.now()
        try:
            ok, actual = fn()
        except Exception as e:  # 試験の失敗として記録し、続きの手順も流す
            ok, actual = False, "例外: %s" % e
        time.sleep(PAUSE)
        shot = "shots/%02d.png" % no
        if not snapshot(self.rec.display, os.path.join(self.out, shot)):
            shot = "（スクショ無し）"
        end = self.rec.now()
        self.results.append(dict(no=no, acc=acc, action=action, expected=expected,
                                 ok=ok, actual=actual, start=start, end=end, shot=shot))
        print("%s %02d %s %s -> %s" % ("OK" if ok else "NG", no, acc, action, actual))


def scenario_editor(run: Run, editor: str, fixture_path: str, save_path: str):
    with spix_app(editor, free_port(), extra_args=("--open", fixture_path)) as url:
        btn = ED_WIN + "/widget_btnStart"

        def opened():
            names = ("btnStart", "btnStop", "status")
            missing = [n for n in names
                       if not (wait_item(url, ED_WIN + "/widget_" + n) and visible(url, ED_WIN + "/widget_" + n))]
            time.sleep(0.8)
            return not missing, ("3 つとも表示された" if not missing else "表示されない: " + ", ".join(missing))
        run.step("ACC-PRJ-005", "Editor でプロジェクトの JSON を開く", "START / STOP ボタンとラベルが表示される", opened)

        def move():
            # キャンバス上の位置の差だけ、画面上でもドラッグする（キャンバスは等倍で表示される）
            cx, cy = center(url, btn)
            dx = 60 - float(get_prop(url, btn, "x"))
            dy = 320 - float(get_prop(url, btn, "y"))
            MOUSE.drag(cx, cy, round(cx + dx), round(cy + dy),
                       remaining=lambda: (round(60 - float(get_prop(url, btn, "x"))),
                                          round(320 - float(get_prop(url, btn, "y")))))
            time.sleep(0.3)
            x, y = get_prop(url, btn, "x"), get_prop(url, btn, "y")
            return (x in ("60", "60.0") and y in ("320", "320.0")), "位置 (%s, %s)" % (x, y)
        run.step("ACC-EDT-001", "START ボタンを (60, 320) へドラッグする", "ボタンの位置が (60, 320) になる（保存される内容は手順 4 で確かめる）", move)

        def select():
            MOUSE.click(*center(url, btn))
            text = wait_prop(url, ED_WIN + "/inspectorTextField", "text", "START")
            return text == "START", "インスペクタの Text 欄 = %r" % text
        run.step("ACC-EDT-006", "START ボタンをクリックして選ぶ", "インスペクタの Text 欄に START が出る", select)

        def save():
            body = call_method(url, "invokeMethod", ED_WIN, "saveTo", [save_path])
            ok = "<boolean>1</boolean>" in body and os.path.isfile(save_path)
            detail = "保存できなかった"
            if ok:
                with open(save_path, encoding="utf-8") as f:
                    d = json.load(f)
                w = {x["id"]: x for x in d["screens"][0]["widgets"]}
                moved = w["btnStart"]["x"] == 60 and w["btnStart"]["y"] == 320
                act = (w["btnStart"].get("actions") or [{}])[0]
                kept = (act.get("op") == "setVariable" and act.get("target") == "state"
                        and act.get("value") == "RUNNING")
                ok = moved and kept
                detail = "保存した JSON: 位置 (%s, %s)、アクション %s" % (
                    w["btnStart"]["x"], w["btnStart"]["y"], "あり" if kept else "なし")
            return ok, detail
        run.step("ACC-EDT-004", "画面を保存する（ファイル選択画面を避けるため Spix で保存を呼ぶ）", "保存した JSON に新しい位置とアクションが残る", save)


def scenario_simulator(run: Run, simulator: str, save_path: str):
    with spix_app(simulator, free_port(), extra_args=("--open", save_path)) as url:
        label = SIM_WIN + "/widget_status/hmiLabel"
        start = SIM_WIN + "/widget_btnStart/hmiButton"
        stop = SIM_WIN + "/widget_btnStop/hmiButton"

        def opened():
            if not wait_item(url, label):
                return False, "ラベルが表示されない"
            time.sleep(0.8)
            text = get_prop(url, label, "text")
            return text == "STOPPED", "ラベル = %r" % text
        run.step("ACC-RUN-001", "Simulator で保存した JSON を開く", "ラベルが変数の初期値 STOPPED を表示する", opened)

        def press_start():
            MOUSE.click(*center(url, start))
            text = wait_prop(url, label, "text", "RUNNING")
            return text == "RUNNING", "ラベル = %r" % text
        run.step("ACC-WGT-002", "START ボタンを押す", "変数が RUNNING になり、ラベルが追従する", press_start)

        def press_stop():
            before = get_prop(url, label, "text")
            if before != "RUNNING":
                return False, "前提が成り立たない（押す前のラベル = %r。RUNNING のはず）" % before
            MOUSE.click(*center(url, stop))
            text = wait_prop(url, label, "text", "STOPPED")
            return text == "STOPPED", "ラベル = %r" % text
        run.step("ACC-WGT-003", "STOP ボタンを押す", "変数が STOPPED に戻り、ラベルが追従する", press_stop)


# ---------------------------------------------------------------------------
# 出力
# ---------------------------------------------------------------------------
def write_srt(results, path: str):
    with open(path, "w", encoding="utf-8") as f:
        for i, r in enumerate(results, 1):
            mark = "OK" if r["ok"] else "NG"
            f.write("%d\n%s --> %s\n期待値: %s\n結果: %s（%s）\n\n" % (
                i, srt_time(r["start"]), srt_time(r["end"]), r["expected"], mark, r["actual"]))


def _circle(r: int) -> str:
    """半径 r の円を ASS の描画命令で返す。左上を (0, 0) とする。"""
    k = round(r * 0.5523)
    d = 2 * r
    return ("m %d 0 b %d 0 %d %d %d %d b %d %d %d %d %d %d b %d %d 0 %d 0 %d b 0 %d %d 0 %d 0"
            % (r, r + k, d, r - k, d, r, d, r + k, r + k, d, r, d, r - k, d, r + k, r, r - k, r - k, r))


def write_cursor_ass(log, path: str):
    """マウスの記録から、カーソル位置に赤い丸を出す ASS 字幕を作る。

    普段は赤い輪、ボタンを押している間は大きい塗りつぶしの丸にする。
    """
    w, h = SCREEN.split("x")
    lines = ["[Script Info]", "ScriptType: v4.00+", "PlayResX: " + w, "PlayResY: " + h, "",
             "[V4+ Styles]",
             "Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, "
             "Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, "
             "Shadow, Alignment, MarginL, MarginR, MarginV, Encoding",
             "Style: C,Arial,20,&H00FFFFFF,&H00FFFFFF,&H002828C6,&H00000000,0,0,0,0,100,100,0,0,1,4,0,7,0,0,0,1",
             "", "[Events]",
             "Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text"]

    def ts(t):
        cs = max(0, int(round(t * 100)))
        return "%d:%02d:%02d.%02d" % (cs // 360000, cs // 6000 % 60, cs // 100 % 60, cs % 100)

    for i, (t, x, y, down) in enumerate(log):
        end = log[i + 1][0] if i + 1 < len(log) else t + 3600
        if end <= t:
            continue
        r = 22 if down else 16
        fill = r"\1c&H2828C6&\1a&H60&" if down else r"\1a&HFF&"
        lines.append("Dialogue: 0,%s,%s,C,,0,0,0,,{\\an7\\pos(%d,%d)%s\\p1}%s{\\p0}"
                     % (ts(t), ts(end), x - r, y - r, fill, _circle(r)))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def burn(raw: str, srt: str, out: str, cursor_ass: str):
    """字幕とカーソルの印を焼き込む。フィルタの書式が壊れないよう、ファイルはその場所から相対名で渡す。"""
    style = "FontName=Noto Sans CJK JP,FontSize=13,PrimaryColour=&H00FFFFFF,BackColour=&H99000000,BorderStyle=3,Outline=1,Shadow=0,MarginV=12"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", raw, "-vf",
                    "ass=%s,subtitles=%s:force_style='%s'" % (os.path.basename(cursor_ass), os.path.basename(srt), style), "-c:v", "libx264",
                    "-preset", "veryfast", "-pix_fmt", "yuv420p", out], check=True, cwd=os.path.dirname(srt))


def git_head() -> str:
    try:
        return subprocess.run(["git", "-C", ROOT, "rev-parse", "--short", "HEAD"],
                              capture_output=True, text=True, check=True).stdout.strip()
    except Exception:
        return "unknown"


def write_report(results, out: str, video: str):
    ok_n = sum(1 for r in results if r["ok"])
    lines = [
        "## 録画付き受け入れ試験の結果",
        "",
        "| 項目 | 内容 |",
        "|---|---|",
        "| 日時 | %s |" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M"),
        "| コミット | `%s` |" % git_head(),
        "| 環境 | Linux（Xvfb %s・Qt の xcb） |" % SCREEN,
        "| 結果 | **%d / %d 件 OK** |" % (ok_n, len(results)),
        "| 動画 | `%s`（手順ごとに字幕あり） |" % os.path.basename(video),
        "",
        "| # | 受け入れ条件 | 操作 | 期待結果 | 結果 | 実際の値 | 動画 | スクショ | 所見 |",
        "|---|---|---|---|---|---|---|---|---|",
    ]
    for r in results:
        lines.append("| %d | %s | %s | %s | %s | %s | %s | `%s` | （Claude が記入） |" % (
            r["no"], cell(r["acc"]), cell(r["action"]), cell(r["expected"]), "OK" if r["ok"] else "**NG**",
            cell(r["actual"]), fmt_time(r["start"]), cell(r["shot"])))
    lines += ["", "- 「結果」は値を機械的に確かめた判定。「所見」はスクショと動画を Claude が見た判定。"]
    with open(os.path.join(out, "report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


OUTPUT_NAMES = {"report.md", "acceptance.mp4", "shots"}


def safe_out_dir(out: str) -> bool:
    """消してよい出力先かを確かめる。既にあるなら、このスクリプトの出力だけが入っていること。"""
    forbidden = {os.path.abspath(p) for p in (ROOT, os.path.dirname(ROOT), os.path.expanduser("~"), "/")}
    if out in forbidden:
        return False
    if os.path.exists(out):
        if not os.path.isdir(out):
            return False
        if not set(os.listdir(out)) <= OUTPUT_NAMES:
            return False
    return True


def start_xvfb():
    """空いているディスプレイ番号で Xvfb を起動し、(プロセス, ":番号") を返す。"""
    r, w = os.pipe()
    proc = subprocess.Popen(["Xvfb", "-displayfd", str(w), "-screen", "0", SCREEN + "x24", "-nolisten", "tcp"],
                            pass_fds=(w,), stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    os.close(w)
    with os.fdopen(r) as f:
        num = f.readline().strip()
    if not num or proc.poll() is not None:
        proc.kill()
        raise RuntimeError("Xvfb を起動できなかった")
    return proc, ":" + num


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--editor-binary", required=True)
    ap.add_argument("--simulator-binary", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    for tool in ("Xvfb", "xdotool", "ffmpeg"):
        if not shutil.which(tool):
            print("%s が見つからない" % tool, file=sys.stderr)
            return 2
    out = os.path.abspath(args.out)
    if not safe_out_dir(out):
        print("--out には、リポジトリ直下・ホーム・ルート以外の専用ディレクトリを指定する: %s" % out,
              file=sys.stderr)
        return 2
    if os.path.exists(out):
        shutil.rmtree(out)
    os.makedirs(out)

    xvfb, display = start_xvfb()
    os.environ["DISPLAY"] = display
    os.environ["QT_QPA_PLATFORM"] = "xcb"
    try:
        with tempfile.TemporaryDirectory(prefix="hmi_acceptance_") as work:
            fixture_path = os.path.join(work, "fixture.json")
            save_path = os.path.join(work, "saved.json")
            with open(fixture_path, "w", encoding="utf-8") as f:
                json.dump(fixture(), f, ensure_ascii=False, indent=2)

            raw = os.path.join(work, "raw.mp4")
            rec = Recorder(raw, display)
            run = Run(out, rec)
            try:
                rec.start()
                MOUSE.clock = rec.now
                scenario_editor(run, args.editor_binary, fixture_path, save_path)
                scenario_simulator(run, args.simulator_binary, save_path)
            finally:
                rec.stop()

            # 記録した時刻を、動画の上の時刻へそろえる
            lag = rec.lag()
            print("録画の遅れ: %.2f 秒" % lag)
            for r in run.results:
                r["start"] = max(0.0, r["start"] - lag)
                r["end"] = max(0.0, r["end"] - lag)
            MOUSE.log = [(max(0.0, t - lag), x, y, d) for (t, x, y, d) in MOUSE.log]

            srt = os.path.join(work, "steps.srt")
            write_srt(run.results, srt)
            video = os.path.join(out, "acceptance.mp4")
            cursor_ass = os.path.join(work, "cursor.ass")
            write_cursor_ass(MOUSE.log, cursor_ass)
            burn(raw, srt, video, cursor_ass)
            write_report(run.results, out, video)
    finally:
        xvfb.terminate()
        try:
            xvfb.wait(5)
        except subprocess.TimeoutExpired:
            xvfb.kill()
            xvfb.wait()
    print("報告: %s" % os.path.join(out, "report.md"))
    print("動画: %s" % video)
    return 0 if all(r["ok"] for r in run.results) else 1


if __name__ == "__main__":
    sys.exit(main())
