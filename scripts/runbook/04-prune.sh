#!/usr/bin/env bash
# Lesson step 4: delete the ConfigMap's file from Git, first with prune off, then on.
#   04-prune.sh off       the object stays and is flagged
#   04-prune.sh on        the object is removed
#   04-prune.sh restore   git revert of the deletion brings it back
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

marker="${WORK_DIR}/prune-commit"
configmap_present() { kc -n "${APP_NAMESPACE}" get configmap web-config >/dev/null 2>&1; }
configmap_gone() { ! configmap_present; }

case "${1:-}" in
  off)
    set_sync_policy prune false
    work_git rm --quiet apps/web/base/configmap.yaml
    perl -ni -e 'print unless /^  - configmap.yaml$/' "${WORK_CLONE}/apps/web/base/kustomization.yaml"
    sha="$(commit_and_push "Delete the web ConfigMap")"
    echo "${sha}" > "${marker}"
    wait_for "the app to report OutOfSync" 90 output_is OutOfSync app_field '{.status.sync.status}'
    sleep 30
    echo "ConfigMap web-config in the cluster: $(configmap_present && echo present || echo gone)"
    echo "sync=$(app_field '{.status.sync.status}')  resources needing prune:"
    kc -n argocd get application "${APP_NAME}" \
      -o 'jsonpath={range .status.resources[?(@.requiresPruning==true)]}  {.kind}/{.name}{"\n"}{end}'
    ;;
  on)
    set_sync_policy prune true
    wait_for "the ConfigMap to be pruned" 90 configmap_gone
    wait_for "the app to be Synced" 60 output_is Synced app_field '{.status.sync.status}'
    kc -n "${APP_NAMESPACE}" get configmap web-config 2>&1 || true
    ;;
  restore)
    [ -f "${marker}" ] || die "no deletion commit recorded; run 04-prune.sh off first"
    work_git revert --no-edit "$(cat "${marker}")" >/dev/null
    work_git push --quiet origin main
    wait_for "the ConfigMap to be back" 90 configmap_present
    wait_for "the app to be Synced and Healthy" "${WAIT_TIMEOUT}" app_synced_and_healthy_at "$(work_head)"
    ;;
  *)
    die "usage: 04-prune.sh off|on|restore"
    ;;
esac
