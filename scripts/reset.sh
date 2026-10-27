#!/usr/bin/env bash
# Back to the first state of the lesson: the Application and the app deleted, the repository reseeded,
# the Application created again with self-heal and prune off. The tests call this before each scenario.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

log "resetting the demo"
kc -n argocd delete application "${APP_NAME}" --ignore-not-found --wait=true --timeout=120s >/dev/null
kc delete namespace "${APP_NAMESPACE}" --ignore-not-found --wait=true --timeout=120s >/dev/null
"${ROOT}/scripts/seed-repo.sh" --reset
"${ROOT}/scripts/bootstrap.sh" >/dev/null
wait_for "the web app to be synced and healthy" "${WAIT_TIMEOUT}" app_synced_and_healthy_at "$(work_head)"
