#!/usr/bin/env bash
# Lesson step 2: change the replica count and the greeting in one commit and watch the cluster follow.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"

deployment="${WORK_CLONE}/apps/web/base/deployment.yaml"
configmap="${WORK_CLONE}/apps/web/base/configmap.yaml"

perl -pi -e 's/^  replicas: 2$/  replicas: 3/' "${deployment}"
# Environment variables are read at container start, so the pod template changes with the ConfigMap.
perl -pi -e 's/(plainround.dev\/config-revision: )"1"/$1"2"/' "${deployment}"
perl -pi -e 's/^  GREETING: hello$/  GREETING: hi there/' "${configmap}"

sha="$(commit_and_push "Scale web to 3 replicas and change the greeting")"
log "pushed ${sha:0:7}; waiting for the controller (it polls Git every 20 seconds)"
wait_for "the app synced and healthy at ${sha:0:7}" "${WAIT_TIMEOUT}" app_synced_and_healthy_at "${sha}"
three_ready() { [ "$(deploy_field '{.status.readyReplicas}')" = "3" ] && [ "$(deploy_field '{.status.updatedReplicas}')" = "3" ]; }
wait_for "3 ready replicas on the new pods" "${WAIT_TIMEOUT}" three_ready

echo "replicas:  $(deploy_field '{.spec.replicas}')"
echo "GREETING:  $(kc -n "${APP_NAMESPACE}" exec deploy/web -- printenv GREETING)"
echo "running from commit: $(app_field '{.status.sync.revision}' | cut -c1-7)  (git log: $(work_git log -1 --format='%h %s'))"
echo "history (deployment id, commit):"
kc -n argocd get application "${APP_NAME}" -o 'jsonpath={range .status.history[*]}  {.id}  {.revision}{"\n"}{end}'
