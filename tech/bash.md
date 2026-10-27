# Bash

## 1. What it is

Bash is a **shell**: a program that reads commands, one per line, and runs other programs. A **script** is a text file of such commands, so that a person types `./scripts/up.sh` once instead of fifty commands. Bash is also a small programming language: it has variables, functions, `if`, loops and pipes.

## 2. Why this repository uses it

The whole lesson is run by scripts, so a person can read each step and a test can call the same step. `make up` is five scripts in a row; `make run` is the lesson (change through Git, drift, prune, rollback, bad manifest) as scripts under `scripts/runbook/`.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `scripts/lib.sh` | helpers sourced by every other script: `log`, `die`, `require`, `kc`, `retry`, `wait_for`, `output_is`, Argo CD field readers, git helpers |
| `scripts/provider.sh` | k3d or kind behind one set of functions, plus the cluster lock |
| `scripts/up.sh, cluster-up.sh, build-images.sh, install-git-server.sh, install-argocd.sh, seed-repo.sh, bootstrap.sh` | the steps of `make up` |
| `scripts/run.sh, scripts/runbook/*.sh` | the lesson as an executable runbook |
| `scripts/status.sh, diff.sh, reset.sh, down.sh, validate.sh, ci-install-tools.sh` | inspection, reset, teardown, the manifest gate and the CI tool installer |
| `scripts/compare/*.sh` | the same three behaviors on Flux in a second cluster |
| `docker/git-server/entrypoint.sh` | the start-up script inside the Git server image (plain `sh`) |

## 4. How it works underneath

- A script starts with a **shebang** line such as `#!/usr/bin/env bash`. The operating system reads it and starts that program with the file as input.
- Every command ends with an **exit code**, a number from 0 to 255. `0` means success, anything else means failure. `if`, `&&`, `||` and `until` all look at it.
- A **variable** is written `name=value` and read as `"${name}"`. Quotes stop Bash from splitting a value at spaces.
- `$(command)` runs the command and pastes its output in place. `|` (a **pipe**) sends one command's output into the next command's input.
- `source file` runs another file *inside the current shell*, so its functions and variables become available. That is how one `lib.sh` is shared.
- **Standard output** (fd 1) is the normal output; **standard error** (fd 2) is for messages. `>&2` sends output to standard error; `>/dev/null` throws it away; `2>&1` joins error into output.
- Bash does not stop on errors unless told to. The line `set -euo pipefail` tells it to: `-e` stop at the first failing command, `-u` treat an unset variable as an error, `-o pipefail` make a pipe fail when any part of it fails (not only the last).

## 5. Walkthrough of this repository's use

### The header every script shares

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
```

* `#!/usr/bin/env bash` finds `bash` on the `PATH`, so the script works where Bash is not in `/bin`.
* `set -euo pipefail` is explained in section 4. It makes the script stop at the first error.
* `${BASH_SOURCE[0]}` is the path of the file being run. `dirname` cuts off the file name, `$( ... )` captures the folder, and `source .../lib.sh` loads the helpers. That makes the script work from any current folder.

### `scripts/lib.sh`, line by line

```bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
```
`cd` to the folder above `scripts/` and print the full path with `pwd`. `cd` runs inside `$( )`, a sub-shell, so the caller's folder does not change. `export` makes `ROOT` visible to programs the script starts.

```bash
source "${ROOT}/versions.env"
if [ -f "${ROOT}/.env" ]; then
  source "${ROOT}/.env"
fi
```
`versions.env` holds the pinned versions; `.env` (copied from `.env.example`) holds local choices. `[ -f file ]` is true when the file exists. The `# shellcheck source=...` comments above these lines tell ShellCheck which files are loaded.

```bash
CLUSTER_NAME="${CLUSTER_NAME:-gitops-drift}"
```
`${NAME:-default}` means "use `NAME` if it is set and not empty, otherwise the default". Each setting can be overridden by the environment or `.env`.

```bash
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "error: $*"; exit 1; }
```
`log` prints a time-stamped line to **standard error** (`>&2`), so standard output stays clean for values a caller captures. `"$*"` is all arguments joined. `die` logs and exits with code 1.

```bash
require() {
  local tool
  for tool in "$@"; do
    command -v "${tool}" >/dev/null 2>&1 || die "${tool} is not installed ..."
  done
}
```
`local` limits a variable to the function. `"$@"` is every argument as a separate word. `command -v tool` succeeds when the tool is on the `PATH`; the output is thrown away. `a || b` runs `b` only when `a` fails.

