#!/usr/bin/env bash
# Lesson step 3: change the cluster behind Git's back, first with self-heal off, then on.
#   03-drift.sh off    the controller reports the difference and leaves it alone
#   03-drift.sh on     the controller puts both objects back, with no command from you
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

drift_by_hand() {
  kc -n "${APP_NAMESPACE}" scale deploy web --replicas=5
  kc -n "${APP_NAMESPACE}" patch configmap web-config --type merge -p '{"data":{"GREETING":"hacked"}}'
}

live_greeting() { kc -n "${APP_NAMESPACE}" get configmap web-config -o 'jsonpath={.data.GREETING}'; }
live_replicas() { deploy_field '{.spec.replicas}'; }
git_replicas() { grep -E '^  replicas:' "${WORK_CLONE}/apps/web/base/deployment.yaml" | awk '{print $2}'; }
git_greeting() { grep -E '^  GREETING:' "${WORK_CLONE}/apps/web/base/configmap.yaml" | sed 's/^  GREETING: //'; }
back_to_git() { [ "$(live_replicas)" = "$(git_replicas)" ] && [ "$(live_greeting)" = "$(git_greeting)" ]; }

case "${1:-}" in
  off)
    set_sync_policy selfHeal false
    drift_by_hand
    wait_for "the app to report OutOfSync" 60 output_is OutOfSync app_field '{.status.sync.status}'
    echo "--- what differs between Git and the cluster (kubectl diff):"
    "${ROOT}/scripts/diff.sh" | grep -E '^[-+] +(replicas|GREETING):' || true
    sleep 45 # two poll intervals: a controller that was going to revert it would have done so
    echo "after 45 seconds: replicas=$(live_replicas) GREETING=$(live_greeting) sync=$(app_field '{.status.sync.status}')"
    ;;
  on)
    set_sync_policy selfHeal true
    wait_for "the leftover drift to be reverted" 60 back_to_git
    drift_by_hand
    echo "drifted by hand: replicas=$(live_replicas) GREETING=$(live_greeting)"
    started=$SECONDS
    wait_for "both objects to return to Git's values" 60 back_to_git
    echo "reverted in $((SECONDS - started))s: replicas=$(live_replicas) GREETING=$(live_greeting) sync=$(app_field '{.status.sync.status}')"
    ;;
  *)
    die "usage: 03-drift.sh off|on"
    ;;
esac
