#!/usr/bin/env bash
# One-time, idempotent setup of everything around the pipeline that a human owner controls (D-004, docs/setup.md).
# Safe to re-run: each step converges to the documented state.
#
#   scripts/bootstrap.sh                   teams, quarantine repo, governance repo settings, environments, variables
#   scripts/bootstrap.sh --with-secrets    + prompt for the five environment secrets (values never echoed)
#   scripts/bootstrap.sh --with-ruleset    + the governance repo's main-branch ruleset (step 9: only once the
#                                            workflows have run, because a never-run required check can't pass)
#   scripts/bootstrap.sh --with-hcp        + create/verify the HCP Terraform workspace in local execution mode
#
# Needs: gh logged in as an org owner (scopes repo, admin:org), jq, curl. Configure with environment variables:
#   ORG (default delta-appgov), PREFIX (app slug prefix, default "$ORG-"), HCP_ORG (default $ORG),
#   WORKSPACE (default github-app-governance), REPO (default github-app-governance)
# Still manual (UI only): creating the org, creating and installing the apps, creating tokens.
set -euo pipefail

ORG="${ORG:-delta-appgov}"
PREFIX="${PREFIX:-$ORG-}"
HCP_ORG="${HCP_ORG:-$ORG}"
WORKSPACE="${WORKSPACE:-github-app-governance}"
REPO="${REPO:-github-app-governance}"
QUARANTINE="${QUARANTINE:-app-quarantine}"
TEAMS=(platform security product)
ACTIONS_APP_ID=15368 # GitHub Actions: required checks are pinned to it

with_secrets=false with_ruleset=false with_hcp=false
for arg in "$@"; do
  case "$arg" in
    --with-secrets) with_secrets=true ;;
    --with-ruleset) with_ruleset=true ;;
    --with-hcp) with_hcp=true ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

R="$ORG/$REPO"
log() { printf '\033[1m▸ %s\033[0m\n' "$*"; }

log "Owner teams (D-012): ${TEAMS[*]}"
for t in "${TEAMS[@]}"; do
  gh api "orgs/$ORG/teams/$t" >/dev/null 2>&1 || gh api -X POST "orgs/$ORG/teams" -f name="$t" -f privacy=closed >/dev/null
  # CODEOWNERS only accepts teams with write access to the repo
  gh api -X PUT "orgs/$ORG/teams/$t/repos/$R" -f permission=push >/dev/null
done

log "Quarantine repo $QUARANTINE: exists and archived (D-013)"
if ! gh api "repos/$ORG/$QUARANTINE" >/dev/null 2>&1; then
  gh repo create "$ORG/$QUARANTINE" --public --add-readme \
    --description "Parking repo for GitHub App installations. Contains no code. Managed by $REPO." >/dev/null
  gh repo edit "$ORG/$QUARANTINE" --enable-issues=false --enable-wiki=false --enable-projects=false >/dev/null
fi
[ "$(gh api "repos/$ORG/$QUARANTINE" --jq .archived)" = "true" ] || gh repo archive "$ORG/$QUARANTINE" --yes

log "Governance repo settings: squash merges only, delete merged branches"
gh repo edit "$R" --enable-squash-merge --enable-merge-commit=false --enable-rebase-merge=false --delete-branch-on-merge >/dev/null

log "Environments: plan (required reviewer), production and audit (main only)"
me="$(gh api user --jq .id)"
jq -n --argjson id "$me" '{wait_timer: 0, prevent_self_review: false, reviewers: [{type: "User", id: $id}], deployment_branch_policy: null}' |
  gh api -X PUT "repos/$R/environments/plan" --input - >/dev/null
for e in production audit; do
  jq -n '{deployment_branch_policy: {protected_branches: false, custom_branch_policies: true}}' |
    gh api -X PUT "repos/$R/environments/$e" --input - >/dev/null
  if ! gh api "repos/$R/environments/$e/deployment-branch-policies" --jq '.branch_policies[].name' | grep -qx main; then
    gh api -X POST "repos/$R/environments/$e/deployment-branch-policies" -f name=main -f type=branch >/dev/null
  fi
