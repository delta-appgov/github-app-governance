#!/usr/bin/env bash
# Policy checks on a Terraform plan (the JSON from `terraform show -json`). Exits 1 on any violation.
#
#   scripts/plan-guard.sh plan.json                    delete guard (D-006); runs on every plan and apply
#   scripts/plan-guard.sh plan.json --narrowing-only   scheduled reconcile: apps may only LOSE access
set -euo pipefail

plan="${1:?usage: plan-guard.sh plan.json [--narrowing-only]}"
mode="${2:-}"
quarantine="${QUARANTINE_REPO:-app-quarantine}"

# Delete guard (D-006): an installation resource may only be deleted or replaced while it is parked on the
# quarantine repo. The provider's Delete keeps one *random* repository attached, so deleting an app that still has
# real access would leave it on an arbitrary repo. This also catches an empty or mis-pathed registry, and an
# installation-ID change from a reinstall.
violations="$(jq -r --arg q "$quarantine" '
  .resource_changes[]?
  | select(.type == "github_app_installation_repositories" and (.change.actions | index("delete")))
  | select((.change.before.selected_repositories // []) != [$q])
  | "\(.address) would be deleted (\(.change.actions | join("+"))) while it still has access to: \(.change.before.selected_repositories | join(", ")). Set status: quarantined and merge first; delete the YAML in a later PR (D-006)."
' "$plan")"

if [ "$mode" = "--narrowing-only" ]; then
  # The scheduled reconcile applies without a human looking at the plan. It may revoke access that was added by
  # hand or expired, and drop bypasses of apps that lost access. It must never grant anything, and must never
  # re-grant access an owner removed during an incident.
  # Landing on the archived, empty quarantine repo is never "gaining access".
  narrowing="$(jq -r --arg q "$quarantine" '
    .resource_changes[]?
    | select(.change.actions != ["no-op"] and .change.actions != ["read"])
    | if .type == "github_app_installation_repositories" and .change.actions == ["update"] then
        ((.change.after.selected_repositories - .change.before.selected_repositories - [$q]) as $added
         | select($added | length > 0)
         | "\(.address) would GAIN access to: \($added | join(", "))")
      elif .type == "github_repository_ruleset" and .change.actions == ["update"] then
        select(
          ((.change.before | del(.bypass_actors, .etag)) != (.change.after | del(.bypass_actors, .etag)))
          or (((.change.after.bypass_actors // []) - (.change.before.bypass_actors // [])) | length > 0)
        )
        | "\(.address): only removing bypass actors is allowed in narrowing-only mode"
      else
        "\(.address): \(.change.actions | join("+")) is not allowed in narrowing-only mode"
      end
  ' "$plan")"
  violations="$(printf '%s\n%s\n' "$violations" "$narrowing" | sed '/^$/d')"
fi

if [ -n "$violations" ]; then
  while IFS= read -r v; do echo "::error title=Plan guard::$v"; done <<<"$violations"
  exit 1
fi
echo "plan-guard: OK${mode:+ ($mode)}"
