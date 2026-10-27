#!/usr/bin/env bash
# Deletes the cluster and the working clone. Nothing else is left behind on the machine except the images.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require "${CLUSTER_PROVIDER}"

provider_delete "${CLUSTER_NAME}"
rm -rf "${WORK_DIR}"
