#!/usr/bin/env bash
# Stop hook: UI(QML 本体)に変更があるのに README ヒーロースクショ
# (Docs/screenshots/editor.png / simulator.png) が未更新ならリマインドする。
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

# UI 本体(QML)の変更があるか。tests/ 配下(QML テスト)は見た目に無関係なので除外
ui=$(printf '%s\n' "$changed" | grep -E '\.qml$' | grep -Ev '/tests/' || true)
[ -z "$ui" ] && exit 0

# README ヒーロースクショが同じ変更集合に含まれていれば同期済みとみなす
if printf '%s\n' "$changed" | grep -Eq 'Docs/screenshots/(editor|simulator)\.png$'; then
  exit 0
fi

cat >&2 <<'MSG'
⚠️ README スクショ未同期の可能性があります。
QML(UI 本体)に変更がありますが Docs/screenshots/editor.png / simulator.png が更新されていません。

- 見た目が変わるなら: screenshot-capture スキルで editor.png / simulator.png を撮り直し、
  同じコミットに含めてください(詳細は .claude/rules/readme-screenshot-sync.md)。
- 見た目が変わらない(内部ロジック/リファクタのみ)、または撮影不能な環境なら:
  その旨を一言述べてそのまま終了して構いません(この注意は一度きりで、次の停止はブロックしません)。
MSG
exit 2
