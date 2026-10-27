#!/usr/bin/env bash
# Step 6: the three behaviors the lesson compares, run against Flux on the second cluster.
# Prints one RESULT line per behavior; tests/compare asserts on them.
set -euo pipefail
# shellcheck source=env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "${COMPARE_ROOT}/scripts/lib.sh"

kustomization_field() { kc -n flux-system get kustomization web -o "jsonpath=${1}" 2>/dev/null || true; }
ready() { kustomization_field '{.status.conditions[?(@.type=="Ready")].status}'; }
ready_is() { [ "$(ready)" = "$1" ]; }
configmap_present() { kc -n "${APP_NAMESPACE}" get configmap web-config >/dev/null 2>&1; }
configmap_gone() { ! configmap_present; }
replicas_are() { [ "$(deploy_field '{.spec.replicas}')" = "$1" ]; }
greeting_is() { [ "$(kc -n "${APP_NAMESPACE}" get configmap web-config -o 'jsonpath={.data.GREETING}')" = "$1" ]; }
drift_reverted() { replicas_are 2 && greeting_is hello; }

wait_for "Flux Ready before the experiments" "${WAIT_TIMEOUT}" ready_is True

# 1. Self-healing: nothing to switch on. The Kustomization applies Git again on every interval.
started=$SECONDS
kc -n "${APP_NAMESPACE}" scale deploy web --replicas=5 >/dev/null
kc -n "${APP_NAMESPACE}" patch configmap web-config --type merge -p '{"data":{"GREETING":"hacked"}}' >/dev/null
wait_for "Flux to revert the drift" 120 drift_reverted
echo "RESULT drift: replicas 5 -> $(deploy_field '{.spec.replicas}') and GREETING hacked -> hello in $((SECONDS - started))s with prune=false and no self-heal setting"

# 2. Pruning: off by default, one field to turn on, and no OutOfSync flag while it is off.
work_git rm --quiet apps/web/base/configmap.yaml
perl -ni -e 'print unless /^  - configmap.yaml$/' "${WORK_CLONE}/apps/web/base/kustomization.yaml"
deletion="$(commit_and_push "Delete the web ConfigMap")"
sleep 40
echo "RESULT prune-off: ConfigMap $(configmap_present && echo present || echo gone) after 40s, Kustomization Ready=$(ready) (Flux raises no out-of-sync flag)"
kc -n flux-system patch kustomization web --type merge -p '{"spec":{"prune":true}}' >/dev/null
wait_for "Flux to prune the ConfigMap" 120 configmap_gone
echo "RESULT prune-on: ConfigMap gone after spec.prune=true"
work_git revert --no-edit "${deletion}" >/dev/null
work_git push --quiet origin main
wait_for "the ConfigMap to come back" 120 configmap_present
wait_for "Flux Ready again" 120 ready_is True

# 3. Health: Ready=False when an applied object is not healthy (kstatus, because spec.wait is true).
perl -pi -e 's/newTag: 1\.0\.0/newTag: 1.1.0/' "${WORK_CLONE}/apps/web/overlays/local/kustomization.yaml"
perl -0pi -e 's#(readinessProbe:\s+httpGet:\s+path: )/healthz#$1/definitely-missing#' "${WORK_CLONE}/apps/web/base/deployment.yaml"
bad="$(commit_and_push "Ship web 1.1.0 (readiness probe points at a missing path)")"
wait_for "Flux Ready=False after the bad commit" 240 ready_is False
echo "RESULT health: Ready=False, reason=$(kustomization_field '{.status.conditions[?(@.type=="Ready")].reason}') after the bad commit"
work_git revert --no-edit "${bad}" >/dev/null
work_git push --quiet origin main
wait_for "Flux Ready=True after git revert" 240 ready_is True
echo "RESULT rollback: Ready=True, image=$(deploy_field '{.spec.template.spec.containers[0].image}') after git revert"
