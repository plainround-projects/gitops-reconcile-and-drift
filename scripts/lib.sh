#!/usr/bin/env bash
# Shared helpers for every script in this repository. Source it; do not run it.
# shellcheck shell=bash

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT

# versions.env pins the tools and images; .env (copied from .env.example) holds local choices.
# shellcheck source=../versions.env
source "${ROOT}/versions.env"
if [ -f "${ROOT}/.env" ]; then
  # shellcheck source=/dev/null
  source "${ROOT}/.env"
fi

CLUSTER_NAME="${CLUSTER_NAME:-gitops-drift}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-240}"
GIT_HOST_PORT="${GIT_HOST_PORT:-30418}"
GIT_HOST_URL="http://127.0.0.1:${GIT_HOST_PORT}/gitops-demo.git"
WORK_DIR="${WORK_DIR:-${ROOT}/.work}"
WORK_CLONE="${WORK_DIR}/gitops-demo"
APP_NAME="web"
APP_NAMESPACE="web"
export CLUSTER_NAME WAIT_TIMEOUT KUBE_CONTEXT GIT_HOST_URL WORK_CLONE

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "error: $*"; exit 1; }

# shellcheck source=provider.sh
source "${ROOT}/scripts/provider.sh"
KUBE_CONTEXT="$(provider_context "${CLUSTER_NAME}")"

require() {
  local tool
  for tool in "$@"; do
    command -v "${tool}" >/dev/null 2>&1 || die "${tool} is not installed (see the prerequisites in README.md)"
  done
}

# kubectl always talks to this project's cluster, never to whatever context happens to be current.
kc() { kubectl --context "${KUBE_CONTEXT}" "$@"; }

# retry <attempts> <delay-seconds> <command...>: run until it succeeds, with a fixed delay.
retry() {
  local attempts="$1" delay="$2" attempt=1
  shift 2
  until "$@"; do
    if [ "${attempt}" -ge "${attempts}" ]; then return 1; fi
    attempt=$((attempt + 1))
    sleep "${delay}"
  done
}

# wait_for <description> <timeout-seconds> <command...>: poll once a second until the command succeeds.
wait_for() {
  local description="$1" timeout="$2" waited=0
  shift 2
  until "$@" >/dev/null 2>&1; do
    if [ "${waited}" -ge "${timeout}" ]; then
      die "timed out after ${timeout}s waiting for ${description}"
    fi
    sleep 1
    waited=$((waited + 1))
  done
  log "${description}: ok (${waited}s)"
}

# app_field <jsonpath>: one field of the Argo CD Application, empty when it is not there.
app_field() { kc -n argocd get application "${APP_NAME}" -o "jsonpath=${1}" 2>/dev/null || true; }

app_synced_and_healthy_at() {
  local revision="$1"
  [ "$(app_field '{.status.sync.status}')" = "Synced" ] &&
    [ "$(app_field '{.status.health.status}')" = "Healthy" ] &&
    [ "$(app_field '{.status.sync.revision}')" = "${revision}" ]
}

# Every git command of the runbook goes through here so it only ever touches the working clone.
work_git() { git -C "${WORK_CLONE}" "$@"; }

work_head() { work_git rev-parse HEAD; }

# commit_and_push <message>: commit everything in the working clone, push it, print the new commit.
commit_and_push() {
  work_git add --all
  work_git commit --quiet -m "$1"
  work_git push --quiet origin main
  work_head
}

# Ask the controller to look at Git now instead of at the next poll. The runbook never needs this
# (the poll interval is 20 seconds); the tests use it only to shorten waits where the lesson does not
# measure the interval.
refresh_app() {
  kc -n argocd annotate application "${APP_NAME}" argocd.argoproj.io/refresh=normal --overwrite >/dev/null
}

# set_sync_policy <selfHeal|prune> <true|false>: change a controller setting. This edits the
# Application object (the controller's configuration), not the workload.
set_sync_policy() {
  kc -n argocd patch application "${APP_NAME}" --type merge \
    -p "{\"spec\":{\"syncPolicy\":{\"automated\":{\"$1\":$2}}}}" >/dev/null
  log "syncPolicy.automated.$1 = $2"
}

# output_is <expected> <command...>: true when the command prints exactly <expected>. Used with wait_for, which re-runs it
# at every poll (a "$(...)" written in the wait_for call would be evaluated only once).
output_is() {
  local expected="$1"
  shift
  [ "$("$@")" = "${expected}" ]
}

deploy_field() { kc -n "${APP_NAMESPACE}" get deploy web -o "jsonpath=${1}" 2>/dev/null || true; }
