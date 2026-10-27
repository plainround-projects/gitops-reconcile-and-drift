#!/usr/bin/env bash
# The one thing applied by hand: the AppProject and the Application that tell the controller where to look.
# Everything the Application then deploys comes from Git.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require kubectl

kc apply -f "${ROOT}/manifests/clusters/local/project.yaml" -f "${ROOT}/manifests/clusters/local/application.yaml"
