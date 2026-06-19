#!/usr/bin/env python3
"""ヒーロー GIF 生成: atlas-dashboard-demo.json を段階的に組み上げる中間 JSON を作り、
各段を Editor（offscreen）で撮影 → Pillow で 1 本の GIF に合成する。

「デモ画面を Editor で作っていく様子」を README ヒーローとして見せるためのツール。

前提:
  - Qt 導入済み + cmake --build build 済み（scripts/web/setup.sh）
  - pip install Pillow
使い方:
  python3 scripts/web/build-hero-gif.py
出力:
  Docs/screenshots/hero-frames/frame_NN.png（中間フレーム）
  Docs/screenshots/editor.gif（ヒーロー GIF）
"""
import json
import os
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DEMO = os.path.join(ROOT, "Docs/samples/atlas-dashboard-demo.json")
FRAME_DIR = os.path.join(ROOT, "Docs/screenshots/hero-frames")
OUT_GIF = os.path.join(ROOT, "Docs/screenshots/editor.gif")
CAPTURE = os.path.join(ROOT, "scripts/capture-app-screenshot-linux.sh")

# 各マイルストーンで「ここまで widget を置いた」状態を見せる累積カット数。
# atlas-dashboard-demo.json の widgets 配列は組み上げ順（ヘッダ→ステータス→
# KPI タイル→機械ステータス盤→操作→トレンド）に並んでいるので前方スライスで段階を作る。
MILESTONES = [1, 3, 6, 9, 12, 15, 18, 21, 33, 35, 38, 40]


def main():
    with open(DEMO, encoding="utf-8") as f:
        demo = json.load(f)
    widgets = demo["screens"][0]["widgets"]
    os.makedirs(FRAME_DIR, exist_ok=True)

    png_paths = []
    for i, count in enumerate(MILESTONES):
        frame = json.loads(json.dumps(demo))
        frame["screens"][0]["widgets"] = widgets[:count]
        frame_json = os.path.join(FRAME_DIR, f"frame_{i:02d}.json")
        frame_png = os.path.join(FRAME_DIR, f"frame_{i:02d}.png")
        with open(frame_json, "w", encoding="utf-8") as f:
            json.dump(frame, f, ensure_ascii=False, indent=2)
        print(f"[{i+1}/{len(MILESTONES)}] widgets={count} 撮影 -> {frame_png}")
        subprocess.run(
            ["bash", CAPTURE, "-a", "editor", "-o", frame_png, "-j", frame_json, "-d", "700"],
            check=True, cwd=ROOT,
        )
        png_paths.append(frame_png)

    from PIL import Image
    frames = [Image.open(p).convert("RGB") for p in png_paths]
    # 各フレーム 700ms、完成（最終）は 2500ms 保持して余韻を残す。
    durations = [700] * (len(frames) - 1) + [2500]
    frames[0].save(
        OUT_GIF, save_all=True, append_images=frames[1:],
        duration=durations, loop=0, optimize=True,
    )
    size_kb = os.path.getsize(OUT_GIF) / 1024
    print(f"GIF 生成完了: {OUT_GIF} ({size_kb:.0f} KB, {len(frames)} frames)")


if __name__ == "__main__":
    sys.exit(main())
