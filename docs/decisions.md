# Decision log

Short records of the trade-offs made in this solution. Each entry says what we chose, what we gave up and when
we'd revisit it. The assignment asks for decisions and their pros/cons to be explicit, so they live here rather
than only in someone's head.

---

## D-001 — Terraform state in HCP Terraform (Free tier) instead of AWS S3 + GitHub OIDC

- **Status:** Accepted — 2026-10-21
- **Scope:** where Terraform state lives and how CI authenticates to it. Where Terraform *executes*
  (GitHub runner vs HCP worker) is a separate decision.

### Context

The GitOps pipeline runs on GitHub-hosted runners, which start from a clean machine every time. Terraform state
must therefore live in a shared, locked, versioned remote backend that those runners can reach.

The preferred enterprise pattern was **S3 backend + GitHub Actions OIDC**: the workflow swaps its short-lived
OIDC token for a temporary AWS role, so there are no stored cloud credentials, and separate plan/apply roles get
least-privilege access.

Constraint: this is a homework project in a throwaway GitHub org, and we chose **not to register a payment card
with any cloud provider**. Every AWS, GCP and Azure account requires one.

### Options considered

| Option | Why not (or why) |
|---|---|
| **AWS S3 + GitHub OIDC** | Best security model: no stored credentials, claim-pinned IAM roles. Rejected only because an AWS account needs a payment card. |
| **LocalStack (S3 emulator)** | GitHub-hosted runners can't reach a LocalStack on a laptop. LocalStack run as a CI service container is wiped after every job, so state would be lost between runs. OIDC against LocalStack validates nothing, so it would be security theatre. Using a self-hosted runner to reach a laptop is a known risk for public repos (anyone's PR could run code on the machine). Rejected for CI; not needed locally either (see below). |
| **Postgres free tier (`pg` backend, e.g. Neon/Supabase)** | No card, has locking. But it's a non-standard backend, has no state-history UI, and uses a static connection string. Rejected. |
| **GitLab-managed Terraform state** | Adds a second VCS platform just to store state, with a static token. Rejected. |
| **Scalr / Spacelift free tiers** | Full Terraform automation platforms; more moving parts than needed. They'd also tend to replace the GitHub workflow the assignment explicitly asks for. Rejected. |
| **State committed to the repo** | No locking, conflicting writes, and state metadata published in a public repo. Rejected. |
| **HCP Terraform, Free tier** ✅ | No card needed. Locking, state versioning, encryption at rest and a run/state history UI are built in. No infrastructure to bootstrap. It's the vendor's own backend for the tool the role uses. **Chosen.** |

### What we gain

- **No bootstrap infrastructure.** No bucket, IAM roles, OIDC identity provider or bucket policies to create, secure
  and explain. This saves roughly an hour of the 8-hour budget for the actual governance work.
- **Built-in state safety.** Locking, version history with rollback, and encryption at rest, without configuring any of it.
- **Easy for reviewers to reproduce.** An HCP account is a free email sign-up. The `cloud` block is configured from
  environment variables (`TF_CLOUD_ORGANIZATION`, `TF_WORKSPACE`), so no code edits are needed. Reviewers who don't
  want HCP can add a one-line `backend_override.tf` and run with local state on their own machine.
- **No overlapping applies.** State locking stops two applies from writing state at the same time. If runs execute
  on HCP workers, the Free tier's one-concurrent-run limit also queues them.

### What we give up (accepted costs)

1. **No OIDC — CI holds a static credential.**
   - HCP Terraform's API doesn't accept GitHub Actions OIDC tokens (an open, unanswered feature request as of May 2026).
   - So the workflow stores an HCP API token as a GitHub secret.
   - A static token can be stolen and reused until it expires or is revoked. OIDC tokens are bound to a single job
     and last minutes.
2. **No least-privilege split on the Free tier.**
   - Team management appears not to be available on Free (HashiCorp's plan table contradicts itself; to be confirmed
     during setup). If so, the token is effectively owner-level for the HCP org.
   - It can read and write state, start runs and edit workspace variables.
   - With S3 + OIDC we would have had a read-mostly plan role and a write apply role.
