#!/usr/bin/env bash
# Installs Argo CD at the pinned version (platform/argocd) and waits for its components.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require kubectl

pinned="$(grep -oE 'argo-cd/v[0-9.]+/' "${ROOT}/platform/argocd/kustomization.yaml" | head -1 | tr -d '/' | sed 's/argo-cd//')"
[ "${pinned}" = "${ARGOCD_VERSION}" ] || die "platform/argocd pins ${pinned}, versions.env says ${ARGOCD_VERSION}"

log "installing Argo CD ${ARGOCD_VERSION}"
# Server-side apply: the ApplicationSet CRD is too large for the client-side last-applied annotation.
kc apply --server-side --force-conflicts -k "${ROOT}/platform/argocd" >/dev/null
kc -n argocd rollout status statefulset/argocd-application-controller --timeout="${WAIT_TIMEOUT}s"
for deployment in argocd-repo-server argocd-server argocd-applicationset-controller argocd-redis; do
  kc -n argocd rollout status "deployment/${deployment}" --timeout="${WAIT_TIMEOUT}s"
done
