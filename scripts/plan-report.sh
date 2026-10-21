#!/usr/bin/env bash
# Markdown report of a plan (or of a failed plan), plus any plan-guard violations. Used for PR comments and job
# summaries.
#
#   scripts/plan-report.sh [guard.log]
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
tf="$here/../terraform"
guard="${1:-}"

if [ -f "$tf/plan.json" ]; then
  "$here/plan-summary.sh" "$tf/plan.json" "$tf/plan.txt"
else
  echo "### ❌ Terraform plan failed"
  echo
  echo "Registry mistakes fail a precondition with an explanation, e.g. a review date too far out, an unknown"
  echo "repository, or an app missing from the inventory."
  echo
  if [ -f "$tf/plan.log" ]; then
    # The explanation first (from the first "Error:" on), the full log folded underneath.
    echo '```'
    sed -n '/^Error: /,$p' "$tf/plan.log" | head -c 15000
    echo '```'
    echo
    echo "<details><summary>Full plan log</summary>"
    echo
    echo '```'
    tail -c 20000 "$tf/plan.log"
    echo '```'
    echo "</details>"
  else
    echo "(no plan output)"
  fi
fi

if [ -n "$guard" ] && [ -f "$guard" ] && grep -q '^::error' "$guard"; then
  echo
  echo "#### ❌ Plan guard"
  echo
  sed -n 's/^::error title=Plan guard::/- /p' "$guard"
fi
