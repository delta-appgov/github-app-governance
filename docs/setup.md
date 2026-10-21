# Setup guide — the operational (non-code) work

This guide prepares everything the code needs: a GitHub org, its security baseline, owner teams, repos, dummy
GitHub Apps, HCP Terraform, tokens, and the governance repo's environments. It takes about **45–60 minutes**, most of
it clicking through UIs.

Reviewers: this is also how you point the solution at **your own org**. Change the four variables below and follow
the same steps.

```bash
export ORG=delta-appgov              # GitHub org (names are unique across GitHub)
export PREFIX=delta-appgov-          # prefix for app names (app names are unique across GitHub too; max 34 chars)
export HCP_ORG=delta-appgov          # HCP Terraform org (separate namespace; add a suffix if it's taken)
export WORKSPACE=github-app-governance
```

> The org is a throwaway sandbox for a take-home assignment. Give it a description that says so (step 1), so
> nobody mistakes it for an official organization.

> **Shortcut:** `scripts/bootstrap.sh` automates the command-line parts. That's steps 3 and 4a (including
> archiving), the repo settings in 4b, and step 8 (`--with-secrets` prompts for the values). It also covers step 9
> (`--with-ruleset`) and the HCP workspace from step 6 (`--with-hcp`). It's idempotent, so it's safe to re-run.
> Still manual: creating the org (1), the baseline settings (2), the apps (5), signing up for HCP and its tokens
> (6) and the GitHub tokens (7).

---

## 0. Before you start (laptop)

- [ ] **2FA is on** for your GitHub account. The org will require it.
- [ ] **Terraform ≥ 1.11.** Homebrew's default formula is frozen at 1.5.7, so install HashiCorp's own:
  ```bash
  brew uninstall terraform            # removes the old 1.5.7
  brew tap hashicorp/tap && brew install hashicorp/tap/terraform
  terraform version
  ```
- [ ] **GitHub CLI** logged in, with the extra scope needed to create teams:
  ```bash
  gh auth login                        # GitHub.com → HTTPS → browser
  gh auth refresh -h github.com -s admin:org
  gh auth status
  ```
- [ ] `jq` installed (`brew install jq`).
- [ ] Start the **time log** in `NOTES.md`. Setup counts toward the 8 hours.

---

## 1. Create the GitHub org (Free plan)

1. Open https://github.com/account/organizations/new?plan=free.
2. Org name `$ORG`, your contact email, belongs to "My personal account". Skip inviting members.
3. Open https://github.com/organizations/$ORG/settings/profile and set the description:
   *"Sandbox for a take-home assignment (GitHub App governance). Not an official organization."*

## 2. Org security baseline

All of these live under **Org → Settings**.

| Where | Setting | Why |
|---|---|---|
| Authentication security | **Require two-factor authentication** | Baseline for any org |
| Member privileges | Base permissions: **Read** | Least privilege for members |
| Third-party access → OAuth application policy | Check that **access restrictions are on** (the default for new orgs) | OAuth apps are an adjacent risk |
| Personal access tokens → Settings | **Allow** fine-grained tokens and **allow** classic tokens | Classic PATs are required (D-005); a fine-grained token is used for the audit. Restricting classic PATs later would break the pipeline, a known trade-off. |
| Actions → General → Policies | "Allow *org*, and select non-*org*, actions": tick **Allow actions created by GitHub**, then allow `hashicorp/setup-terraform@*`. Tick **Require actions to be pinned to a full-length commit SHA** if offered. | Supply-chain baseline |
| Actions → General → Fork pull request workflows | **Require approval for all external contributors** | Fork PRs must never run unattended |
| Actions → General → Workflow permissions | **Read repository contents and packages**; untick **Allow GitHub Actions to create and approve pull requests** | `GITHUB_TOKEN` is read-only by default; jobs ask for more explicitly |

## 3. Owner teams (D-012)

These stand in for teams synced from an identity provider. Terraform only reads them.

```bash
for t in platform security product; do
  gh api -X POST "orgs/$ORG/teams" -f name="$t" -f privacy=closed --jq '.slug'
done
```

