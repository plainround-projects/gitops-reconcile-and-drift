#!/usr/bin/env bash
# Lesson step 5: ship an image whose readiness probe never passes, then roll back with git revert.
#   05-break-and-rollback.sh bad        commit and push the break
#   05-break-and-rollback.sh rollback   git revert it; no kubectl command touches the cluster
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

marker="${WORK_DIR}/bad-commit"
live_image() { deploy_field '{.spec.template.spec.containers[0].image}'; }

case "${1:-}" in
  bad)
    perl -pi -e 's/newTag: 1\.0\.0/newTag: 1.1.0/' "${WORK_CLONE}/apps/web/overlays/local/kustomization.yaml"
    # The first "path: /healthz" in the file is the readiness probe; the liveness probe stays valid.
    perl -0pi -e 's#(readinessProbe:\s+httpGet:\s+path: )/healthz#$1/definitely-missing#' \
      "${WORK_CLONE}/apps/web/base/deployment.yaml"
    sha="$(commit_and_push "Ship web 1.1.0 (readiness probe points at a missing path)")"
    echo "${sha}" > "${marker}"
    wait_for "the controller to report Degraded" "${WAIT_TIMEOUT}" output_is Degraded app_field '{.status.health.status}'
    echo "health=$(app_field '{.status.health.status}')  image=$(live_image)"
    echo "ready replicas: $(deploy_field '{.status.readyReplicas}') of $(deploy_field '{.spec.replicas}') (the old pods keep serving)"
    ;;
  rollback)
    [ -f "${marker}" ] || die "no bad commit recorded; run 05-break-and-rollback.sh bad first"
    work_git revert --no-edit "$(cat "${marker}")" >/dev/null
    work_git push --quiet origin main
    sha="$(work_head)"
    wait_for "the app Synced and Healthy at ${sha:0:7}" "${WAIT_TIMEOUT}" app_synced_and_healthy_at "${sha}"
    echo "health=$(app_field '{.status.health.status}')  image=$(live_image)  (rolled back by $(work_git log -1 --format='%h %s'))"
    ;;
  *)
    die "usage: 05-break-and-rollback.sh bad|rollback"
    ;;
esac
