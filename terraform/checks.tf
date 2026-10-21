# Warnings: they appear in every plan (and in the PR comment) but never block. Use them for anything that depends
# on time or on the live org, so that one app's problem can't stop unrelated changes or an emergency fix.

check "reviews_due_soon" {
  assert {
    condition     = !anytrue(values(local.due_soon))
    error_message = "Review due within ${var.review_warning_days} days: ${join(", ", [for n, d in local.due_soon : "${n} (${local.apps[n].review_by})" if d])}. Renew with a PR that bumps review_by, or start decommissioning."
  }
}

check "reviews_overdue" {
  assert {
    condition     = !anytrue([for n, o in local.overdue : o && !local.expired[n]])
    error_message = "Review overdue, in grace period: ${join(", ", [for n, o in local.overdue : "${n} (auto-quarantine on ${formatdate("YYYY-MM-DD", local.expires_at[n])})" if o && !local.expired[n]])}."
  }
}

check "auto_quarantined" {
  assert {
    condition     = !anytrue(values(local.auto_quarantined))
    error_message = "Quarantined automatically because the review expired: ${join(", ", [for n, q in local.auto_quarantined : n if q])}. Renew review_by to restore access."
  }
}

check "expired_business_critical" {
  assert {
    condition     = !anytrue([for n, app in local.apps : local.expired[n] && app.criticality == "business-critical" && app.status == "active"])
    error_message = "Business-critical app(s) past review + grace, NOT cut off, escalate: ${join(", ", [for n, app in local.apps : "${n} → ${coalesce(app.escalation, app.owner_team, "-")}" if local.expired[n] && app.criticality == "business-critical" && app.status == "active"])}."
  }
}

check "unregistered_apps" {
  assert {
    condition     = length(local.unregistered_slugs) == 0
    error_message = "Installed but not registered: ${join(", ", local.unregistered_slugs)}. Triage per docs/GOVERNANCE.md: owner claims it with a registry PR within 14 days, otherwise quarantine → suspend → uninstall."
  }
}

check "all_repositories_installs" {
  assert {
    condition     = length(local.all_repos_slugs) == 0
    error_message = "Installed with 'All repositories' (includes the governance repo): ${join(", ", local.all_repos_slugs)}. Requires a security exception or a switch to selected repositories."
  }
}

check "permission_creep" {
  assert {
    condition     = alltrue([for n, p in local.permission_creep : length(p) == 0])
    error_message = "Holds permissions beyond approved_permissions: ${join("; ", [for n, p in local.permission_creep : "${n}: ${join(", ", p)}" if length(p) > 0])}. Approve them in the registry, or ask the vendor to drop them."
  }
}

check "suspended_apps" {
  assert {
    condition     = !anytrue([for n, i in local.installation : try(i.suspended, false)])
    error_message = "Suspended (break-glass in effect): ${join(", ", [for n, i in local.installation : n if try(i.suspended, false)])}. Follow up with a quarantine PR or unsuspend."
  }
}

check "owner_teams_exist" {
  assert {
    condition     = alltrue([for n, app in local.apps : alltrue([for t in compact([app.owner_team, app.escalation]) : contains(local.team_slugs, t)])])
    error_message = "Owner/escalation team not found in the org: ${join(", ", flatten([for n, app in local.apps : [for t in compact([app.owner_team, app.escalation]) : "${n} → ${t}" if !contains(local.team_slugs, t)]]))}."
  }
}

check "quarantine_repo_archived" {
  assert {
    condition     = data.github_repository.quarantine.archived
    error_message = "${var.quarantine_repo} is not archived, so apps parked there could write to it. Archive it again (D-013)."
  }
}