Planned ownership: release-bot → `platform`, ci-reporter → `product`, legacy-linter → `product`. `security` reviews
high-tier apps.

## 4. Repositories created by hand

Only two repos are created manually. Terraform creates the workload repos (`service-a`, `service-b`, `service-c`) later.

**a) The quarantine/parking repo (D-013).** Apps need a repo to land on before Terraform manages them. The repo is
**archived**, so it's read-only: an app parked there can't write anything. It can still be added to and removed
from installations. Terraform only reads this repo and warns if it's ever unarchived.

```bash
gh repo create "$ORG/app-quarantine" --public --add-readme \
  --description "Parking repo for GitHub App installations. Contains no code. Managed by github-app-governance."
gh repo edit "$ORG/app-quarantine" --enable-issues=false --enable-wiki=false --enable-projects=false
gh repo archive "$ORG/app-quarantine" --yes
```

**b) The governance repo (this one).** From the local folder:

```bash
cd github-app-governance
git init -b main
git add . && git commit -m "docs: decision log, setup guide, notes skeleton"
gh repo create "$ORG/github-app-governance" --public --source . --remote origin --push \
  --description "GitOps-managed governance of GitHub App access"
```

Then, in the governance repo's **Settings → General → Pull Requests**: allow **squash merging** only, and tick
**Automatically delete head branches**.

Give the owner teams write access, which CODEOWNERS requires before it accepts a team:

```bash
for t in platform security product; do
  gh api -X PUT "orgs/$ORG/teams/$t/repos/$ORG/github-app-governance" -f permission=push
done
```

## 5. Dummy GitHub Apps (owned by the org)

For each row, open https://github.com/organizations/$ORG/settings/apps/new and fill in:

- **GitHub App name:** `${PREFIX}<name>` from the table
- **Homepage URL:** `https://github.com/$ORG/github-app-governance`
- **Webhook:** untick **Active** (these apps never receive events)
- **Repository permissions:** exactly the ones in the table (*Metadata: Read-only* is added automatically)
- **Where can this GitHub App be installed?** **Only on this account**

Then click **Create GitHub App**. You don't need a private key, because nothing ever runs as these apps.

| App name | Repository permissions | Install on (left sidebar → **Install App** → Install) |
|---|---|---|
| `${PREFIX}release-bot` | Contents: **Read and write** | **Only select repositories** → `app-quarantine` |
| `${PREFIX}ci-reporter` | Checks: **Read and write**; Contents: **Read-only** | **Only select repositories** → `app-quarantine` |
| `${PREFIX}legacy-linter` | Pull requests: **Read and write** | **Only select repositories** → `app-quarantine` |
| `${PREFIX}stray-bot` | Issues: **Read-only** | **All repositories**, on purpose. This is the "app nobody remembers installing". It is never registered, and the audit has to find it. |

Check the result. You should see four installations, three `selected` and one `all`:

```bash
gh api "orgs/$ORG/installations" --jq '.installations[] | [.app_slug, .id, .repository_selection] | @tsv'
```

## 6. HCP Terraform (Free tier, no payment card) — D-001, D-002

1. Sign up at https://app.terraform.io/public/signup/account (email only), then confirm the email.
2. Create an organization named `$HCP_ORG`. Under **Settings → Plan & billing**, confirm it says **Free**.
3. Create a workspace: **Workspaces → New → CLI-driven workflow**, named `$WORKSPACE`.
4. Set **Workspace → Settings → General → Execution Mode: Custom → Local** and save. ⚠️ This must happen **before** the
   first CI run (D-002).
5. Add **no** variables to the workspace. Credentials stay in GitHub (D-002).
6. Under **Account settings → Tokens**, create two API tokens with a **30-day expiry**: `gha-plan` and `gha-apply`.
   Keep them for step 8.
7. Log the laptop in for local runs: `terraform login` (it opens the browser and stores its own token).

## 7. GitHub tokens (D-005, an accepted trade-off)

All three tokens are created on **your** account with a **30-day expiry**. Write the expiry dates in `NOTES.md`.

