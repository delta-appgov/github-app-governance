#!/usr/bin/env bash
# Creates or updates a single "sticky" PR comment, identified by a hidden marker, so each push edits the same
# comment.
#
#   scripts/pr-comment.sh <pr-number> <body-file> [marker]
set -euo pipefail
pr="${1:?usage: pr-comment.sh <pr-number> <body-file> [marker]}"
file="${2:?body file}"
marker="<!-- ${3:-terraform-plan} -->"
repo="${GITHUB_REPOSITORY:?}"

payload="$(jq -n --arg m "$marker" --rawfile b "$file" '{body: ($m + "\n" + $b)}')"
id="$(gh api --paginate "repos/$repo/issues/$pr/comments" \
  | jq -rs --arg m "$marker" 'add | map(select(.user.login == "github-actions[bot]" and (.body | startswith($m)))) | last | .id // empty')"

if [ -n "$id" ]; then
  gh api -X PATCH "repos/$repo/issues/comments/$id" --input - <<<"$payload" >/dev/null && echo "updated comment $id"
else
  gh api -X POST "repos/$repo/issues/$pr/comments" --input - <<<"$payload" >/dev/null && echo "created comment"
fi