```bash
kc() { kubectl --context "${KUBE_CONTEXT}" "$@"; }
```
Every cluster command goes through `kc`, so it always uses this project's context.

```bash
retry() {
  local attempts="$1" delay="$2" attempt=1
  shift 2
  until "$@"; do
    if [ "${attempt}" -ge "${attempts}" ]; then return 1; fi
    attempt=$((attempt + 1))
    sleep "${delay}"
  done
}
```
`$1` and `$2` are the first two arguments; `shift 2` drops them so `"$@"` is the command to run. `until cmd; do ... done` repeats while the command fails. `$(( ))` does arithmetic. `-ge` means "greater than or equal".

```bash
wait_for() {
  local description="$1" timeout="$2" waited=0
  shift 2
  until "$@" >/dev/null 2>&1; do
    if [ "${waited}" -ge "${timeout}" ]; then die "timed out after ${timeout}s waiting for ${description}"; fi
    sleep 1
    waited=$((waited + 1))
  done
  log "${description}: ok (${waited}s)"
}
```
Polls once a second until the command succeeds. The arguments are **words**, not a string to be evaluated again: `wait_for "x" 60 test "$(cmd)" = ok` would run `cmd` once. That is why the file defines `output_is` and `app_synced_and_healthy_at`: small functions that do the check on every poll.

```bash
app_field() { kc -n argocd get application "${APP_NAME}" -o "jsonpath=${1}" 2>/dev/null || true; }
```
Reads one field of the Argo CD Application with a JSONPath expression. `2>/dev/null || true` turns "not found yet" into an empty string instead of an error.

```bash
app_synced_and_healthy_at() {
  local revision="$1"
  [ "$(app_field '{.status.sync.status}')" = "Synced" ] &&
    [ "$(app_field '{.status.health.status}')" = "Healthy" ] &&
    [ "$(app_field '{.status.sync.revision}')" = "${revision}" ]
}
```
Three tests joined with `&&` (all must be true). The function's exit code is the last test's, so `wait_for` can poll it.

```bash
commit_and_push() {
  work_git add --all
  work_git commit --quiet -m "$1"
  work_git push --quiet origin main
  work_head
}
```
`work_git` is `git -C <working clone>`, so no git command ever touches this repository. The function prints the new commit hash, which the runbook captures with `sha="$(commit_and_push ...)"`.

```bash
refresh_app() { kc -n argocd annotate application "${APP_NAME}" argocd.argoproj.io/refresh=normal --overwrite >/dev/null; }
set_sync_policy() { kc -n argocd patch application "${APP_NAME}" --type merge -p "{\"spec\":{\"syncPolicy\":{\"automated\":{\"$1\":$2}}}}" >/dev/null; ... }
```
`refresh_app` asks Argo CD to look at Git now. `set_sync_policy selfHeal true` builds a JSON merge patch and changes the controller's setting on the Application object only.

### `scripts/up.sh`

```bash
require docker kubectl git curl kubeconform
"${ROOT}/scripts/cluster-up.sh"
...
wait_for "the web app to be synced and healthy" "${WAIT_TIMEOUT}" app_synced_and_healthy_at "$(work_head)"
```
Runs the six steps in order, then waits for the controller to report the newest commit as Synced and Healthy. Scripts are called by path (not `make`) so they can be run on their own and so another process killing "make" does not stop them.

### `scripts/cluster-up.sh`
* `provider_exists ... && ! kubectl config get-contexts -o name | grep -qx "${KUBE_CONTEXT}"`: a cluster that exists as a container but has no kubectl context was interrupted while being created, so it is deleted. `grep -q` prints nothing and only sets the exit code; `-x` matches the whole line; `!` negates.
* `create_cluster() { docker rm --force ...; provider_create ... }` first removes a left-over node container (`|| true` ignores "no such container"), then creates the cluster publishing the Git server's port.
* `with_cluster_lock retry 6 10 create_cluster` takes the machine-wide lock, then tries up to six times, ten seconds apart.
* `kc wait --for=condition=Ready node --all --timeout=180s` blocks until the node is ready.