3. **Third-party SaaS dependency.**
   - If HCP Terraform is down, plan/apply stops. GitHub itself keeps working, so break-glass changes in the GitHub UI
     remain possible and get reconciled by PR afterwards.
   - State is stored with HashiCorp, not in an account we control.
4. **Free-tier ceilings.**
   - 500 managed resources and one concurrent run. The demo uses about 30 resources.
   - At Delta's scale (hundreds of apps, plus repo settings and rulesets), the resource cap and the single-run queue
     would push us to a paid tier or a self-managed backend.

### Mitigations in this solution

- The HCP token is created **with an expiry date**. It is stored as a GitHub **environment** secret, not a plain
  repository secret. Rotation steps are in the README.
- State holds org metadata (repo names, installation IDs, app permissions) but **no credentials**. The GitHub token
  is never written to state.
- The residual risk is spelled out in the security section: whoever can run a PR plan can reach the pipeline's credentials.
- **Exit path:** `terraform init -migrate-state` to any other backend, then prove the move with a no-op plan. The
  `cloud` block is the only HCP-specific code.

### What we'd do in an enterprise setting

- **Preferred:** move state to a backend in our own cloud account (S3/GCS/Azure Blob) with **GitHub OIDC**.
  - Separate plan and apply roles.
  - Trust policies pinned to the repository, the `production` environment and, ideally, the calling workflow
    (`job_workflow_ref`).
