#!/usr/bin/env bash
# Builds the three local images and loads them into the kind cluster (no registry involved):
#   plainround/web:1.0.0 and :1.1.0   the demo application, an old and a new version to roll between
#   plainround/git-server:1.0.0       the Git server the controller watches
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require docker kind

build() {
  local context="$1" tag="$2"
  shift 2
  log "building ${tag}"
  docker build --quiet --tag "${tag}" "$@" "${ROOT}/${context}" >/dev/null
}

build docker/web plainround/web:1.0.0 --build-arg "BASE_IMAGE=${WEB_BASE_IMAGE}" --build-arg APP_VERSION=1.0.0
build docker/web plainround/web:1.1.0 --build-arg "BASE_IMAGE=${WEB_BASE_IMAGE}" --build-arg APP_VERSION=1.1.0
build docker/git-server plainround/git-server:1.0.0 --build-arg "BASE_IMAGE=${GIT_SERVER_BASE_IMAGE}"

log "loading the images into cluster ${CLUSTER_NAME}"
kind load docker-image --name "${CLUSTER_NAME}" plainround/web:1.0.0 plainround/web:1.1.0 plainround/git-server:1.0.0
