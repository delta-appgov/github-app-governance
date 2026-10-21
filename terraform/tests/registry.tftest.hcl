# Offline tests of the registry logic: a mocked provider, no token, no network. They run in the CI validate job.
#
# In `terraform test`, a failing check block fails the run unless it is listed in expect_failures. So every run
# also states which governance warnings must fire, which tests the warnings themselves.
#
# Fixture inventory: t-bot (contents:write), t-reporter (checks:write), t-old (pull_requests:write),
# t-crit (read-only), and t-stray (not registered, installed on "All repositories").

mock_provider "github" {
  mock_data "github_repository" {
    defaults = {
      archived = true
    }
  }

  mock_data "github_organization_teams" {
    defaults = {
      teams = [
        for slug in ["platform", "product", "security"] : {
          slug    = slug, name = slug, id = 1, node_id = "n", description = "", privacy = "closed",
          members = [], repositories = [], parent = {}, parent_team_id = "", parent_team_slug = ""
        }
      ]
    }
  }
}

variables {
  github_owner      = "test-org"
  app_slug_prefix   = "t-"
  now               = "2026-10-21T00:00:00Z"
  registry_dir      = "tests/fixtures/apps"
  inventory_file    = "tests/fixtures/inventory.json"
  repositories_file = "tests/fixtures/repositories.yaml"
}

run "grants_follow_the_registry" {
  command = plan

  # t-stray is unregistered and on "All repositories"; crit's review (2026-11-01) is within 30 days.
  expect_failures = [check.unregistered_apps, check.all_repositories_installs, check.reviews_due_soon]

  assert {
    condition     = github_app_installation_repositories.this["bot"].selected_repositories == toset(["service-a", "service-b"])
    error_message = "An active app gets exactly the repositories in its YAML."
  }

  assert {
    condition     = github_app_installation_repositories.this["bot"].installation_id == "101"
    error_message = "The installation ID comes from the committed inventory via the derived slug (prefix + name)."
  }

  assert {
    condition     = github_app_installation_repositories.this["old"].selected_repositories == toset(["app-quarantine"])
    error_message = "A quarantined app keeps its installation but only sees the quarantine repo."
  }
}

run "bypass_only_where_the_app_is_installed" {
  command = plan

  expect_failures = [check.unregistered_apps, check.all_repositories_installs, check.reviews_due_soon]

  assert {
    condition     = [for b in github_repository_ruleset.require_pr["service-a"].bypass_actors : b.actor_id] == [1001]
    error_message = "service-a: only the app with bypass: [require-pr] that is granted service-a may bypass (by App ID)."
  }

  assert {
    condition     = length(github_repository_ruleset.require_pr["service-c"].bypass_actors) == 0
    error_message = "service-c: no app with a bypass is granted it, so no bypass actors."
  }

  assert {
    condition     = length(github_repository_ruleset.branch_integrity["service-a"].bypass_actors) == 0
    error_message = "branch-integrity never has bypass actors."
  }
}

run "tiers_are_derived_from_live_permissions" {
  command = plan

  expect_failures = [check.unregistered_apps, check.all_repositories_installs, check.reviews_due_soon]

  assert {
    condition     = output.access_matrix["bot"].tier == "high" && output.access_matrix["reporter"].tier == "medium" && output.access_matrix["crit"].tier == "low"
    error_message = "contents:write + bypass → high, checks:write → medium, read-only → low."
  }
}

run "expiry_quarantines_unless_business_critical" {
  command = plan

  variables {
    now = "2027-01-01T00:00:00Z" # bot: review_by 2026-12-01 + 14 days of grace has passed; crit too, but it's business-critical
  }

  expect_failures = [check.auto_quarantined, check.expired_business_critical, check.unregistered_apps, check.all_repositories_installs]

  assert {
    condition     = github_app_installation_repositories.this["bot"].selected_repositories == toset(["app-quarantine"])
    error_message = "An expired standard app is quarantined automatically (D-008)."
  }

  assert {
    condition     = length(github_repository_ruleset.require_pr["service-a"].bypass_actors) == 0
    error_message = "A quarantined app loses its bypass too."
  }

  assert {
    condition     = github_app_installation_repositories.this["crit"].selected_repositories == toset(["service-c"])
    error_message = "An expired business-critical app keeps access and is escalated (check warning) instead."
  }
}

run "rejects_review_date_beyond_tier_limit" {
  command = plan

  variables {
    registry_dir   = "tests/fixtures/apps-review-too-far" # high tier, review_by a year out
    inventory_file = "tests/fixtures/inventory-bot.json"
  }

  expect_failures = [github_app_installation_repositories.this]
}

run "rejects_unmanaged_repository" {
  command = plan

  variables {
    registry_dir   = "tests/fixtures/apps-unknown-repo" # asks for the governance repo
    inventory_file = "tests/fixtures/inventory-reporter.json"
  }

  expect_failures = [github_app_installation_repositories.this]
}

run "rejects_app_missing_from_inventory" {
  command = plan

  variables {
    registry_dir   = "tests/fixtures/apps-not-installed"
    inventory_file = "tests/fixtures/inventory-empty.json"
  }

  expect_failures = [github_app_installation_repositories.this]
}