- **If staying on HCP Terraform:** a paid tier with team-scoped tokens and self-hosted agents. CI would get
  **short-lived HCP tokens issued by Vault** (Vault's Terraform Cloud secrets engine), with Vault itself trusting
  GitHub OIDC. That removes long-lived secrets from GitHub entirely.

### Revisit when

- The workspace approaches ~400 managed resources, or the single-run queue slows PRs noticeably.
- HCP Terraform starts accepting GitHub OIDC (or another workload-identity login) for its API.
- A compliance requirement says state must live in our own cloud account.
- This moves from a homework org to a real one. Then the enterprise option above becomes the default.

### Sources

- HCP Terraform Free tier (500 managed resources, unlimited users):
  https://www.hashicorp.com/en/blog/continuing-hcp-terraform-s-enhanced-free-tier-experience
- Plan limits (one concurrent run on Free): https://developer.hashicorp.com/terraform/cloud-docs/overview
- Pricing ("no credit card required"): https://cloud.hashicorp.com/products/terraform/pricing
- Open request for GitHub OIDC → HCP Terraform API (unanswered, May 2026):
  https://discuss.hashicorp.com/t/deep-dive-hcp-terraform-api-queuing-vs-tfc-agent-polling-oidc-support-for-gha-ecosystem-actions/77435

---

## D-002 — HCP Terraform in *local* execution mode

- **Status:** Accepted — 2026-10-21
- **Decision:** GitHub Actions runs `terraform plan` / `apply`. HCP Terraform only stores and locks state. The HCP
  workspace holds **no variables**.
- **Why:**
  - The assignment asks for a GitHub workflow that plans on PR and applies on merge.
  - In remote (CLI-driven) mode, the PR job would hold a run-capable HCP token (owner-level on Free). It could start
    an *apply* from an unreviewed branch.
  - In remote mode the GitHub token would sit in workspace variables, where plan-time code on HCP's workers can read it.
  - Remote runs upload only the current directory unless a working directory is configured. `../apps` would
    silently disappear, and the plan would try to remove every app's access.
- **Cost:** Logs live in Actions, not HCP's run UI. The credentials live in GitHub secrets.
- **Revisit when:** a paid tier with agents and team-scoped tokens is available.

## D-003 — Committed inventory instead of a live lookup

- **Status:** Accepted — 2026-10-21
- **Decision:** `inventory/inventory.json` is generated by `scripts/inventory.sh` and committed. Per app slug, it
  holds the installation ID, app ID, permissions and repository selection. Terraform reads the file, not the API.
- **Why:**
  - Plans are deterministic and reviewable.
  - The plan job doesn't need org-owner rights to list installations.
  - A newly installed app shows up as a diff in a PR.
  - The same file feeds the daily audit and the brownfield scaffolding.
  - The live alternatives pull reality into desired state at plan time. The `github_rest_api` data source reads only
    one page. `github_organization_app_installations` needs owner rights while planning.
- **Cost:**
  - The file can go stale, so the daily audit compares live and committed and opens an issue.
  - Onboarding an app has one extra step.

## D-004 — The governance repo's protections are set by a human-run script, not by the pipeline

- **Status:** Accepted — 2026-10-21
- **Decision:**
  - `scripts/bootstrap.sh` (idempotent, using `gh api`) sets the governance repo's ruleset, environments and secrets.
  - The main Terraform config never manages the governance repo, and a static check rejects any resource that
    targets it.
  - The daily audit verifies those settings.
- **Why:** A pipeline shouldn't apply the rules that constrain it. Managing secrets in Terraform would also write
  them into state.
- **Honest limit:** The pipeline token belongs to an org owner (D-005), so this separation is *procedural*, not
  technical. A malicious change that is approved and merged could still reach the repo. The controls are the plan
  approval gate (D-007), the required checks and the daily audit.

## D-005 — The pipeline uses the maintainer's own classic PATs (accepted trade-off)

- **Status:** Accepted — 2026-10-21
- **Context:**
  - The provider resource `github_app_installation_repositories` reads through
    `GET /user/installations/{id}/repositories`. That endpoint accepts **user tokens only**: not fine-grained PATs,
    not GitHub App tokens.
  - GitHub's 2026-10-13 `installation_repositories:write` permission covers adding and removing repos only, not this
    read. So a **classic** PAT is required.
  - The right owner for that token is a dedicated machine account (GitHub's terms allow one per person), ideally not
    an org owner.
- **Decision:** For this homework, use the maintainer's own account:
  - two classic PATs, `plan` and `apply`
  - scopes `repo` + `read:org`
  - 30-day expiry
  - stored as GitHub *environment* secrets
  - plus one read-only fine-grained PAT for the audit
- **What we give up:**
  1. **Reach beyond this org.** A classic PAT isn't scoped to one org. It reaches every repo the maintainer's account
     can reach, in every org and in the personal account.
  2. **Owner-level power.** The maintainer is an org owner. The token can do anything the `repo` scope allows here,
     including in the governance repo.
  3. **No attribution.** In the audit log, pipeline actions and human actions show the same actor.
  4. **No privilege split.** The plan and apply tokens can be revoked separately, but they're equally powerful.
     Classic scopes have no read-only `repo`.
- **Mitigations:**
  - 30-day expiry, and every token revoked after the interview.
  - Minimal scopes: teams are created during setup (D-012), so `admin:org` isn't needed.
  - The apply token is only reachable from `main`.
  - The plan token sits behind the approval gate (D-007).
  - Only one person has push access, and PRs from forks get no secrets.
  - While the tokens are live, the maintainer's account should have no sensitive access elsewhere.
- **Enterprise target:**
  - A machine user that is **not** an org owner, with admin only on the repos it manages.
  - Or a GitHub App using `installation_repositories:write`, once the provider no longer needs a user token for reads.
  - Short-lived credentials, and separate identities for plan and apply.

## D-006 — Decommission order and the delete guard

- **Status:** Accepted — 2026-10-21
- **Decision:**
  - An app is retired in this order: quarantine → delete its YAML → uninstall in the UI.
  - A CI check on the plan JSON fails any delete or replacement of an installation resource unless the app's current
    repos are exactly `[app-quarantine]`.
  - No `removed` blocks.
- **Why:**
  - The provider's delete leaves one *random* repo attached.
  - Its read doesn't handle a 404, so uninstalling first breaks every plan.
  - A `removed` block can't target a single `for_each` key.
  - The guard also catches an empty or mis-pathed registry.

## D-007 — PR plans need an approval

- **Status:** Accepted — 2026-10-21
- **Decision:** The `plan` job runs in a `plan` environment with a required reviewer.
- **Why:** `terraform plan` executes the PR's HCL. A function like `filebase64("/proc/self/environ")` can print the
  job's secrets into the plan output without touching the workflow at all. The approval means a human has looked at
  the diff before any secrets are exposed to it.
- **Cost:** One extra click per PR.
- **Revisit when:** plans move to a dedicated Terraform runner (TACOS) or a central, locked-down reusable workflow.

## D-008 — Expiry is enforced in Terraform

- **Status:** Accepted — 2026-10-21
- **Decision:** Once `review_by` plus 14 days' grace has passed, the app's effective status becomes `quarantined` on
  the next apply. `business-critical` apps raise a warning and escalate instead.
- **Why:** A reminder or a bot PR that nobody merges enforces nothing.
- **Cost:** An unrelated merge can quarantine an expired app. To soften that, 30 days of warnings come first, in plan
  comments and audit issues.

## D-009 — Zero required approvals on the governance repo (accepted trade-off)

- **Status:** Accepted — 2026-10-21
- **Context:** The demo org has one maintainer, and GitHub doesn't let PR authors approve their own PRs. Requiring an
  approval would force an admin bypass on every merge. That would also hide whether the GitOps flow really works.
- **Decision:**
  - The ruleset requires a PR, an up-to-date branch, and passing `validate` + `plan` checks (pinned to GitHub
    Actions as their source).
  - It requires **0 approvals**.
  - The human checkpoint is the `plan` environment approval (D-007).
  - Org admins can still bypass, for emergencies only.
- **What we give up:**
  - No four-eyes review.
  - CODEOWNERS is informational, not enforced.
  - One person can change any app's access alone.
- **Mitigations:** Required checks, the delete guard, the plan approval, public PR history, the daily audit.
- **Enterprise target:**
  - At least 1 approval, and 2 for high-tier apps.
  - Required code-owner review, with security approving high-tier apps.
  - "Prevent self-review" on environments.

  Here that's one Terraform variable (`required_approvals`) plus one setting in the governance repo's ruleset.

## D-010 — Public repositories

- **Status:** Accepted — 2026-10-21
- **Decision:** Every repo in the demo org is public.
- **Why:** On GitHub Free, rulesets, environment protection rules and environment secrets only work on public repos.
  Nothing sensitive is stored in them.
- **Enterprise target:** Private repos on Team or Enterprise.

## D-011 — Scope cuts for the 8-hour budget

- **Status:** Accepted — 2026-10-21
- **Not built (documented as roadmap):**
  - a governance-bot GitHub App, and bot-opened PRs
  - creating the apps from manifests
  - two provider aliases (App auth + PAT)
  - OPA/conftest policies
  - merge queue
  - audit-log streaming
  - splitting state per business unit
- **Why:** None is required by the acceptance criteria, and each would cost more time than it demonstrates within
  8 hours.

## D-012 — Owner teams are created during setup and read by Terraform

- **Status:** Accepted — 2026-10-21
- **Decision:** Teams such as `platform`, `security` and `product` are created by the maintainer during setup.
  Terraform reads them and warns when an app's owner team doesn't exist.
- **Why:** It mirrors an enterprise, where teams come from the identity provider. It also keeps the pipeline token at
  `read:org` instead of `admin:org`.

## D-013 — `app-quarantine` is created during setup, then imported

- **Status:** Accepted — 2026-10-21
- **Decision:** The quarantine repo is created by hand during setup, then adopted into Terraform with an `import` block.
- **Why:** An app must be installed on some repo before Terraform can manage it, so this repo has to exist first. It
  also demonstrates the import pattern for adopting Delta's existing repos.
