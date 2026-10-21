# Working notes

A raw journal written while building this: time spent, problems hit, how they were solved, and where answers came
from. It's kept on purpose, because the problem-solving process is part of what's being evaluated.

## Time log

| Date | Activity | Time |
|---|---|---|
| | Setup (org, apps, HCP, tokens, environments) | |
| | Spike S1–S8 | |
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

- **S1** — classic scopes `repo` + `read:org` sufficient?
- **S2** — quarantine swap in one apply (add before remove)?
- **S3** — archived quarantine repo can be added to an installation?
- **S4** — Integration bypass actor on a repo where the app isn't installed?
- **S5** — refresh on a suspended installation?
- **S6** — refresh on an uninstalled installation?
- **S7** — HCP local mode via env vars; `local_override.tf` switch?
- **S8** — fine-grained read-only token lists org installations?

## Problems and how I solved them

## Sources
