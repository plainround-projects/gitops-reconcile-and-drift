#!/usr/bin/env bash
# Source this before scripts/lib.sh: it points every script at the second cluster, the Flux one.
# shellcheck shell=bash
COMPARE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export CLUSTER_NAME=gitops-drift-flux
export GIT_HOST_PORT=30419
export WORK_DIR="${COMPARE_ROOT}/.work-flux"
export KIND_CONFIG="${COMPARE_ROOT}/kind/flux-cluster.yaml"
