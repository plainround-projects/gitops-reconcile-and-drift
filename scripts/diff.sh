#!/usr/bin/env bash
# What differs between Git (rendered with kustomize) and the live cluster. Exit status is always 0.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

kubectl kustomize "${WORK_CLONE}/apps/web/overlays/local" | kc diff -f - || true
