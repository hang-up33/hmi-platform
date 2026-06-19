#!/usr/bin/env bash
# Stop hook: UI(QML 本体)に変更があるのに README ヒーロー画像
# (Docs/screenshots/editor.gif / simulator.png) が未更新ならリマインドする。
#
# 背景: README スクショ同期ルールは元々 screenshot-capture スキルの末尾にだけ
# 書かれており、オンデマンドの skill 内に埋もれて自動では効かなかった
# (Task 33〜41 で editor.png / simulator.png が古いまま残った)。
# この Stop hook と path-scoped rule (.claude/rules/readme-screenshot-sync.md) の
# 二段構えで「見た目が変わったら README スクショを撮り直す」を効かせる。
#
# 方針: ハード block はしない。見た目不変のロジック変更や撮影不能な環境では
# Claude が一度確認して停止できるよう、stop_hook_active で多重発火を防ぐ
# (= 一回限りの注意喚起)。

input=$(cat 2>/dev/null || true)

# 既に stop hook 起因で継続中なら再発火させない(無限ループ防止)
case "$input" in
  *'"stop_hook_active": true'* | *'"stop_hook_active":true'*) exit 0 ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0

# 比較基準: origin/main があればそれとの merge-base、無ければコミット済み差分は見ない
base=""
if git rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
  base=$(git merge-base origin/main HEAD 2>/dev/null || true)
fi

# 変更ファイル集合(ブランチのコミット済み + 作業ツリー + ステージ)
changed=$(
  {
    [ -n "$base" ] && git diff --name-only "$base"...HEAD 2>/dev/null
    git diff --name-only HEAD 2>/dev/null
    git diff --name-only --cached 2>/dev/null
  } | sort -u
)
[ -z "$changed" ] && exit 0

# UI 本体(QML, tests 除く)の変更を、影響するヒーロースクショ別に判定する。
# tests/ 配下(QML テスト)は見た目に無関係なので除外。
#   - Editor の見た目    : Editor/ の QML、または共有 Widget(Shared/Widgets) の QML
#   - Simulator の見た目 : Simulator/ または Runtime/ の QML、または共有 Widget の QML
# Shared/Widgets(= HmiButton 等)は両アプリの描画に効くため editor / simulator 両方に影響する。
# Editor 専用 UI(インスペクタ / ツールバー等)の変更では simulator.png は対象外＝誤発火を避ける。
ui_files=$(printf '%s\n' "$changed" | grep -E '\.qml$' | grep -Ev '/tests/' || true)
[ -z "$ui_files" ] && exit 0

editor_ui=$(printf '%s\n' "$ui_files" | grep -E '^(Editor/|Shared/Widgets/)' || true)
sim_ui=$(printf '%s\n' "$ui_files" | grep -E '^(Simulator/|Runtime/|Shared/Widgets/)' || true)
[ -z "$editor_ui" ] && [ -z "$sim_ui" ] && exit 0

# 影響するアプリのヒーロースクショが「同じ変更集合に」含まれているか個別に確認する。
# CodeRabbit PR #86 指摘(Major): 片方だけ更新で通過すると、もう片方の未同期を見逃す。
# よって editor / simulator を 2 ファイル個別に存在確認し、AND で同期済み判定する。
has_editor_gif=0
has_sim_png=0
# Editor ヒーローは README が表示する「組み上げる様子」のアニメ GIF(editor.gif、
# build-hero-gif.py で再生成)。README 参照先に合わせ editor.gif を必須にする
# (旧静止 editor.png は README 非参照＝撮り直しても GIF は古いままなので同期済みにしない。Codex PR #135 指摘)。
printf '%s\n' "$changed" | grep -Eq '^Docs/screenshots/editor\.gif$' && has_editor_gif=1
printf '%s\n' "$changed" | grep -Eq '^Docs/screenshots/simulator\.png$' && has_sim_png=1

missing=""
[ -n "$editor_ui" ] && [ "$has_editor_gif" -eq 0 ] && missing="${missing} Docs/screenshots/editor.gif"
[ -n "$sim_ui" ] && [ "$has_sim_png" -eq 0 ] && missing="${missing} Docs/screenshots/simulator.png"

# 影響する全スクショが更新済みなら同期済みとみなす
[ -z "$missing" ] && exit 0

{
  echo "⚠️ README スクショ未同期の可能性があります。"
  echo "QML(UI 本体)に変更がありますが、対応するヒーロースクショが更新されていません:"
  for f in $missing; do echo "  - $f"; done
  cat <<'MSG'

- 見た目が変わるなら: 上記を撮り直して同じコミットに含めてください
  (editor.gif は python3 scripts/web/build-hero-gif.py、simulator.png は
   screenshot-capture スキル。詳細は .claude/rules/readme-screenshot-sync.md)。
- 見た目が変わらない(内部ロジック/リファクタのみ)、または撮影不能な環境なら:
  その旨を一言述べてそのまま終了して構いません(この注意は一度きりで、次の停止はブロックしません)。
MSG
} >&2
exit 2
