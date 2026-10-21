# No HCP Terraform account? Copy this file into terraform/ to keep state on your machine instead (D-001).
# Terraform override files replace the `cloud {}` block in versions.tf. terraform/*_override.tf is git-ignored.
terraform {
  backend "local" {}
}
