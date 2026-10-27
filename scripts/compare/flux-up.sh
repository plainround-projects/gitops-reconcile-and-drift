#!/usr/bin/env bash
# Step 6: the other controller. Creates a second kind cluster, installs Flux at the pinned version, and points
# it at the same repository content through a second Git server. The two clusters never share an object.
set -euo pipefail
# shellcheck source=env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "${COMPARE_ROOT}/scripts/lib.sh"

pinned="$(grep -oE 'flux2/releases/download/v[0-9.]+/' "${ROOT}/platform/flux/kustomization.yaml" | head -1 | cut -d/ -f4)"
[ "${pinned}" = "${FLUX_VERSION}" ] || die "platform/flux pins ${pinned}, versions.env says ${FLUX_VERSION}"

"${ROOT}/scripts/cluster-up.sh"
"${ROOT}/scripts/build-images.sh"
"${ROOT}/scripts/install-git-server.sh"
"${ROOT}/scripts/seed-repo.sh"

log "installing Flux ${FLUX_VERSION}"
kc apply --server-side --force-conflicts -k "${ROOT}/platform/flux" >/dev/null
kc -n flux-system rollout status deployment/source-controller --timeout=240s
kc -n flux-system rollout status deployment/kustomize-controller --timeout=240s
kc apply -f "${ROOT}/platform/flux/sync.yaml"
wait_for "the Flux Kustomization to be Ready" "${WAIT_TIMEOUT}" \
  bash -c "kubectl --context ${KUBE_CONTEXT} -n flux-system get kustomization web -o 'jsonpath={.status.conditions[?(@.type==\"Ready\")].status}' | grep -qx True"
