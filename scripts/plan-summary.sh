#!/usr/bin/env bash
# Renders a Terraform plan as Markdown for the PR comment and the job summary: who gains or loses which repos,
# bypass changes, other changes, and the governance warnings from check blocks.
#
#   scripts/plan-summary.sh plan.json [plan.txt] > summary.md
set -euo pipefail

plan="${1:?usage: plan-summary.sh plan.json [plan.txt]}"
text="${2:-}"
inventory="$(cd "$(dirname "$0")/.." && pwd)/inventory/inventory.json"

jq -r --slurpfile inv "$inventory" --arg q "${QUARANTINE_REPO:-app-quarantine}" '
  # App IDs → app slugs, via the committed inventory.
  def names($ids): [$ids[] as $id | (($inv[0].installations | to_entries[] | select(.value.app_id == $id) | .key) // ($id | tostring))];
  def joined: if length == 0 then "—" else join(", ") end;
  def has($r): any(.[]; . == $r);

  [.resource_changes[]? | select(.change.actions != ["no-op"] and .change.actions != ["read"])] as $changes
  | ($changes | map(.change.actions | join("+")) | group_by(.) | map("\(length) to \(.[0])") | join(", ")) as $counts

  | "### Terraform plan: " + (if ($changes | length) == 0 then "no changes" else $counts end),
    "",

    ( [$changes[] | select(.type == "github_app_installation_repositories")] as $apps
      | if ($apps | length) > 0 then
          "#### App repository access", "",
          "| App | Before | After | Change |", "|---|---|---|---|",
          ( $apps[]
            | (.change.before.selected_repositories // []) as $b
            | (if .change.actions == ["delete"] then [] else (.change.after.selected_repositories // []) end) as $a
            | "| `\(.index)` | \(if .change.actions == ["create"] then "*not managed yet*" else ($b | joined) end) | \(if .change.actions == ["delete"] then "*removed from Terraform*" else ($a | joined) end) | \(if .change.actions == ["delete"] then "no longer tracked; GitHub keeps it on \($b | joined) until it is uninstalled" else (($a - $b - [$q]) | map("**+" + . + "**")) + (($b - $a - [$q]) | map("−" + .))
                  + (if ($a | has($q)) and (($b | has($q)) | not) then ["⏸ parked on \($q) (no real access)"] else [] end)
                  + (if ($b | has($q)) and (($a | has($q)) | not) then ["▶ leaves \($q)"] else [] end) | joined end) |" ),
          ""
        else empty end ),

    ( [$changes[] | select(.type == "github_repository_ruleset" and (.change.actions == ["update"] or .change.actions == ["create"]))
        | select((.change.before.bypass_actors // []) != (.change.after.bypass_actors // []))] as $rs
      | if ($rs | length) > 0 then
          "#### Ruleset bypass (apps allowed to skip the rule)", "",
          "| Repo / ruleset | Before | After |", "|---|---|---|",
          ( $rs[] | "| `\(.index)` / \(.change.after.name) | \(names([.change.before.bypass_actors[]?.actor_id]) | joined) | \(names([.change.after.bypass_actors[]?.actor_id]) | joined) |" ),
          ""
        else empty end ),

    ( [$changes[] | select(.type != "github_app_installation_repositories")] as $other
      | if ($other | length) > 0 then
          "#### Other changes", "",
          ( $other[] | "- `\(.address)`: \(.change.actions | join("+"))" ),
          ""
        else empty end ),

    ( [.checks[]? | select(.status == "fail") | .instances[]?.problems[]?.message] as $warn
      | if ($warn | length) > 0 then
          "#### ⚠️ Governance warnings", "",
          ( $warn[] | "- " + gsub("\n"; " ") ),
          ""
        else empty end )
' "$plan"

if [ -n "$text" ] && [ -f "$text" ]; then
  echo "<details><summary>Full plan output</summary>"
  echo
  echo '```'
  head -c 60000 "$text"
  echo
  echo '```'
  echo "</details>"
fi
