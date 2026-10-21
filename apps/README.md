# App registry

One YAML file per GitHub App. **The file name is the app's logical name**. Its GitHub slug is
`<app_slug_prefix><name>` unless `slug:` overrides it, because slugs are unique across all of GitHub.

Every change to an app's access is a PR to its file. The plan comment shows exactly which repositories change.

| Field | Required | Meaning |
|---|---|---|
| `owner_team` | ✅ | GitHub team accountable for the app (a team, never a person) |
| `escalation` | | Fallback team if the owner team disappears, or for expired business-critical apps |
| `purpose` | ✅ | Why the app exists, in one sentence |
| `criticality` | | `standard` (default) or `business-critical`. After expiry, a business-critical app is escalated instead of being cut off. |
| `declared_tier` | | `low` / `medium` / `high`. The effective tier is max(declared, derived from the inventory's live permissions). |
| `approved_permissions` | ✅ | Permissions security approved. Anything the installation holds beyond these raises a warning. |
| `review_by` | ✅ | **Quoted** date (`"2027-01-31"`). At most 90 / 180 / 365 days ahead for high / medium / low tier. Fourteen days after it passes, an active app is quarantined automatically. |
| `status` | ✅ | `active`, `deprecated` (keeps access, loses bypass) or `quarantined` (only the archived `app-quarantine`) |
| `repositories` | ✅ | Repos the app may access. They must exist in `repositories.yaml`. |
| `bypass` | | `[require-pr]`: the app may push without a PR, on its granted repos only, while active |
| `ticket` | | Approval or change reference |
| `slug` | | Override the derived GitHub slug |

## Lifecycle in one paragraph

**Onboarding:**
1. Install the app on `app-quarantine` only.
2. Run `scripts/inventory.sh`.
3. Add its YAML and the inventory change in one PR.

**Decommissioning:**
1. `status: quarantined`, merge.
2. Suspend the app in the UI and watch for breakage.
3. Delete the YAML, merge.
4. Uninstall in the UI.

The CI delete guard blocks deleting a YAML whose app still has real access. Details: `docs/GOVERNANCE.md`.
