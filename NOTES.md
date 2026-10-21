# Working notes

A raw journal written while building this: time spent, problems hit, how they were solved, and where answers came
from. It's kept on purpose, because the problem-solving process is part of what's being evaluated.

## Time log

| Date | Activity | Time |
|---|---|---|
| 2026-10-15 → 10-21 | Reading the assignment, design, independent design reviews, decision log, setup guide | *fill in* |
| 2026-10-21 | Setup: org, baseline, teams, repos, 4 apps, HCP, tokens, environments (17:07–17:56 local) | ~50 min |
| 2026-10-21 | Spike S1–S8, including rotating a leaked token (17:56–18:16 local) | ~20 min |
| | Terraform core | |
| | Workflows + scripts | |
| | Demo PRs | |
| | Docs | |
| | **Total** | |

## Token expiry

| Token | Expires |
|---|---|
| GitHub classic `delta-appgov-plan` | |
| GitHub classic `delta-appgov-apply` | |
| GitHub fine-grained `delta-appgov-audit` | |
| HCP `gha-plan` | |
| HCP `gha-apply` | |

## Spike results (what I tested, what happened, what it changed)

Run on 2026-10-21 against `delta-appgov`. Throwaway config: provider `integrations/github` 6.13.0, Terraform
1.16.6, local state, apps release-bot and legacy-linter, temporary repos `spike-a`, `spike-b`, `spike-archived`.

| # | Question | Result | Design impact |
|---|---|---|---|
| S1 | Are classic scopes `repo` + `read:org` enough? | ✅ Creating repos, reading a team, changing installation repos and creating a ruleset with an Integration bypass all worked | No extra scopes (D-005 stands) |
| S2 | Quarantine swap in one apply | ✅ `[spike-a, spike-b]` → `[app-quarantine]` in one apply, no 422. The grant `[app-quarantine]` → `[spike-a, spike-b]` also worked, so the provider **adds before it removes**. The bypass was removed in the same apply (ruleset `depends_on` the access resource). | One-step quarantine is safe |
| S3 | Can an archived repo be added to an installation? | ✅ Add (204) and remove (204) both work. ⚠️ Provider bug: *creating* a repo with `archived = true` fails ("403 Repository was archived so is read-only"); the provider archives the repo, then tries to PATCH it. | `app-quarantine` can be archived, so apps parked there can't write. Never create repos with `archived = true`. |
| S4 | Integration bypass on a repo where the app isn't installed | ✅ Expected failure: "422 … integration must be part of the ruleset source or owner organization". The second plan after a successful bypass showed no perpetual diff (#3687 not hit). | Per-repo bypass lists + `depends_on` confirmed |
| S5 | Refresh on a suspended installation | ✅ Refresh works, plan "No changes". A suspended installation's repos can also still be **changed** (PUT/DELETE 204). | Break-glass = suspend; the quarantine PR still applies while suspended |
| S6 | Refresh on an uninstalled installation | Skipped. The provider source shows no 404 handling in Read. | Runbook: `terraform state rm` |
| S7 | HCP local mode via env vars; override switch | ✅ `cloud {}` + `TF_CLOUD_ORGANIZATION` / `TF_WORKSPACE` initialized and planned locally; the workspace stayed untouched (0 resources). `local_override.tf` with `backend "local"` replaced the cloud block. | Reviewer path confirmed |
| S8 | Can a read-only token list org installations? | Partial. The classic `repo` + `read:org` token **can** (HTTP 200, 4 installations). The fine-grained audit token isn't tested yet; the audit workflow's first run will test it. | D-003's rationale updated |

Other findings:
- An existing installation is adopted by a plain **create**, with no import needed: Create reconciles the repo set.
- `gh`'s own login token (`gho_…`, an OAuth-app token) is **rejected** by `/user/installations/...`; only PATs, GitHub App user tokens and basic auth work. Scripts must pass a PAT.
- Deleting a repo needs the `delete_repo` scope, which the pipeline doesn't have. So `archive_on_destroy = true` is required, and the pipeline can never delete a repo.
- Cleanup procedure: put each app back on `app-quarantine`, `terraform state rm` the installation resources, then destroy the rest. Destroying an installation resource directly would have left a random repo attached.

## Problems and how I solved them

- **A token leaked into a session log.** A local token file was `source`d by a shell, and a bare token line got
  echoed in the "command not found" error. Fix: revoked and regenerated the token within minutes. The file is now
  `chmod 600` and holds only the raw token, which scripts read with `head -n1` and never execute. Lesson: never
  source secret files, and treat any accidental print as a leak.
- **`GITHUB_` prefix is reserved.** GitHub rejects Actions secret and variable names starting with `GITHUB_` (HTTP 422).
  Renamed the variable to `GH_OWNER` and mapped it to the provider's env var inside the workflow.

## Sources
