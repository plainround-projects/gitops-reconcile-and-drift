#!/usr/bin/env bash
# The whole lesson as one scripted run (steps 2 to 5 and the bad manifest), printing what the controller
# does at each step. `make up` must have finished first. It starts from a clean demo.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

step() { printf '\n==== %s ====\n' "$*"; }

"${ROOT}/scripts/reset.sh"
step "Step 2: change it through Git"
"${ROOT}/scripts/runbook/02-change-through-git.sh"
step "Step 3a: drift it by hand, self-heal off"
"${ROOT}/scripts/runbook/03-drift.sh" off
step "Step 3b: drift it by hand, self-heal on"
"${ROOT}/scripts/runbook/03-drift.sh" on
step "Step 4a: delete the ConfigMap's file, prune off"
"${ROOT}/scripts/runbook/04-prune.sh" off
step "Step 4b: the same deletion, prune on"
"${ROOT}/scripts/runbook/04-prune.sh" on
step "Step 4c: bring the ConfigMap back with git revert"
"${ROOT}/scripts/runbook/04-prune.sh" restore
step "Step 5a: a bad commit"
"${ROOT}/scripts/runbook/05-break-and-rollback.sh" bad
step "Step 5b: git revert"
"${ROOT}/scripts/runbook/05-break-and-rollback.sh" rollback
step "Extra: a manifest the schema refuses"
"${ROOT}/scripts/runbook/06-bad-manifest.sh"
step "Where it ended"
"${ROOT}/scripts/status.sh"
