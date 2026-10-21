# Workload repositories: settings relevant to app governance, as code. The governance repo and the quarantine repo
# are deliberately not managed here (D-004, D-013).
resource "github_repository" "this" {
  for_each = local.repositories

  name        = each.key
  description = each.value.description
  topics      = each.value.topics
  visibility  = "public" # GitHub Free: rulesets and environment protections need public repos (D-010)

  auto_init              = true
  has_issues             = true
  has_wiki               = false
  has_projects           = false
  allow_merge_commit     = false
  allow_rebase_merge     = false
  allow_squash_merge     = true
  delete_branch_on_merge = true

  # The pipeline token has no delete_repo scope: removing a repo from repositories.yaml archives it, never deletes it.
  archive_on_destroy = true

  lifecycle {
    precondition {
      condition     = !contains([var.governance_repo, var.quarantine_repo], each.key)
      error_message = "repositories.yaml must not list '${each.key}': the governance and quarantine repos are managed outside this config (D-004, D-013)."
    }
  }
}

# Created and archived during setup; only read here (D-013).
data "github_repository" "quarantine" {
  name = var.quarantine_repo
}

# Owner teams come from setup (like IdP-synced teams in an enterprise) and are only read here (D-012).
data "github_organization_teams" "all" {
  summary_only = true
}
