#!/usr/bin/env bash
# Slack のチャンネルへ、文章と画像（任意）を投稿する。
#
# 使い方:
#   scripts/ci/slack-post.sh <本文ファイル> [画像ファイル ...]
#
# 必要な環境変数:
#   SLACK_BOT_TOKEN   Bot トークン（xoxb-）。画像を付けるには、権限 files:write が要る
#   SLACK_CHANNEL_ID  投稿先のチャンネル ID
#
# 動き:
#   - 画像が 1 枚以上あれば、画像と本文を 1 件の投稿にまとめてアップロードする。
#   - 画像のアップロードに失敗したとき（権限不足など）は、本文だけを通常の投稿で送る。
#   - 本文の投稿にも失敗したときだけ、終了コード 1 で終わる。
set -euo pipefail

if [ "$#" -lt 1 ]; then
  echo "使い方: $0 <本文ファイル> [画像ファイル ...]" >&2
  exit 2
fi
body_file="$1"
shift
images=("$@")

: "${SLACK_BOT_TOKEN:?SLACK_BOT_TOKEN を設定してください}"
: "${SLACK_CHANNEL_ID:?SLACK_CHANNEL_ID を設定してください}"
api="https://slack.com/api"
auth=(-H "Authorization: Bearer ${SLACK_BOT_TOKEN}")

# 応答が空や壊れた JSON でも落ちないように、値を取り出す。取り出せなければ空を返す。
jqs() {
  jq -r "$1" 2>/dev/null || true
}

post_text_only() {
  local payload res
  payload="$(jq -n --arg c "${SLACK_CHANNEL_ID}" --rawfile t "${body_file}" '{channel: $c, text: $t}')"
  res="$(curl -sS -X POST "${api}/chat.postMessage" "${auth[@]}" \
    -H 'Content-Type: application/json; charset=utf-8' --data "${payload}")"
  echo "${res}" | jq '{ok, error}'
  [ "$(jq -r '.ok' <<<"${res}")" = "true" ]
}

# 画像を 1 枚アップロードし、{"id": ..., "title": ...} を標準出力へ出す。失敗したら 1 を返す。
upload_one() {
  local path="$1" name size res upload_url file_id code
  name="$(basename "${path}")"
  size="$(wc -c < "${path}" | tr -d ' ')"
  res="$(curl -sS -X POST "${api}/files.getUploadURLExternal" "${auth[@]}" \
    --data-urlencode "filename=${name}" --data-urlencode "length=${size}" || true)"
  if [ "$(jqs '.ok' <<<"${res}")" != "true" ]; then
    echo "[slack-post] アップロード先の取得に失敗: $(jqs '.error' <<<"${res}")" >&2
    return 1
  fi
  upload_url="$(jqs '.upload_url' <<<"${res}")"
  file_id="$(jqs '.file_id' <<<"${res}")"
  code="$(curl -sS -X POST "${upload_url}" --data-binary "@${path}" -o /dev/null -w '%{http_code}' || true)"
  if [ "${code}" != "200" ]; then
    echo "[slack-post] 画像の送信に失敗: HTTP ${code}" >&2
    return 1
  fi
  jq -n --arg id "${file_id}" --arg t "${name%.*}" '{id: $id, title: $t}'
}

if [ "${#images[@]}" -gt 0 ]; then
  files_json="[]"
  failed=0
  for img in "${images[@]}"; do
    if [ ! -s "${img}" ]; then
      echo "[slack-post] 画像が無いか空: ${img}" >&2
      continue
    fi
    if item="$(upload_one "${img}")"; then
      files_json="$(jq -c --argjson i "${item}" '. + [$i]' <<<"${files_json}")"
    else
      failed=1
      break
    fi
  done
  if [ "${failed}" -eq 0 ] && [ "$(jq 'length' <<<"${files_json}")" -gt 0 ]; then
    payload="$(jq -n --arg c "${SLACK_CHANNEL_ID}" --rawfile t "${body_file}" --argjson f "${files_json}" \
      '{files: $f, channel_id: $c, initial_comment: $t}')"
    res="$(curl -sS -X POST "${api}/files.completeUploadExternal" "${auth[@]}" \
      -H 'Content-Type: application/json; charset=utf-8' --data "${payload}" || true)"
    if [ "$(jqs '.ok' <<<"${res}")" = "true" ]; then
      echo "[slack-post] 画像付きで投稿した"
      exit 0
    fi
    echo "[slack-post] 画像付きの投稿に失敗: $(jqs '.error' <<<"${res}")（通信の失敗を含む）" >&2
  fi
  echo "[slack-post] 画像なしで投稿し直す" >&2
fi

post_text_only
