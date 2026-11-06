#!/usr/bin/env python3
"""ヒーロー GIF 生成: atlas-dashboard-demo.json を段階的に組み上げる中間 JSON を作り、
各段を Editor (offscreen) で撮影 -> Pillow で 1 本の GIF に合成する。

"デモ画面を Editor で作っていく様子" を README ヒーローとして見せるためのツール。

前提:
  - Qt 導入済み + cmake --build build 済み (scripts/web/setup.sh)
  - pip install Pillow
使い方:
  python3 scripts/web/build-hero-gif.py
出力:
  Docs/screenshots/hero-frames/frame_NN.png (中間フレーム)
  Docs/screenshots/editor.gif (ヒーロー GIF)
"""
import copy
import json
import os
import shutil
import subprocess
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEMO = os.path.join(ROOT, "Docs/samples/atlas-dashboard-demo.json")
FRAME_DIR = os.path.join(ROOT, "Docs/screenshots/hero-frames")
OUT_GIF = os.path.join(ROOT, "Docs/screenshots/editor.gif")
CAPTURE = os.path.join(ROOT, "scripts/capture-app-screenshot-linux.sh")

# 各マイルストーンで "ここまで widget を置いた" 状態を見せる累積カット数 (中間段階)。
# atlas-dashboard-demo.json の widgets 配列は組み上げ順 (地とヘッダ -> 警報バナー ->
# 生産 -> 設備の状態 -> 操作 -> トレンド -> 温度メーター -> 長押し起動) に並んでいるので
# 前方スライスで段階を作る。
# 最終フレームは実行時に widget 総数へ自動で揃えるため (main 参照)、末尾値の手動更新は不要。
MILESTONES = [3, 7, 22, 40, 49, 53, 57]


def main():
    """中間フレームを撮影し editor.gif に合成する。"""
    bash = shutil.which("bash") or "/bin/bash"
    with open(DEMO, encoding="utf-8") as f:
        demo = json.load(f)
    widgets = demo["screens"][0]["widgets"]
    # 最終マイルストーンは常に widget 総数に揃える (前方スライスなので、demo に
    # Widget を足したら最終フレームへ自動反映される)。総数以上の固定値は捨てて
    # 重複を避ける。これで MILESTONES の手動更新漏れでもヒーローが欠けない。
    milestones = [m for m in MILESTONES if m < len(widgets)] + [len(widgets)]
    os.makedirs(FRAME_DIR, exist_ok=True)

    png_paths = []
    for i, count in enumerate(milestones):
        frame = copy.deepcopy(demo)
        frame["screens"][0]["widgets"] = widgets[:count]
        frame_json = os.path.join(FRAME_DIR, f"frame_{i:02d}.json")
        frame_png = os.path.join(FRAME_DIR, f"frame_{i:02d}.png")
        with open(frame_json, "w", encoding="utf-8") as f:
            json.dump(frame, f, ensure_ascii=False, indent=2)
        print(f"[{i+1}/{len(milestones)}] widgets={count} 撮影 -> {frame_png}")
        subprocess.run(
            [bash, CAPTURE, "-a", "editor", "-o", frame_png, "-j", frame_json, "-d", "700"],
            check=True, cwd=ROOT,
        )
        png_paths.append(frame_png)

    frames = []
    for p in png_paths:
        with Image.open(p) as img:
            frames.append(img.convert("RGB"))
    # 各フレーム 700ms、完成 (最終) は 2500ms 保持して余韻を残す。
    durations = [700] * (len(frames) - 1) + [2500]
    frames[0].save(
        OUT_GIF, save_all=True, append_images=frames[1:],
        duration=durations, loop=0, optimize=True,
    )
    size_kb = os.path.getsize(OUT_GIF) / 1024
    print(f"GIF 生成完了: {OUT_GIF} ({size_kb:.0f} KB, {len(frames)} frames)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
