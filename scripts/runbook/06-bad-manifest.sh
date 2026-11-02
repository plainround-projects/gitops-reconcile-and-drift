#!/usr/bin/env bash
# Extra: a manifest the schema refuses is stopped twice. The pre-push hook (kubeconform) refuses the push; if
# the hook is skipped with --no-verify, the Kubernetes API server refuses the apply and the controller
# reports the failed sync while the cluster keeps running the last good state.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

before_replicas="$(deploy_field '{.spec.replicas}')"
perl -pi -e 's/^  replicas: \d+$/  replicas: "many"/' "${WORK_CLONE}/apps/web/base/deployment.yaml"
work_git add --all
work_git commit --quiet -m "Set replicas to a string"
bad="$(work_head)"

echo "--- 1. the pre-push hook refuses it:"
if work_git push origin main; then die "the hook let an invalid manifest through"; fi

echo "--- 2. skipping the hook (--no-verify): the cluster refuses it:"
work_git push --quiet --no-verify origin main
# The controller retries a failed automated sync with a growing delay, so the phase can stay Running; the message says what failed.
operation_failed() {
  [[ "$(app_field '{.status.operationState.phase}')" =~ ^(Failed|Error)$ ]] || [[ "$(app_field '{.status.operationState.message}')" == *"completed unsuccessfully"* ]]
}
wait_for "the controller to report a failed sync" 120 operation_failed
echo "operation phase: $(app_field '{.status.operationState.phase}')"
echo "message: $(app_field '{.status.operationState.message}' | cut -c1-200)"
echo "live replicas still: $(deploy_field '{.spec.replicas}') (was ${before_replicas})"

echo "--- 3. git revert clears it:"
work_git revert --no-edit "${bad}" >/dev/null
work_git push --quiet origin main
wait_for "the app Synced and Healthy again" "${WAIT_TIMEOUT}" app_synced_and_healthy_at "$(work_head)"
