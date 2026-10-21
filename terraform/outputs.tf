output "access_matrix" {
  description = "Who can reach what: one entry per registered app."
  value = {
    for name, app in local.apps : name => {
      slug         = local.app_slug[name]
      owner_team   = app.owner_team
      tier         = local.effective_tier[name]
      status       = local.effective_status[name]
      review_by    = app.review_by
      repositories = local.effective_repos[name]
      bypass       = local.effective_status[name] == "active" ? app.bypass : []
    }
  }
}