done

log "Repository variables"
gh variable set TF_CLOUD_ORGANIZATION --body "$HCP_ORG" --repo "$R"
gh variable set TF_WORKSPACE --body "$WORKSPACE" --repo "$R"
gh variable set GH_OWNER --body "$ORG" --repo "$R"
gh variable set APP_SLUG_PREFIX --body "$PREFIX" --repo "$R"

if $with_secrets; then
  log "Environment secrets (you'll be prompted; values are never echoed)"
  for pair in plan:TF_TOKEN_APP_TERRAFORM_IO plan:GH_TF_TOKEN production:TF_TOKEN_APP_TERRAFORM_IO production:GH_TF_TOKEN audit:GH_AUDIT_TOKEN; do
    env="${pair%%:*}" name="${pair#*:}"
    echo "  $env / $name"
    gh secret set "$name" --env "$env" --repo "$R"
  done
fi

if $with_ruleset; then
  log "Governance repo ruleset 'main' (D-009: 0 approvals; checks pinned to GitHub Actions)"
  ruleset="$(jq -n --argjson app "$ACTIONS_APP_ID" '{
    name: "main", target: "branch", enforcement: "active",
    bypass_actors: [{actor_id: 1, actor_type: "OrganizationAdmin", bypass_mode: "always"}],
    conditions: {ref_name: {include: ["~DEFAULT_BRANCH"], exclude: []}},
    rules: [
      {type: "deletion"},
      {type: "non_fast_forward"},
      {type: "pull_request", parameters: {
        required_approving_review_count: 0, dismiss_stale_reviews_on_push: true, require_code_owner_review: false,
        require_last_push_approval: false, required_review_thread_resolution: false, allowed_merge_methods: ["squash"]}},
      {type: "required_status_checks", parameters: {
        strict_required_status_checks_policy: true, do_not_enforce_on_create: false,
        required_status_checks: [{context: "validate", integration_id: $app}, {context: "plan", integration_id: $app}]}}
    ]}')"
  id="$(gh api "repos/$R/rulesets" --jq '.[] | select(.name == "main") | .id' | head -n1)"
  if [ -n "$id" ]; then
    gh api -X PUT "repos/$R/rulesets/$id" --input - <<<"$ruleset" >/dev/null && echo "  updated ruleset $id"
  else
    gh api -X POST "repos/$R/rulesets" --input - <<<"$ruleset" --jq '"  created ruleset \(.id)"'
  fi
fi

if $with_hcp; then
  log "HCP Terraform workspace $HCP_ORG/$WORKSPACE in local execution mode (D-002)"
  token="${TF_TOKEN_app_terraform_io:-$(jq -r '.credentials["app.terraform.io"].token // empty' ~/.terraform.d/credentials.tfrc.json 2>/dev/null)}"
  [ -n "$token" ] || { echo "  no HCP token: run 'terraform login' first" >&2; exit 1; }
  api="https://app.terraform.io/api/v2"
  hdr=(-H "Authorization: Bearer $token" -H "Content-Type: application/vnd.api+json")
  body="$(jq -n --arg n "$WORKSPACE" '{data: {type: "workspaces", attributes: {name: $n, "execution-mode": "local", "setting-overwrites": {"execution-mode": true}}}}')"
  if curl -sf "${hdr[@]}" "$api/organizations/$HCP_ORG/workspaces/$WORKSPACE" >/dev/null; then
    curl -sf -X PATCH "${hdr[@]}" -d "$body" "$api/organizations/$HCP_ORG/workspaces/$WORKSPACE" | jq -r '"  workspace exists, execution mode: " + .data.attributes."execution-mode"'
  else
    curl -sf -X POST "${hdr[@]}" -d "$body" "$api/organizations/$HCP_ORG/workspaces" | jq -r '"  created workspace, execution mode: " + .data.attributes."execution-mode"'
  fi
fi

log "Done. Manual steps left: create and install the apps (docs/setup.md §5), tokens (§6–7), then scripts/inventory.sh."
