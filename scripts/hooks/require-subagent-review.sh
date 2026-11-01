#!/usr/bin/env bash
# Stop hook: まとまった変更(origin/main との差分が一定量以上)があるのに、
# 現在の HEAD についてサブエージェントレビューが済んでいなければ、
# Claude を一度止めてレビューを促す。
#
# 済みの記録: `bash scripts/hooks/require-subagent-review.sh --record` を実行すると、
#   「HEAD の SHA + 作業ツリーの状態(未コミット差分・未追跡ファイル)」を
#   .git/subagent-reviewed に書く(git 管理外)。レビュー指摘を直した後に実行すること。
#   記録後に HEAD も作業ツリーも変わっていなければ、フックは何もしない。
# 規約: .claude/rules/feedback-subagent-review.md
#
# ループ防止: stop_hook_active が真なら何もしない(促しは 1 回限り)。
# 小さな変更(THRESHOLD 行未満)・差分なし・main 上で差分なしは対象外。


# 現在の状態: HEAD の SHA と、作業ツリー(追跡ファイルの差分 + 未追跡ファイルの名前と内容)のハッシュ。
# ハッシュは git hash-object で計算する(macOS 標準に sha1sum が無いため、git だけに依存させる)。
# 計算に失敗したら非ゼロで返し、呼び出し側で扱う(空のハッシュを記録しない)。
current_state() {
  local head wt f
  head=$(git rev-parse HEAD 2>/dev/null) || return 1
  # pipefail: パイプ左側(git diff / hash-object)の失敗を、右端の成功で隠さない
  wt=$( set -o pipefail
        {
          git diff HEAD || exit 1
          git ls-files -o --exclude-standard -z | while IFS= read -r -d '' f; do
            printf '%s ' "$f"
            git hash-object -- "$f" || exit 1
          done
        } | git hash-object --stdin ) || return 1
  [ -n "$wt" ] || return 1
  printf '%s:%s' "$head" "$wt"
}

if [ "${1:-}" = "--record" ]; then
  root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 1
  cd "$root" || exit 1
  state=$(current_state) || { echo "状態のハッシュ計算に失敗しました" >&2; exit 1; }
  printf '%s' "$state" > "$(git rev-parse --git-dir)/subagent-reviewed" && echo "recorded: $state"
  exit $?
fi

input=$(cat 2>/dev/null || true)
case "$input" in
  *'"stop_hook_active": true'* | *'"stop_hook_active":true'*) exit 0 ;;
esac

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
cd "$root" || exit 0

git rev-parse --verify --quiet origin/main >/dev/null 2>&1 || exit 0
base=$(git merge-base origin/main HEAD 2>/dev/null) || exit 0

THRESHOLD=${HMI_REVIEW_THRESHOLD:-30}

# 変更行数 = (コミット済み + 未コミットの追跡ファイル差分の追加+削除) + 未追跡ファイルの行数
tracked=$(git diff --numstat "$base" 2>/dev/null | awk '{ if ($1 ~ /^[0-9]+$/) s += $1; if ($2 ~ /^[0-9]+$/) s += $2 } END { print s + 0 }')
untracked=$(git ls-files -o --exclude-standard -z 2>/dev/null | while IFS= read -r -d '' f; do wc -l < "$f" 2>/dev/null; done | awk '{ s += $1 } END { print s + 0 }')
lines=$(( ${tracked:-0} + ${untracked:-0} ))
[ "${lines:-0}" -ge "$THRESHOLD" ] || exit 0

state=$(current_state) || exit 0
marker="$(git rev-parse --git-dir)/subagent-reviewed"
if [ -f "$marker" ] && [ "$(cat "$marker" 2>/dev/null)" = "$state" ]; then
  exit 0
fi

reason="サブエージェントレビューが未実施です(origin/main との差分 ${lines} 行)。.claude/rules/feedback-subagent-review.md に従い、Agent ツール(general-purpose・読み取り専用)でレビューさせ、指摘を修正・コミットしてください。完了後に 'bash scripts/hooks/require-subagent-review.sh --record' を実行すると、このフックは止まります。レビュー不要と判断できる場合(機械的な変更など)は、理由を一言添えて同じコマンドで記録してください。"

# reason に引用符を含むため jq で安全に JSON 化する(jq 無しなら引用符を除いて出力)
if command -v jq >/dev/null 2>&1; then
  jq -n --arg r "$reason" '{decision:"block",reason:$r}'
else
  printf '{"decision":"block","reason":"%s"}\n' "$(printf '%s' "$reason" | tr -d '"\\')"
fi
exit 0
