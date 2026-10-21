# Two rulesets per workload repo, so an app's bypass can never weaken history protection.

# No deletion, no force-push. Nobody bypasses this, not even apps: a stolen bot key must not rewrite history.
resource "github_repository_ruleset" "branch_integrity" {
  for_each = github_repository.this

  name        = "branch-integrity"
  repository  = each.value.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    deletion         = true
    non_fast_forward = true
  }
}

# Changes go through pull requests. Apps whose registry entry has `bypass: [require-pr]` may push directly, but
# only on repositories they are granted and only while active. This is the "access rule an app depends on".
resource "github_repository_ruleset" "require_pr" {
  for_each = github_repository.this

  name        = "require-pr"
  repository  = each.value.name
  target      = "branch"
  enforcement = "active"

  conditions {
    ref_name {
      include = ["~DEFAULT_BRANCH"]
      exclude = []
    }
  }

  rules {
    pull_request {
      required_approving_review_count   = var.required_approvals
      dismiss_stale_reviews_on_push     = true
      required_review_thread_resolution = true
    }
  }

  dynamic "bypass_actors" {
    for_each = local.bypass_by_repo[each.key]
    content {
      actor_id    = tonumber(bypass_actors.value) # the App ID, not the installation ID
      actor_type  = "Integration"
      bypass_mode = "always"
    }
  }

  # GitHub rejects an Integration bypass for an app that isn't installed on the repo (spike S4). Access must change
  # first. That ordering also works when access is revoked (spike S2).
  depends_on = [github_app_installation_repositories.this]
}
