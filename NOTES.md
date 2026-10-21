# Working notes

A raw journal written while building this: time spent, problems hit, how they were solved, and where answers came
from. It's kept on purpose, because the problem-solving process is part of what's being evaluated.

## Time log

| Date | Activity | Time |
|---|---|---|
| 2026-10-15 → 10-21 | Reading the assignment, design, independent design reviews, decision log, setup guide | *fill in* |
| 2026-10-21 | Setup: org, baseline, teams, repos, 4 apps, HCP, tokens, environments (17:07–17:56 local) | ~50 min |
| 2026-10-21 | Spike S1–S8, including rotating a leaked token (17:56–18:16 local) | ~20 min |
| 2026-10-21 | Terraform core, tests, scripts, workflows; PR #1 applied (18:16–18:45 local) | ~30 min |
| 2026-10-21 | Rework: wrong git identity → history rebuilt, repo recreated, PRs replayed (18:45–19:05 local, approx.) | ~20 min |
| 2026-10-21 | Demo trail #3–#13, incl. the delayed-run incident and its fix (19:05–19:38 local) | ~35 min |
| 2026-10-21 | Docs: README, GOVERNANCE.md, decision log, bootstrap script (19:38– local) | *fill in* |
| | **Total** (design time included) | *fill in* |

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
| S6 | Refresh on an uninstalled installation | Skipped in the spike (the provider source shows no 404 handling in Read). **Confirmed live later** during the incident: every plan failed with a 404 until the runbook was applied. | Runbook: `terraform state rm` (it works) |
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
- **Commits carried the wrong identity.** The machine's global `~/.gitconfig` held another account's name and email,
  so the first commits were authored by it. GitHub's squash merge then added it as `Co-authored-by`. Rewriting
  `main` wasn't enough: GitHub keeps every PR's commits, and only GitHub Support can delete a PR. Fix:
  1. A repo-local identity: `birylokacper` with the GitHub noreply email, and email privacy turned on so web merges
     use it too.
  2. Commits rebuilt with `git commit-tree`: same trees and timestamps, new author.
  3. The governance repo, the workload repos and the HCP workspace deleted and recreated.
  4. The PRs replayed.

  `scripts/bootstrap.sh` rebuilt the whole setup on the fresh repo in one run, which doubled as a test of the
  "point it at another org" path. Lesson: set the identity per repo (or with `includeIf` per directory) before
  the first commit.
- **zsh vs bash.** zsh doesn't word-split unquoted expansions, so `${parent:+-p "$parent"}` became a single argument
  and the first history rewrite failed. Scripts now always run under `bash` explicitly.
- **A delayed push event re-applied stale state (incident, #9).** During a GitHub incident ("Delays for Pull
  Requests and Webhook deliveries"), #6's merge produced no run at first. #7's apply then applied both changes,
  because it re-plans the full state. Four minutes later the delayed run for #6 arrived. It checked out its own,
  **older** commit and re-applied it, giving the already-quarantined legacy-linter two repos back.
  - **Contained by:** the app was suspended (the grant was never usable), and the **delete guard** then blocked
    #8's apply ("would be deleted while it still has access").
  - **Then the S6 case happened for real.** After the uninstall, every plan failed with a 404 on the uninstalled
    installation. The documented runbook fixed it: `terraform state rm`, then a no-op plan.
  - **Fix (D-014):** the apply checks out the latest `main`, not the trigger commit, so late or replayed runs
    converge instead of rolling back.
  - **Lesson:** push-triggered GitOps is edge-triggered. Correctness has to come from level-based reconciliation.
- **Output-only "drift".** `-detailed-exitcode` returns 2 for output-only differences too. The drift audit now counts
  real resource changes from the plan JSON instead.
- **Time zones in the inventory.** The same installation's `created_at` came back as `+02:00` with a classic PAT and
  as `Z` with the fine-grained audit token, so the audit flagged a change that wasn't one. `inventory.sh` now sends
  `Time-Zone: Etc/UTC`.

## Resources used

- **Primary sources:**
  - the `integrations/github` provider docs and its **Go source**, which settled how Read, Create and Delete
    really behave
  - the provider's GitHub issues (#2103, #3576, #3687)
  - GitHub REST docs and changelog (2026-10-13 `installation_repositories` permission)
  - HashiCorp Terraform and HCP Terraform docs
- **Hands-on verification:** the spike above, run against the real org before writing the real config.
- **AI assistance:** Claude Code was used for research, three independent design reviews (a platform engineer, a
  security architect, a critical interview panel), and drafting code and docs. Every claim the design relies on
  was checked against the primary sources above or the spike, and every change went through the same PR pipeline.
