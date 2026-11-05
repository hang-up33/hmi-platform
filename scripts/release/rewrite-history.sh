#!/usr/bin/env bash
# v1.0 公開用：main の履歴から個人のメールとセッション URL を消したクローンを作る。
# 使い方: bash rewrite-history.sh <元リポジトリの URL かパス> <出力ディレクトリ>
# 手順の正本は Docs/v1-release-runbook.md。
# 置き換え表（mailmap.txt / msg-replace.txt）はこのスクリプトと同じ場所に置く。
# どちらも個人のメールを含むので、リポジトリには入れない。
set -euo pipefail

SRC="$1"
OUT="$2"
HERE="$(cd "$(dirname "$0")" && pwd)"

if [ -e "$OUT" ]; then
    echo "出力先 $OUT が既にある。消してからやり直す。" >&2
    exit 1
fi

# 1. main だけを新しくクローンする（他のブランチやタグは持ち込まない）
git clone --quiet --single-branch --branch main --no-tags "$SRC" "$OUT"
cd "$OUT"
ORIG_TREE="$(git rev-parse HEAD^{tree})"
ORIG_COUNT="$(git rev-list --count HEAD)"

# 2. 作者・コミッターの名前とメールを置き換える
git filter-repo --force --mailmap "$HERE/mailmap.txt"

# 3. メッセージ中のメール・(#N)・セッション URL を置き換える
git filter-repo --force --replace-message "$HERE/msg-replace.txt"

# 4. 確かめる
fail=0
EMAILS="$(grep -oE '[A-Za-z0-9._%+-]+@gmail\.com' "$HERE/mailmap.txt" | sort -u)"
for e in $EMAILS; do
    if git log --all --format='%an %ae %cn %ce %B' | grep -qF "$e"; then
        echo "NG: コミット情報に個人のメールが残っている" >&2; fail=1
    fi
    if git grep -qF "$e" $(git rev-list --all) 2>/dev/null; then
        echo "NG: ファイルの中に個人のメールが残っている" >&2; fail=1
    fi
done
if git log --all --format='%an %cn' | grep -qvE '^(hang-up33|Claude|GitHub) (hang-up33|Claude|GitHub)$'; then
    echo "NG: 想定外の作者名がある:" >&2
    git log --all --format='%an / %cn' | sort -u >&2; fail=1
fi
if git log --all --format='%B' | grep -q 'claude.ai/code/session'; then
    echo "NG: セッション URL が残っている" >&2; fail=1
fi
if [ "$(git rev-parse HEAD^{tree})" != "$ORIG_TREE" ]; then
    echo "NG: ファイルの中身が元と変わった" >&2; fail=1
fi
if [ "$(git rev-list --count HEAD)" != "$ORIG_COUNT" ]; then
    echo "NG: コミット数が元と変わった" >&2; fail=1
fi

echo "コミット数: $(git rev-list --count HEAD)"
echo "作者とコミッター:"
git log --format='  %an <%ae> / %cn <%ce>' | sort | uniq -c
if [ "$fail" -ne 0 ]; then
    echo "結果: NG（公開しない）" >&2
    exit 1
fi
echo "結果: OK"
