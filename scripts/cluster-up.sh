#!/usr/bin/env bash
# Creates the kind cluster if it does not exist yet. Safe to run again.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require kind kubectl docker

# A cluster whose creation was interrupted exists as a container but has no working context; start it over.
# Under CPU contention a control plane can miss kubeadm's fixed deadlines, so the node gets a larger share of the CPU
# than the default as soon as its container exists. Harmless on an idle machine.
prioritize_node() {
  local container="$1" waited=0
  until docker update --cpu-shares 8192 "${container}" >/dev/null 2>&1; do
    waited=$((waited + 1))
    [ "${waited}" -lt 120 ] || return 0
    sleep 1
  done
}

if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}" && ! kc get nodes >/dev/null 2>&1; then
  log "cluster ${CLUSTER_NAME} is half-made; deleting it"
  kind delete cluster --name "${CLUSTER_NAME}"
fi
if kind get clusters 2>/dev/null | grep -qx "${CLUSTER_NAME}"; then
  log "cluster ${CLUSTER_NAME} already exists"
else
  log "creating cluster ${CLUSTER_NAME} (${KIND_NODE_IMAGE%%@*})"
  create_cluster() {
    # Remove the leftover of an interrupted attempt (kind would stop on the name conflict).
    docker rm --force "${CLUSTER_NAME}-control-plane" >/dev/null 2>&1 || true
    prioritize_node "${CLUSTER_NAME}-control-plane" &
    kind create cluster --name "${CLUSTER_NAME}" --image "${KIND_NODE_IMAGE}" \
      --config "${ROOT}/kind/cluster.yaml" --wait 600s
  }
  # Starting a control plane on a busy machine sometimes fails; kind removes the half-made cluster, so try again.
  with_kind_lock retry 6 10 create_cluster || die "the cluster did not start after six attempts"
fi
kc wait --for=condition=Ready node --all --timeout=120s
