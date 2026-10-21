#!/usr/bin/env bash
# init + plan + text/JSON renderings. Shared by the plan, apply and drift jobs.
#
#   scripts/tf-plan.sh [extra plan args, e.g. -detailed-exitcode]
#   → terraform/plan.log, terraform/tfplan, terraform/plan.txt, terraform/plan.json
#   Exit code: terraform plan's own (1 = error; 2 = changes, with -detailed-exitcode).
set -euo pipefail
cd "$(dirname "$0")/../terraform"

terraform init -lockfile=readonly -no-color

set +e
terraform plan -lock-timeout=5m -no-color -out=tfplan "$@" 2>&1 | tee plan.log
status=${PIPESTATUS[0]}
set -e

if [ "$status" -ne 1 ]; then
  terraform show -no-color tfplan >plan.txt
  terraform show -json tfplan >plan.json
fi
exit "$status"
