#!/usr/bin/env bash
# Creates the working clone of gitops-demo from manifests/ and pushes it to the in-cluster Git server.
#   seed-repo.sh            create the clone if it is missing; push the clone either way
#   seed-repo.sh --reset    throw the clone away and start again from one initial commit
# The clone has a pre-push hook that runs scripts/validate.sh, the same check the CI runs.
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
require git curl

if [ "${1:-}" = "--reset" ]; then
  rm -rf "${WORK_CLONE}"
fi

if [ -d "${WORK_CLONE}/.git" ]; then
  log "working clone already exists at ${WORK_CLONE#"${ROOT}"/}"
  # A new cluster has an empty Git server even when an old clone is left over: put the clone's history on it.
  work_git push --quiet --force origin main
  exit 0
fi

mkdir -p "${WORK_CLONE}"
cp -R "${ROOT}/manifests/." "${WORK_CLONE}/"
git -C "${WORK_CLONE}" init --quiet --initial-branch=main
git -C "${WORK_CLONE}" config user.name "Runbook"
git -C "${WORK_CLONE}" config user.email "runbook@example.invalid"
git -C "${WORK_CLONE}" config commit.gpgsign false

cat > "${WORK_CLONE}/.git/hooks/pre-push" <<HOOK
#!/usr/bin/env bash
exec "${ROOT}/scripts/validate.sh" "${WORK_CLONE}"
HOOK
chmod +x "${WORK_CLONE}/.git/hooks/pre-push"

work_git add --all
work_git commit --quiet -m "Initial desired state: web app 1.0.0, two replicas"
work_git remote add origin "${GIT_HOST_URL}"
# --force: a reset must replace whatever an earlier run left on the server.
work_git push --quiet --force origin main
log "seeded gitops-demo at $(work_head | cut -c1-7)"
