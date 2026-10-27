#!/usr/bin/env bash
# One screen of state: what the controller thinks, and what the cluster holds.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

printf 'application  sync=%s  health=%s  revision=%s\n' \
  "$(app_field '{.status.sync.status}')" "$(app_field '{.status.health.status}')" \
  "$(app_field '{.status.sync.revision}' | cut -c1-7)"
printf 'syncPolicy   selfHeal=%s  prune=%s\n' \
  "$(app_field '{.spec.syncPolicy.automated.selfHeal}')" "$(app_field '{.spec.syncPolicy.automated.prune}')"
printf 'deployment   replicas=%s  image=%s\n' \
  "$(deploy_field '{.spec.replicas}')" "$(deploy_field '{.spec.template.spec.containers[0].image}')"
kc -n "${APP_NAMESPACE}" get pods,configmap web-config --no-headers 2>&1 || true
