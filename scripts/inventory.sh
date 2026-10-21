#!/usr/bin/env bash
# Regenerates inventory/inventory.json from the org's live GitHub App installations (D-003).
#
#   scripts/inventory.sh           rewrite the file, but only if the installations changed
#   scripts/inventory.sh --check   exit 1 and print a diff if the committed file differs from the live org
#
# Needs GH_OWNER (the org) and a token `gh` can use (GH_TOKEN) that may list org installations: an org owner's
# classic PAT, or a fine-grained PAT with organization "Administration: read".
set -euo pipefail

org="${GH_OWNER:?set GH_OWNER to the GitHub organization}"
file="$(cd "$(dirname "$0")/.." && pwd)/inventory/inventory.json"
mode="${1:-write}"

# updated_at is left out on purpose: it changes whenever repositories are added or removed, and the repository
# set is Terraform's job, not the inventory's.
live="$(gh api --paginate "orgs/$org/installations?per_page=100" --jq '.installations[]' | jq -S -s '
  map({key: .app_slug, value: {
    installation_id: .id,
    app_id,
    repository_selection,
    suspended: (.suspended_at != null),
    permissions,
    created_at
  }}) | from_entries')"

current="$(if [ -f "$file" ]; then jq -S '.installations' "$file"; else echo null; fi)"

if [ "$live" = "$current" ]; then
  echo "inventory: up to date ($(jq length <<<"$live") installations)"
  exit 0
fi

if [ "$mode" = "--check" ]; then
  echo "inventory: the committed file differs from the live org (- committed, + live):"
  diff <(echo "$current") <(echo "$live") || true
  exit 1
fi

jq -S -n --arg org "$org" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson installations "$live" \
  '{generated_at: $now, org: $org, installations: $installations}' >"$file"
echo "inventory: wrote $(jq length <<<"$live") installations to inventory/inventory.json"
