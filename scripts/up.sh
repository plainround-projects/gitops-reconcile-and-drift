#!/usr/bin/env bash
# Everything `make up` does, in order. Safe to run again.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require docker kubectl git curl kubeconform

"${ROOT}/scripts/cluster-up.sh"
"${ROOT}/scripts/build-images.sh"
"${ROOT}/scripts/install-git-server.sh"
"${ROOT}/scripts/install-argocd.sh"
"${ROOT}/scripts/seed-repo.sh"
"${ROOT}/scripts/bootstrap.sh"
wait_for "the web app to be synced and healthy" "${WAIT_TIMEOUT}" app_synced_and_healthy_at "$(work_head)"
"${ROOT}/scripts/status.sh"