| Token | Where | Settings |
|---|---|---|
| `delta-appgov-plan` (classic) | https://github.com/settings/tokens/new | Scopes: **repo**, **read:org** |
| `delta-appgov-apply` (classic) | same | Scopes: **repo**, **read:org** |
| `delta-appgov-audit` (fine-grained) | https://github.com/settings/personal-access-tokens/new | Resource owner: **$ORG**. Repository access: **Public repositories**. Organization permissions → **Administration: Read-only**. If the org asks for approval, approve it under **Org → Settings → Personal access tokens → Pending requests**. |

Why classic? The provider reads an app's repositories through an endpoint that accepts user tokens only (D-005).

## 8. Governance repo: environments, secrets, variables

`scripts/bootstrap.sh` will automate this step later. For now, use **Repo → Settings → Environments → New environment**:

| Environment | Protection | Secrets |
|---|---|---|
| `plan` | **Required reviewers:** you (leave "Prevent self-review" unticked, since you're the only maintainer: D-009). Deployment branches: **No restriction** (PR refs must be allowed). | `TF_TOKEN_app_terraform_io` = HCP `gha-plan`; `GH_TF_TOKEN` = `delta-appgov-plan` |
| `production` | Deployment branches: **Selected branches → `main`**. No reviewers: the merge is the approval. | `TF_TOKEN_app_terraform_io` = HCP `gha-apply`; `GH_TF_TOKEN` = `delta-appgov-apply` |
| `audit` | Deployment branches: **Selected branches → `main`** | `GH_AUDIT_TOKEN` = `delta-appgov-audit` |

Set the secrets from the terminal. `gh` prompts for each value, so tokens never land in your shell history:

```bash
R="$ORG/github-app-governance"
gh secret set TF_TOKEN_app_terraform_io --env plan       --repo "$R"
gh secret set GH_TF_TOKEN               --env plan       --repo "$R"
gh secret set TF_TOKEN_app_terraform_io --env production --repo "$R"
gh secret set GH_TF_TOKEN               --env production --repo "$R"
gh secret set GH_AUDIT_TOKEN            --env audit      --repo "$R"

gh variable set TF_CLOUD_ORGANIZATION --body "$HCP_ORG"   --repo "$R"
gh variable set TF_WORKSPACE          --body "$WORKSPACE" --repo "$R"
gh variable set GH_OWNER              --body "$ORG"       --repo "$R"   # optional: defaults to the repo's owner
gh variable set APP_SLUG_PREFIX       --body "$PREFIX"    --repo "$R"
```

(Secret and variable names can't start with `GITHUB_`, because GitHub reserves that prefix. So the workflow maps
`GH_TF_TOKEN` to the provider's `GITHUB_TOKEN` env var, and `GH_OWNER` to the org Terraform manages. If `GH_OWNER`
isn't set, it falls back to the org that owns this repo.)

## 9. Governance repo ruleset — LATER, once the workflows are merged

Do this only after the first PR adds `validate` and `plan`. A required check that has never run can't be satisfied.

**Repo → Settings → Rules → Rulesets → New branch ruleset:**

- Name `main`; Enforcement **Active**; Target: **default branch**
- Bypass list: **Organization admin**, for emergencies only (every bypass is visible)
- Rules:
  - **Restrict deletions**
  - **Block force pushes**
  - **Require a pull request before merging**, with required approvals **0** (D-009)
  - **Require status checks to pass**: tick **Require branches to be up to date**, then add `validate` and `plan`
    with source **GitHub Actions**

## 10. Verify

```bash
gh api "orgs/$ORG/installations" --jq '.installations | length'   # 4
gh api "orgs/$ORG/teams" --jq '.[].slug'                           # platform, product, security
gh repo list "$ORG"                                                # app-quarantine, github-app-governance
gh secret list --env plan --repo "$ORG/github-app-governance"      # 2 secrets
terraform version                                                  # ≥ 1.11
```

## 11. Housekeeping

- Put calendar reminders a few days before each token's expiry, and regenerate tokens before the interview demo if needed.
- **After the hiring process:**
  1. Revoke the two classic PATs, the fine-grained PAT and both HCP tokens.
  2. Delete the four apps.
  3. Delete the HCP org.
  4. Optionally delete the GitHub org.
