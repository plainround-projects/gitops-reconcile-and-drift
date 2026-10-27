#!/usr/bin/env bash
# Creates the local cluster (k3d by default, kind with CLUSTER_PROVIDER=kind) if it does not exist yet. Safe to run again.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require "${CLUSTER_PROVIDER}" kubectl docker

# A cluster whose creation was interrupted exists as a container but has no kubectl context; start it over. (A slow API
# server is not a reason to delete a cluster, so only the missing context counts.)
if provider_exists "${CLUSTER_NAME}" && ! kubectl config get-contexts -o name | grep -qx "${KUBE_CONTEXT}"; then
  log "cluster ${CLUSTER_NAME} is half-made; deleting it"
  provider_delete "${CLUSTER_NAME}"
fi
if provider_exists "${CLUSTER_NAME}"; then
  log "cluster ${CLUSTER_NAME} already exists"
else
  log "creating cluster ${CLUSTER_NAME} with ${CLUSTER_PROVIDER}"
  create_cluster() {
    # Remove the leftover of an interrupted attempt (the provider would stop on the name conflict).
    docker rm --force "$(provider_node "${CLUSTER_NAME}")" >/dev/null 2>&1 || true
    # The Git server's NodePort (platform/git-server) is published on the loopback interface of the host.
    provider_create "${CLUSTER_NAME}" "${GIT_HOST_PORT}:30418"
  }
  with_cluster_lock retry 6 10 create_cluster || die "the cluster did not start after six attempts"
fi
kc wait --for=condition=Ready node --all --timeout=180s
