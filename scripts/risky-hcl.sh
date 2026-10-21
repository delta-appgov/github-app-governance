#!/usr/bin/env bash
# Flags HCL that the plan approver must read before approving the `plan` environment (D-007): `terraform plan`
# runs this PR's code with the plan credentials, and these constructs can read them or send them elsewhere.
# It's a speed bump for the reviewer, not a control: a PR can edit this script too.
set -euo pipefail
cd "$(dirname "$0")/.."

patterns='data "external"|data "http"|provisioner "|local-exec|remote-exec|/proc/|filebase64|pathexpand|source *= *"'
hits="$(grep -rnE "$patterns" --include='*.tf' --include='*.tftest.hcl' terraform/ | grep -vE 'source *= *"integrations/github"' || true)"

if [ -z "$hits" ]; then
  echo "risky-hcl: nothing to flag"
  exit 0
fi
while IFS=: read -r file line text; do
  echo "::warning file=$file,line=$line,title=Read before approving the plan::$(echo "$text" | sed 's/^ *//')"
done <<<"$hits"
