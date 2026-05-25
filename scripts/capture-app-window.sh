#!/usr/bin/env bash
# macOS で起動中アプリのウィンドウだけをキャプチャする。
#
# 使い方:
#   scripts/capture-app-window.sh <process-name> <output-path>
#
# 例:
#   ./build/Editor/hmi_editor.app/Contents/MacOS/hmi_editor &
#   sleep 2
#   scripts/capture-app-window.sh hmi_editor Docs/screenshots/task-4-button.png
#
# 仕組み:
#   1. Swift で CGWindowListCopyWindowInfo を呼び、対象プロセスのウィンドウ ID を取得
#   2. screencapture -l<wid> でそのウィンドウだけ取得（Retina 倍率は自動考慮）
#
# 必要な macOS 権限:
#   - 画面収録（システム設定 > プライバシーとセキュリティ > 画面収録）
#     screencapture コマンドに必要。Claude Code（または親ターミナル）を許可。
#   - アクセシビリティ権限は不要（System Events を使わないため）。
#
# 終了コード:
#   0  成功（標準出力に出力パスを出す）
#   1  対象アプリにウィンドウが無い／取得失敗
set -euo pipefail

APP="${1:?process name required}"
OUT="${2:?output path required}"

mkdir -p "$(dirname "$OUT")"

WID=$(swift - "$APP" <<'SWIFT'
import Cocoa
guard CommandLine.arguments.count >= 2 else { exit(2) }
let appName = CommandLine.arguments[1]
let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in windows {
    guard let owner = w[kCGWindowOwnerName as String] as? String, owner == appName else { continue }
    guard let layer = w[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
    guard let num = w[kCGWindowNumber as String] as? Int else { continue }
    print(num)
    exit(0)
}
exit(1)
SWIFT
) || { echo "error: no on-screen window for process '$APP'" >&2; exit 1; }

screencapture -l"$WID" -o "$OUT"
echo "$OUT"
