# One authoritative resource per registered app: the installation's repository set is exactly what Git says.
# Repos added by hand in the UI show up as drift and are removed on the next apply.
#
# Never destroy an instance that still has real access: the provider's Delete keeps one *random* repository
# attached. scripts/plan-guard.sh blocks it in CI; quarantine first, then delete the YAML (D-006).
resource "github_app_installation_repositories" "this" {
  for_each = local.apps

  installation_id = try(local.installation[each.key].installation_id, "not-in-inventory")
  selected_repositories = [
    for r in local.effective_repos[each.key] :
    r == var.quarantine_repo ? data.github_repository.quarantine.name : try(github_repository.this[r].name, r)
  ]

  # Static checks only: the registry and the inventory are both reviewed in the PR. Live signals are warnings in
  # checks.tf, so that one app's live change can never block every plan.
  lifecycle {
    precondition {
      condition     = length(each.value.unknown_fields) == 0
      error_message = "apps/${each.key}.yaml: unknown field(s) ${join(", ", each.value.unknown_fields)}. Allowed: ${join(", ", sort(local.app_fields))}."
    }
    precondition {
      condition     = alltrue([for f in [each.value.owner_team, each.value.purpose, each.value.review_by, each.value.status] : f != null && f != ""])
      error_message = "apps/${each.key}.yaml: owner_team, purpose, review_by and status are required."
    }
    precondition {
      condition     = contains(["active", "deprecated", "quarantined"], coalesce(each.value.status, "-"))
      error_message = "apps/${each.key}.yaml: status must be active, deprecated or quarantined."
    }
    precondition {
      condition     = contains(["standard", "business-critical"], each.value.criticality)
      error_message = "apps/${each.key}.yaml: criticality must be standard or business-critical."
    }
    precondition {
      condition     = each.value.declared_tier == null || contains(keys(local.tier_rank), coalesce(each.value.declared_tier, "-"))
      error_message = "apps/${each.key}.yaml: declared_tier must be low, medium or high."
    }
    precondition {
      condition     = length(each.value.approved_permissions) > 0
      error_message = "apps/${each.key}.yaml: approved_permissions must list what security approved (e.g. contents: read)."
    }
    precondition {
      condition     = local.review_at[each.key] != null
      error_message = "apps/${each.key}.yaml: review_by must be a quoted date, e.g. review_by: \"2027-01-31\"."
    }
    precondition {
      condition     = local.review_at[each.key] == null || timecmp(coalesce(local.review_at[each.key], local.now), timeadd(local.now, "${local.max_days[each.key] * 24}h")) <= 0
      error_message = "apps/${each.key}.yaml: review_by ${coalesce(each.value.review_by, "-")} is too far out. A ${local.effective_tier[each.key]}-tier app must be reviewed within ${local.max_days[each.key]} days."
    }
    precondition {
      condition     = length(each.value.repositories) > 0
      error_message = "apps/${each.key}.yaml: repositories must not be empty. To remove all real access, set status: quarantined."
    }
    precondition {
      condition     = alltrue([for r in each.value.repositories : contains(keys(local.repositories), r)])
      error_message = "apps/${each.key}.yaml: every repository must be listed in repositories.yaml. Unknown: ${join(", ", [for r in each.value.repositories : r if !contains(keys(local.repositories), r)])}. (The quarantine repo is never listed; use status: quarantined.)"
    }
    precondition {
      condition     = alltrue([for b in each.value.bypass : b == "require-pr"])
      error_message = "apps/${each.key}.yaml: bypass may only contain require-pr. branch-integrity has no bypass, by design."
    }
    precondition {
      condition     = local.installation[each.key] != null
      error_message = "App '${each.key}' (slug ${local.app_slug[each.key]}) is not in inventory/inventory.json. Install it on '${var.quarantine_repo}' only, run scripts/inventory.sh and commit the result in this PR."
    }
    precondition {
      condition     = try(local.installation[each.key].repository_selection, "selected") == "selected"
      error_message = "App '${each.key}' is installed with 'All repositories'. Switch it to 'Only select repositories' in the GitHub UI; Terraform can't change that."
    }
  }
}

locals {
  max_days = { for name, tier in local.effective_tier : name => var.max_review_days[tier] }
}