### `scripts/provider.sh`
A `case "${CLUSTER_PROVIDER}" in k3d) ... ;; kind) ... ;; *) die ... ;; esac` in every function. `provider_create` reads its arguments with a `while [ "$#" -gt 0 ]; do case "$1" in --network) ... shift 2 ;; ... esac; done` loop: a small option parser. For k3d it builds an **array** (`args=(...)`) and expands it with `"${args[@]}"`, which keeps each argument whole. For kind it writes a configuration file with a **here-document** (`cat <<'CONFIG' ... CONFIG`; the quoted marker stops variable expansion inside). `provider_load_images` asks the node's container runtime `crictl inspecti` whether an image is present and imports only the missing ones. `with_cluster_lock` uses `mkdir` as the lock because creating a directory either succeeds or fails atomically; it writes its process id (`$$`) into `pid`; a lock whose process is gone (`kill -0 pid` fails) is removed; it gives up after 7200 seconds.

### The runbook scripts
* `perl -pi -e 's/^  replicas: 2$/  replicas: 3/' file` edits a file in place (see the unix-tools note).
* `03-drift.sh` uses `case "${1:-}" in off) ... on) ... *) die "usage..." esac`: the first argument chooses the experiment. `sleep 45 # two poll intervals` proves a negative: a controller that was going to revert the drift would have done so by then. `started=$SECONDS` uses Bash's built-in seconds counter to time the revert.
* `04-prune.sh` records the deleting commit in `.work/prune-commit` so the `restore` step can `git revert` exactly that commit.
* `05-break-and-rollback.sh` uses `perl -0pi` (read the whole file as one string) so a pattern can span lines: it changes only the *readiness* probe's path.
* `06-bad-manifest.sh` runs `if work_git push origin main; then die "..."; fi`: the push is *expected to fail*; if it succeeds, the test fails.
* `kc -n argocd get application ... -o 'jsonpath={range .status.history[*]}...{end}'` loops over a list inside JSONPath.

### `docker/git-server/entrypoint.sh`
A `#!/bin/sh` script (the image has no Bash). `${REPOS:?set REPOS ...}` stops with that message when the variable is missing. The `for` loop creates a bare repository for each name. `fcgiwrap -s unix:/tmp/fcgiwrap.sock &` starts a helper in the background (`&`). `exec nginx -g 'daemon off;'` *replaces* the shell with nginx so nginx receives signals directly.

## 6. Try it yourself

1. `shellcheck scripts/*.sh scripts/*/*.sh` : no output means every script passes.
2. `bash -c 'source scripts/lib.sh; output_is hi echo hi && echo yes'` : prints `yes`; replace `hi` in the first position to see it fail silently (exit code 1).
3. `source scripts/lib.sh; log hello 2>/dev/null` : prints nothing, because `log` writes to standard error.
4. `scripts/status.sh` after `make up` : one screen of Application and Deployment state.
5. `bash -x scripts/status.sh 2>&1 | head -20` : `-x` prints each command as it runs, the best way to see what a script does.

## 7. Mistakes people make

- **Unquoted variables.** `rm -rf $dir/` with an empty `dir` is a disaster; `"${dir}"` and `${var:?message}` stop it. Every variable here is quoted.
- **Forgetting that `$(...)` is evaluated once.** `wait_for "x" 60 test "$(cmd)" = ok` runs `cmd` one time, before the loop starts, and then checks a frozen string. This repository wraps checks in functions so they run again on every poll.
- **Ignoring failures.** Without `set -e` a script keeps going after an error. Every script here starts with `set -euo pipefail`.
- **`cd` in a script that later uses relative paths.** The scripts compute `ROOT` once and use absolute paths.
- **Using Bash features in `sh`.** A script with `#!/bin/sh` runs in a smaller shell; `[[ ]]`, arrays and `${var,,}` are Bash only.

## 8. Check yourself

1. What does a shebang line do?
   *Answer:* It tells the operating system which program should run the file.
2. What do `set -e`, `-u` and `-o pipefail` each protect against?
   *Answer:* `-e`: carrying on after a failing command. `-u`: using a variable that was never set. `pipefail`: hiding a failure in the first part of a pipe.
3. Why is `"${name}"` safer than `$name`?
   *Answer:* The quotes keep a value with spaces or special characters as one word, and the braces mark exactly where the name ends.
4. What is the difference between running `./lib.sh` and `source lib.sh`?
   *Answer:* Running starts a new process whose variables vanish at its end; `source` runs the lines in the current shell, so its functions stay available.
5. What exit code means success?
   *Answer:* 0.

## 9. Further reading

- Bash Reference Manual: <https://www.gnu.org/software/bash/manual/bash.html> (the shell's own manual).
- The Bash installed on macOS is old (3.2); the scripts here avoid features newer than Bash 3.2 where they can, and the CI runner uses Bash 5.
