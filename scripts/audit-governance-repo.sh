#!/usr/bin/env bash
# Checks the governance repo's own protections, which a human sets with bootstrap and the pipeline never changes
# (D-004). Prints findings as Markdown bullets; prints nothing when everything is in place.
set -euo pipefail
repo="${GITHUB_REPOSITORY:?}"
actions_app_id=15368 # GitHub Actions: required checks must come from it, not from any app with checks:write
findings=()

rules="$(gh api "repos/$repo/rulesets" --jq '.[] | select(.target == "branch" and .enforcement == "active") | .id' \
  | while read -r id; do gh api "repos/$repo/rulesets/$id"; done | jq -s '[.[].rules[]]')"

for t in pull_request required_status_checks non_fast_forward deletion; do
  jq -e --arg t "$t" 'any(.[]; .type == $t)' <<<"$rules" >/dev/null ||
    findings+=("No active branch ruleset enforces \`$t\`.")
done
for c in validate plan; do
  jq -e --arg c "$c" --argjson app "$actions_app_id" \
    'any(.[]; .type == "required_status_checks" and any(.parameters.required_status_checks[]; .context == $c and .integration_id == $app))' \
    <<<"$rules" >/dev/null || findings+=("Required check \`$c\` is missing or not pinned to GitHub Actions.")
done

envs="$(gh api "repos/$repo/environments" --jq '.environments')"
jq -e 'any(.[]; .name == "plan" and any(.protection_rules[]?; .type == "required_reviewers"))' <<<"$envs" >/dev/null ||
  findings+=("Environment \`plan\` has no required reviewer (D-007).")
for e in production audit; do
  branches="$(gh api "repos/$repo/environments/$e/deployment-branch-policies" --jq '[.branch_policies[].name] | join(",")' 2>/dev/null || true)"
  [ "$branches" = "main" ] || findings+=("Environment \`$e\` is not restricted to \`main\` (found: ${branches:-none}).")
done

for f in "${findings[@]+"${findings[@]}"}"; do echo "- $f"; done
