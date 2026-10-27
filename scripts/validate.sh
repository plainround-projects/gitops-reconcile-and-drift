#!/usr/bin/env bash
# Checks the desired-state tree against the Kubernetes and Argo CD schemas.
#   validate.sh [repository-root]       default: manifests/ of this project
# Every overlay under apps/*/overlays/* is rendered with kustomize and checked strictly (unknown fields,
# wrong types and missing required fields all fail); everything under clusters/ is checked against the
# community CRD schemas. Exit status 0 means every manifest is valid.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require kubectl kubeconform

tree="${1:-${ROOT}/manifests}"
cache="${XDG_CACHE_HOME:-${HOME}/.cache}/plainround-kubeconform"
mkdir -p "${cache}"
common=(-strict -summary -kubernetes-version "${KUBECONFORM_KUBERNETES_VERSION}" -cache "${cache}")
crds='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

status=0
for overlay in "${tree}"/apps/*/overlays/*; do
  [ -d "${overlay}" ] || continue
  log "kustomize build ${overlay#"${tree}"/}"
  kubectl kustomize "${overlay}" | kubeconform "${common[@]}" - || status=1
done

if [ -d "${tree}/clusters" ]; then
  log "clusters/"
  kubeconform "${common[@]}" -schema-location default -schema-location "${crds}" "${tree}/clusters" || status=1
fi
exit "${status}"
