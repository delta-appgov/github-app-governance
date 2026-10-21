variable "github_owner" {
  description = "GitHub organization to govern."
  type        = string
}

variable "app_slug_prefix" {
  description = "Prefix added to an app's logical name (its registry file name) to form its GitHub slug. Slugs are unique across all of GitHub, so each org uses its own prefix."
  type        = string
  default     = ""
}

variable "quarantine_repo" {
  description = "Archived parking repo for apps that must keep an installation but no real access (D-006, D-013). Created during setup; only read here."
  type        = string
  default     = "app-quarantine"
}

variable "governance_repo" {
  description = "The repository holding this config. Never managed by it (D-004)."
  type        = string
  default     = "github-app-governance"
}

variable "required_approvals" {
  description = "Approvals required by the require-pr ruleset on workload repositories."
  type        = number
  default     = 1
}

variable "review_warning_days" {
  description = "Start warning this many days before an app's review_by date."
  type        = number
  default     = 30
}

variable "expiry_grace_days" {
  description = "Days after review_by before an active, non-business-critical app is quarantined automatically (D-008)."
  type        = number
  default     = 14
}

variable "max_review_days" {
  description = "Longest allowed review interval per risk tier."
  type        = map(number)
  default     = { high = 90, medium = 180, low = 365 }

  validation {
    condition     = alltrue([for t in ["high", "medium", "low"] : contains(keys(var.max_review_days), t)])
    error_message = "max_review_days must define high, medium and low."
  }
}

# --- Test hooks: overridden only by terraform test --------------------------------------------------------------

variable "now" {
  description = "Override the current time (RFC 3339). Plans use plantimestamp(); tests pin a date."
  type        = string
  default     = null
}

variable "registry_dir" {
  description = "Override the app registry directory (default: ../apps)."
  type        = string
  default     = null
}

variable "inventory_file" {
  description = "Override the inventory file (default: ../inventory/inventory.json)."
  type        = string
  default     = null
}

variable "repositories_file" {
  description = "Override the managed-repositories file (default: ../repositories.yaml)."
  type        = string
  default     = null
}
