#!/usr/bin/env bash
# One GitHub issue per audit finding type, matched by exact title.
#
#   scripts/issue.sh "<title>" <body-file>
#   Non-empty body → open the issue, or update its body. Empty body → close the issue if it's open.
set -euo pipefail
title="${1:?usage: issue.sh <title> <body-file>}"
file="${2:?body file}"
repo="${GITHUB_REPOSITORY:?}"
label="governance-audit"

gh label create "$label" --repo "$repo" --color B60205 --description "Opened by the daily governance audit" --force >/dev/null
num="$(gh issue list --repo "$repo" --label "$label" --state open --limit 100 --json number,title \
  | jq -r --arg t "$title" 'map(select(.title == $t)) | first | .number // empty')"

if [ -s "$file" ]; then
  body="$(mktemp)"
  { cat "$file"; echo; echo "<sub>Last checked $(date -u '+%Y-%m-%d %H:%M UTC') by [the audit workflow](${GITHUB_SERVER_URL:-https://github.com}/$repo/actions/runs/${GITHUB_RUN_ID:-0}).</sub>"; } >"$body"
  if [ -n "$num" ]; then
    gh issue edit "$num" --repo "$repo" --body-file "$body" >/dev/null && echo "updated #$num: $title"
  else
    gh issue create --repo "$repo" --title "$title" --label "$label" --body-file "$body"
  fi
elif [ -n "$num" ]; then
  gh issue close "$num" --repo "$repo" --comment "Resolved: the audit no longer finds this ($(date -u +%Y-%m-%d))." >/dev/null && echo "closed #$num: $title"
else
  echo "clean: $title"
fi
