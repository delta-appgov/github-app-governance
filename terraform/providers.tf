provider "github" {
  owner = var.github_owner

  # Auth: the GITHUB_TOKEN env var. It must be a classic PAT (repo, read:org). The installation-repositories
  # resource reads through GET /user/installations/{id}/repositories, which only accepts user tokens: not
  # fine-grained PATs, not GitHub App tokens (D-005).
}
