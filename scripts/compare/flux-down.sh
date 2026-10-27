#!/usr/bin/env bash
# Deletes the Flux cluster and its working clone.
set -euo pipefail
# shellcheck source=env.sh
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "${COMPARE_ROOT}/scripts/lib.sh"
require kind

kind delete cluster --name "${CLUSTER_NAME}"
rm -rf "${WORK_DIR}"
