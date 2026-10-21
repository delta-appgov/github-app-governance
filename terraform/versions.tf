terraform {
  required_version = ">= 1.11"

  required_providers {
    github = {
      source = "integrations/github"
      # Exact pin. 6.13.0 has a known regression (#3576) that only triggers when GITHUB_APP_* env vars are set;
      # this config never sets them. Upgrades arrive as Dependabot PRs and must produce a no-op plan.
      version = "= 6.13.0"
    }
  }

  # State lives in HCP Terraform, in local execution mode (D-001, D-002). Organization and workspace come from
  # TF_CLOUD_ORGANIZATION / TF_WORKSPACE, and the token from TF_TOKEN_app_terraform_io, so nothing org-specific
  # is in the code. No HCP account? Copy ../examples/local_override.tf here to use local state instead.
  cloud {}
}
