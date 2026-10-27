# Bash

## 1. What it is

A **terminal** is a window where you type a line of text, press Return, and the computer does what the line says. The program inside the terminal that reads your line and decides what to do with it is called a **shell**. **Bash** is the most common shell on Linux and the one that ships with macOS (in an old version, 3.2; the scripts here are written so they also work on that old version).

A shell can run other programs (`ls`, `git`, `kubectl`). It also has a small programming language of its own: variables, `if`, loops, functions. When you put many shell lines in a file and run the file, that file is called a **script**. Instead of typing fifty commands one by one, you type one name, such as `./scripts/up.sh`, and the script runs all fifty in order.

A word you will meet again and again: a **command** is one line you give the shell. It starts with a program name, then **arguments** (extra words) that tell the program what to work on. In `ls -l /tmp`, `ls` is the program and `-l` and `/tmp` are its arguments. An argument that starts with a dash, like `-l`, is usually called a **flag** or **option**: it switches a behavior on.

## 2. Why this repository uses it

The lesson is a **runbook**: a list of steps a person follows. Here every step is a script, so the steps are written down exactly, can be read, and can be run again by a test. `make up` runs five scripts in a row to build a cluster. `make run` runs the lesson's steps (change something through Git, change something by hand, delete a file, ship a bad change, roll it back). The tests do not copy that logic; they run the same scripts a person would run.

## 3. Where it appears

| File | What it does with Bash |
| --- | --- |
| `scripts/lib.sh` | A library of small helper functions that every other script loads. It is never run on its own. |
| `scripts/provider.sh` | Functions that create, delete and fill a local cluster, with either k3d or kind, behind one set of names. Also a lock so two clusters are not created at the same moment. |
| `scripts/up.sh` | Everything `make up` does, in order. |
| `scripts/cluster-up.sh` | Creates the cluster if it does not exist. |
| `scripts/build-images.sh` | Builds three container images and copies them into the cluster. |
| `scripts/install-git-server.sh` | Starts the small Git server inside the cluster and waits until it answers. |
| `scripts/install-argocd.sh` | Installs Argo CD (the controller) and waits for its parts. |
| `scripts/seed-repo.sh` | Makes the Git repository that Argo CD will watch, puts the first commit in it and pushes it. |
| `scripts/bootstrap.sh` | Applies the two objects that tell Argo CD where to look. |
| `scripts/run.sh` | Runs the whole lesson, step by step, printing what happens. |
| `scripts/runbook/02-change-through-git.sh` … `06-bad-manifest.sh` | One script for each step of the lesson. |
| `scripts/status.sh`, `scripts/diff.sh`, `scripts/reset.sh`, `scripts/down.sh` | Show state, show differences, go back to the start, delete everything. |
| `scripts/validate.sh` | Checks that the manifests are valid. Also used as a Git hook. |
| `scripts/ci-install-tools.sh` | Installs one tool on the machine that runs the automated checks. |
| `scripts/compare/env.sh`, `flux-up.sh`, `flux-behaviors.sh`, `flux-down.sh` | The same lesson steps on a second tool (Flux), in a second cluster. |
| `docker/git-server/entrypoint.sh` | The start-up script inside the Git server's container. It is written for the smaller `sh` shell. |

## 4. How it works underneath

Read this part slowly. Every later line depends on these ideas.

**A process.** When you run a program, the computer starts a **process**: a running copy of that program, with its own memory and its own list of settings. When a script runs, there is one process for Bash itself. Each program the script starts (for example `git`) becomes a new process, called a **child** process. When the child ends, it hands back a number to its parent. That number is the **exit code**.

**Exit codes.** An exit code is a whole number from 0 to 255. By agreement, `0` means "it worked" and any other number means "it failed" (different numbers can mean different kinds of failure). You cannot see the number on screen, but Bash keeps the code of the last command in a special variable called `$?`, and it uses the code in `if`, `&&`, `||` and loops. This is the most important idea in shell scripting: **success and failure are numbers that commands return, and the script reacts to them.**

**A variable.** A variable is a named box that holds text. You write `name=value` (no spaces around the `=`) to put text in the box, and `${name}` to read it back. The `$` means "take the value of". The braces `{ }` mark exactly where the name ends, so `${name}_file` is the value of `name` followed by `_file`.

**An environment variable.** Every process has a list of named settings called its **environment**. The shell starts every child process with a copy of that list. A shell variable becomes part of the list only when you **export** it (`export NAME`). Programs read environment variables to learn settings, such as where to find files. Because a child gets only a **copy**, a child can never change its parent's variables.

**Quoting.** A shell splits a line into words at spaces. A value such as `my file.txt` would become two words unless you quote it: `"my file.txt"` stays one word. Inside double quotes `"…"` the shell still replaces `${name}` by its value. Inside single quotes `'…'` nothing is replaced; the text is used exactly as written. Every variable in these scripts is written inside double quotes, so a value with a space in it cannot break the line.

**Command substitution.** `$(command)` runs the command and puts its printed output in place of the `$(…)`. For example `today="$(date +%H:%M:%S)"` stores the current time in `today`. The command inside runs in a **sub-shell**: a child copy of the shell. Things the child changes (such as the current folder) do not change the parent.

**Standard streams.** Every process starts with three channels open: **standard input** (channel 0, where it reads), **standard output** (channel 1, where it writes normal results) and **standard error** (channel 2, where it writes problems and messages). On screen the last two both look like text in the terminal, but they are separate. `>` sends standard output to a file instead of the screen. `2>` does the same for standard error. `>&2` means "send my standard output to wherever standard error goes". `>/dev/null` sends output to a special file called `/dev/null` that throws everything away. `2>&1` makes standard error go to the same place as standard output.

**A pipe.** `a | b` connects the standard output of `a` to the standard input of `b`. Both start at the same time; `b` reads what `a` writes. This is how small programs are chained: `grep error log.txt | head -3` finds lines with "error" and keeps the first three.

**A function.** A function is a named group of commands: `name() { commands; }`. You run it by writing its name like a command. Inside a function, `$1`, `$2` … are its arguments, `$#` is how many there are, `"$@"` is all of them (each kept as a separate word), and `"$*"` is all of them joined into one string. `shift 2` throws away the first two arguments so the rest move up. `local x` makes a variable that exists only inside the function.

**`source`.** `source file` (or `. file`) reads the lines of another file **into the current shell**, as if you had typed them here. After it, the other file's functions and variables exist. That is how one library, `lib.sh`, is shared by all the scripts. Running `./lib.sh` instead would start a child process whose functions disappear when it ends.

**A shebang.** The first line of a script, `#!/usr/bin/env bash`, tells the operating system which program should run the file. `env bash` means "find `bash` wherever it is installed".

**Safety switches.** By default Bash keeps going after a command fails. Almost every script here starts with the line `set -euo pipefail`, which turns on three protections:
- `-e` stop the script at the first command that fails (non-zero exit code);
- `-u` treat the use of a variable that was never set as an error (so a typing mistake in a name cannot silently become empty text);
- `-o pipefail` make a pipeline fail if **any** part of it fails (normally only the last part counts).

## 5. Walkthrough of this repository's use

The walkthrough follows the order in which `make up` and `make run` use the scripts. For each script you first see the whole file, then an explanation of every line.

---

### 5.1 `scripts/lib.sh`: the shared library

This file is loaded by every other script with `source`. It does not do anything by itself; it defines variables and functions.

```bash
#!/usr/bin/env bash
# Shared helpers for every script in this repository. Source it; do not run it.
# shellcheck shell=bash
```
- Line 1 is the shebang. Even though this file is only sourced, the line is kept so editors and tools know it is Bash.
- Line 2 is a **comment**: everything after a `#` on a line is ignored by Bash. It is a note for people.
- Line 3 is a comment for a tool called ShellCheck (described in its own note). It says "treat this file as Bash". A file that has no shebang needs it; here it is harmless.

```bash
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ROOT
```
- `BASH_SOURCE` is a Bash **array** (a numbered list of values). `${BASH_SOURCE[0]}` is its first item: the path of the file being read right now (`…/scripts/lib.sh`). Using it means the script still finds its own location when it is started from a different folder.
- `dirname path` prints the folder part of a path, so it gives `…/scripts`.
- `"$(dirname …)/.."` adds `/..`, which means "the folder above". So we get the repository folder.
- `cd folder && pwd` moves into that folder and then prints the full path (`pwd` = "print working directory"). The `&&` means "run the next command only if the previous one succeeded". All of this runs inside `$( … )`, a sub-shell, so the `cd` does not change the folder of the script that sourced this file.
- The result is stored in `ROOT`. The second line **exports** it so programs started by the scripts also see `ROOT`.

```bash
# versions.env pins the tools and images; .env (copied from .env.example) holds local choices.
# shellcheck source=../versions.env
source "${ROOT}/versions.env"
if [ -f "${ROOT}/.env" ]; then
  # shellcheck source=/dev/null
  source "${ROOT}/.env"
fi
```
- `versions.env` is a plain file of lines like `ARGOCD_VERSION=v3.5.6`. Sourcing it creates those variables. This puts every version number in one place.
- `if [ -f path ]; then … fi` is a test. `[ … ]` is a command that checks a condition and returns success or failure. `-f` means "this is an existing regular file". So the next line runs only when a `.env` file exists. `fi` ends the `if` (it is "if" backwards).
- `.env` holds settings a person may change locally. It is optional, so it is loaded only if it exists.
- The comments starting `# shellcheck source=` tell ShellCheck which file is loaded on the next line, because a tool reading the text cannot know the value of `${ROOT}`.

```bash
CLUSTER_NAME="${CLUSTER_NAME:-gitops-drift}"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-240}"
GIT_HOST_PORT="${GIT_HOST_PORT:-30418}"
GIT_HOST_URL="http://127.0.0.1:${GIT_HOST_PORT}/gitops-demo.git"
WORK_DIR="${WORK_DIR:-${ROOT}/.work}"
WORK_CLONE="${WORK_DIR}/gitops-demo"
APP_NAME="web"
APP_NAMESPACE="web"
export CLUSTER_NAME WAIT_TIMEOUT KUBE_CONTEXT GIT_HOST_URL WORK_CLONE
```
- `${NAME:-default}` means "use the value of `NAME` if it is set and not empty, otherwise use `default`". So `CLUSTER_NAME` is `gitops-drift` unless the person set something else in the environment or in `.env`. `WAIT_TIMEOUT` is how many seconds to wait for things (240 by default).
- A **port** is a number (0–65535) that picks one of the many "doors" a computer has for network traffic. A program that wants to receive requests listens on one port. `30418` is the port on your computer that leads into the Git server inside the cluster.
- `127.0.0.1` is the address that always means "this computer itself" (also called `localhost`). Using it means the Git server can be reached only from this machine, not from the network.
- `GIT_HOST_URL` is the web address of the demo Git repository, built from the port.
- `WORK_DIR` is a folder called `.work` inside the repository (a folder whose name starts with a dot is hidden by default). `WORK_CLONE` is a **clone** (a full local copy) of the demo repository, kept inside it. The runbook changes files there and pushes them.
- `APP_NAME` and `APP_NAMESPACE` are the names of the demo application inside Argo CD and Kubernetes.
- The last line exports the variables that other programs need.

```bash
log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*" >&2; }
die() { log "error: $*"; exit 1; }
```
- `log` is a function. `printf` prints text using a **format**: `%s` is a place for one value, `\n` is a line break. The two values are the time (`date +%H:%M:%S` prints hours:minutes:seconds) and `"$*"` (all the arguments of `log`, joined with spaces). `>&2` sends the line to standard error. The reason: standard output is kept clean for results that other commands capture, and messages for humans go to standard error.
- `die` is a function that logs `error: …` and then runs `exit 1`, which ends the whole script with the failure code 1.

```bash
# shellcheck source=provider.sh
source "${ROOT}/scripts/provider.sh"
KUBE_CONTEXT="$(provider_context "${CLUSTER_NAME}")"
```
- Loads the provider library (section 5.2). `provider_context` is one of its functions; it prints the name that `kubectl` uses for this cluster (`k3d-gitops-drift`). A **context** is a saved choice of "which cluster am I talking to".

```bash
require() {
  local tool
  for tool in "$@"; do
    command -v "${tool}" >/dev/null 2>&1 || die "${tool} is not installed (see the prerequisites in README.md)"
  done
}
```
- `require docker kubectl git` checks that those programs are installed.
- `local tool` declares a variable that exists only inside this function.
- `for tool in "$@"; do … done` is a **loop**: it runs the commands between `do` and `done` once for every argument, with `tool` set to that argument.
- `command -v name` prints where a program is found and succeeds if it is found. Its output is thrown away (`>/dev/null`), and `2>&1` sends its error messages the same way.
- `a || b` runs `b` only if `a` failed. So if the tool is missing, `die` stops the script with a clear message.

```bash
kc() { kubectl --context "${KUBE_CONTEXT}" "$@"; }
```
- `kubectl` is the program that talks to Kubernetes. `--context name` tells it which cluster. `kc` is a short function that always adds that flag, then passes along all other arguments with `"$@"`. After this, no script can talk to the wrong cluster by accident, even if you have other clusters on your machine.

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
- `retry 6 10 some-command` runs `some-command` up to 6 times, waiting 10 seconds between tries.
- `local a="$1" b="$2" c=1` makes three local variables at once: the first two arguments and a counter starting at 1.
- `shift 2` drops the first two arguments, so `"$@"` is now the command to run.
- `until command; do … done` repeats the body **until** the command succeeds (the opposite of `while`).
- `[ "${attempt}" -ge "${attempts}" ]` compares two numbers: `-ge` means "greater than or equal". `-lt` means "less than", `-eq` means "equal". When the counter reaches the limit, `return 1` leaves the function with the failure code 1.
- `$(( … ))` does whole-number arithmetic: `attempt=$((attempt + 1))` adds 1.
- `sleep 10` pauses the script for 10 seconds.

```bash
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
```
- `wait_for "text" 60 some-command args` runs the command again and again, once a second, until it succeeds, or stops with an error after 60 seconds. This is how the scripts wait for a cluster component to become ready without guessing a fixed delay.
- The loop condition is the command itself, with its output discarded so the screen stays quiet.
- When the time runs out, `die` ends the script and says what it was waiting for. When the command succeeds, `log` reports how many seconds it took.
- **Important detail.** The command is passed as separate words and **re-run every second**. If you wrote `wait_for "x" 60 test "$(some-command)" = ok`, then `$(some-command)` would run **once**, before `wait_for` starts, and the loop would compare the same frozen text every time and never succeed. That is why several checks in this repository are written as small named functions (`output_is`, `app_synced_and_healthy_at`): the function is what gets re-run.

```bash
app_field() { kc -n argocd get application "${APP_NAME}" -o "jsonpath=${1}" 2>/dev/null || true; }
```
- Reads one piece of information from the Argo CD **Application** object (the object that describes what Argo CD should deploy).
- `-n argocd` selects the Kubernetes **namespace** (a named folder of objects) called `argocd`. `get application web` fetches that object. `-o jsonpath=…` prints only the part you name with a path such as `{.status.sync.status}`. The path is applied to the object's data, which is structured text; a path with dots walks down through nested names.
- `2>/dev/null` hides error messages, and `|| true` turns a failure into success. If the object does not exist yet, the function prints nothing and does not stop the script (remember that `set -e` would otherwise stop it).

```bash
app_synced_and_healthy_at() {
  local revision="$1"
  [ "$(app_field '{.status.sync.status}')" = "Synced" ] &&
    [ "$(app_field '{.status.health.status}')" = "Healthy" ] &&
    [ "$(app_field '{.status.sync.revision}')" = "${revision}" ]
}
```
- A function whose exit code is the answer to a yes/no question: "has Argo CD applied exactly this Git commit, and is the application healthy?"
- `[ a = b ]` is a test that two pieces of text are equal. Three tests are joined by `&&`, so all three must be true. A trailing `&&` at the end of a line continues the command on the next line. The function's exit code is that of the last command it ran.
- `Synced` means "the cluster matches Git"; `Healthy` means "the pods are running and ready"; the revision is the commit hash Argo CD last applied.

```bash
work_git() { git -C "${WORK_CLONE}" "$@"; }
work_head() { work_git rev-parse HEAD; }
```
- `git -C folder args` runs Git as if started in that folder. `work_git` always uses the working clone, so no script ever changes this repository by accident. `git rev-parse HEAD` prints the 40-character hash of the newest commit (`HEAD` means "the commit I am on").

```bash
commit_and_push() {
  work_git add --all
  work_git commit --quiet -m "$1"
  work_git push --quiet origin main
  work_head
}
```
- Makes a commit of everything changed in the working clone and sends it to the server. `add --all` stages all changes; `commit -m "message"` records them (`--quiet` hides the summary); `push origin main` uploads the branch `main` to the remote called `origin`. The last line prints the new commit hash; callers capture it with `sha="$(commit_and_push "message")"`.

```bash
refresh_app() {
  kc -n argocd annotate application "${APP_NAME}" argocd.argoproj.io/refresh=normal --overwrite >/dev/null
}
```
- An **annotation** is a free note stored on a Kubernetes object. Argo CD watches this one: setting it asks Argo CD to look at Git now instead of waiting for its next poll. `--overwrite` allows replacing an existing value. The lesson never needs this (Argo CD polls every 20 seconds); the tests use it to save time where the poll interval is not what is being measured.

```bash
set_sync_policy() {
  kc -n argocd patch application "${APP_NAME}" --type merge \
    -p "{\"spec\":{\"syncPolicy\":{\"automated\":{\"$1\":$2}}}}" >/dev/null
  log "syncPolicy.automated.$1 = $2"
}
```
- Changes one setting of the Argo CD Application. `set_sync_policy selfHeal true` turns self-healing on.
- `patch --type merge -p '…json…'` sends a small piece of **JSON** to merge into the object. JSON is a text format for structured data: curly braces `{}` hold named values (an **object**), as in `{"name":"value"}`. Here the patch says "inside `spec`, inside `syncPolicy`, inside `automated`, set the key named `$1` to the value `$2`".
- The backslashes `\"` put literal double-quote characters inside a double-quoted shell string. The `\` is an **escape**: it removes the special meaning of the next character.
- It edits the Application (the controller's configuration), not the workload.

```bash
output_is() {
  local expected="$1"
  shift
  [ "$("$@")" = "${expected}" ]
}
deploy_field() { kc -n "${APP_NAMESPACE}" get deploy web -o "jsonpath=${1}" 2>/dev/null || true; }
```
- `output_is Synced app_field '{.status.sync.status}'` runs the command `app_field …` and succeeds only when it printed exactly `Synced`. Used with `wait_for` it fixes the "evaluated once" problem described above, because `wait_for` re-runs `output_is`.
- `deploy_field` reads one field of the web Deployment (a Kubernetes object that keeps a number of identical pods running). The comments in the file explain the poll-and-refresh functions the same way.

---

### 5.2 `scripts/provider.sh`: a local cluster, with k3d or kind

A **Kubernetes cluster** is a group of machines that run containers for you. For a lesson, one machine is enough, and it can be a container itself. **k3d** and **kind** are two tools that start such a one-container cluster on your laptop, using Docker. k3d starts **k3s** (a small Kubernetes); kind starts standard Kubernetes with a tool called kubeadm. This file puts both behind the same function names, so every other script is the same whichever you use.

```bash
CLUSTER_PROVIDER="${CLUSTER_PROVIDER:-k3d}"
```
- The provider is `k3d` unless `CLUSTER_PROVIDER` says otherwise (for example `CLUSTER_PROVIDER=kind make up`).

```bash
provider_context() { # <cluster>
  case "${CLUSTER_PROVIDER}" in
    k3d) echo "k3d-$1" ;;
    kind) echo "kind-$1" ;;
    *) die "CLUSTER_PROVIDER must be k3d or kind, not ${CLUSTER_PROVIDER}" ;;
  esac
}
```
- `case value in pattern) commands ;; … esac` chooses by matching. `k3d)` matches the text `k3d`; `*)` matches anything else, so a typo gives a clear error. `;;` ends each branch; `esac` ("case" backwards) ends the statement.
- `echo` prints its arguments. The function prints the context name each tool creates: `k3d-<cluster>` or `kind-<cluster>`. The text after `#` on the first line is a comment showing what argument the function expects.
- `provider_node` (next) and `provider_api_host`, `provider_exists`, `provider_delete` have the same shape.

```bash
provider_node() { # <cluster>
  case "${CLUSTER_PROVIDER}" in
    k3d) echo "k3d-$1-server-0" ;;
    kind) echo "$1-control-plane" ;;
    *) die … ;;
  esac
}
```
- Prints the name of the Docker container that is the cluster's single machine ("node"). Scripts use it to run `docker exec` commands inside it.

```bash
provider_api_host() { # <cluster>
  … k3d) echo "k3d-$1-serverlb" ;;  kind) echo "$1-control-plane" ;;
}
```
- The name other containers on the same Docker network would use to reach this cluster's **API server** (the front door of Kubernetes, port 6443). No script of this repository calls it; it is part of the provider library.

```bash
provider_exists() { # <cluster>
  case "${CLUSTER_PROVIDER}" in
    k3d) k3d cluster list --no-headers 2>/dev/null | awk '{print $1}' | grep -qx "$1" ;;
    kind) kind get clusters 2>/dev/null | grep -qx "$1" ;;
    …
```
- Answers "does a cluster with this name exist?" by exit code. For k3d: list clusters without the title line (`--no-headers`), keep only the first column with `awk '{print $1}'` (`awk` is a small text-processing program; `$1` means "first column"), and check with `grep -qx name`. `grep` searches for lines that match; `-q` means "print nothing, just set the exit code"; `-x` means "the whole line must match, not just part of it". For kind: `kind get clusters` prints one name per line.

```bash
provider_delete() { # <cluster>
  case … k3d) k3d cluster delete "$1" ;;  kind) kind delete cluster --name "$1" ;;
```
- Deletes the cluster and everything in it.

```bash
provider_create() {
  local name="$1" mappings=() network="" registry_config=""
  shift
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --network) network="$2"; shift 2 ;;
      --registry-config) registry_config="$2"; shift 2 ;;
      *) mappings+=("$1"); shift ;;
    esac
  done
```
- Creates a cluster. Usage: `provider_create name [host-port:node-port …] [--network n] [--registry-config f]`.
- `mappings=()` creates an empty **array** (a list). `mappings+=("x")` appends an item.
- `while [ "$#" -gt 0 ]; do … done` repeats while the number of remaining arguments (`$#`) is greater than 0. Inside, a `case` looks at the first argument: if it is `--network`, the next word is the network name, and `shift 2` removes both words; if it is `--registry-config`, same idea; anything else is a port mapping to remember, and `shift` removes it. This is a small hand-made **option parser**.

```bash
    k3d)
      local args=(cluster create "${name}" --servers 1 --agents 0 --image "${K3S_IMAGE}" --wait --timeout 1800s
        --k3s-arg "--disable=traefik@server:0" --k3s-arg "--disable=servicelb@server:0"
        --k3s-arg "--disable=metrics-server@server:0")
      local mapping
      for mapping in "${mappings[@]}"; do
        args+=(-p "127.0.0.1:${mapping%:*}:${mapping#*:}@loadbalancer")
      done
      [ -z "${network}" ] || args+=(--network "${network}")
      [ -z "${registry_config}" ] || args+=(--registry-config "${registry_config}")
      k3d "${args[@]}"
      ;;
```
- Builds the k3d command as an **array** `args`, adds to it, and runs it with `k3d "${args[@]}"`. Using an array keeps every argument whole, even ones with spaces.
- `--servers 1 --agents 0`: one machine that does both jobs (control plane and running pods).
- `--image "${K3S_IMAGE}"`: the exact k3s version (pinned in `versions.env`).
- `--wait --timeout 1800s`: do not return until the cluster is ready; allow up to 30 minutes, because a very busy laptop can be slow.
- `--k3s-arg "--disable=traefik@server:0"` (and two more): k3s normally installs an ingress controller, a load-balancer helper and a metrics server. This lesson needs none, so they are turned off to save memory. The `@server:0` part says "for server node number 0".
- The loop turns each `30418:30418` mapping into `-p "127.0.0.1:30418:30418@loadbalancer"`. `${mapping%:*}` removes the shortest piece matching `:*` from the **end** (leaving `30418`, the part before the colon); `${mapping#*:}` removes the shortest piece matching `*:` from the **start** (leaving the part after the colon). `-p` publishes a port: connections to your computer's `127.0.0.1:30418` are sent into the cluster.
- `[ -z "${network}" ] || args+=(…)` reads "if `network` is empty do nothing, otherwise add the flag". `-z` tests for empty text.

```bash
    kind)
      local config
      config="$(mktemp)"
      {
        cat <<'CONFIG'
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
kubeadmConfigPatches:
  - |
    kind: InitConfiguration
    timeouts:
      controlPlaneComponentHealthCheck: 10m0s
      kubernetesAPICall: 5m0s
      etcdAPICall: 5m0s
  - |
    kind: ClusterConfiguration
    apiServer:
      timeoutForControlPlane: 10m0s
    etcd:
      local:
        dataDir: /tmp/etcd
nodes:
  - role: control-plane
CONFIG
        if [ "${#mappings[@]}" -gt 0 ]; then
          echo "    extraPortMappings:"
          for mapping in "${mappings[@]}"; do
            printf '      - containerPort: %s\n        hostPort: %s\n        listenAddress: 127.0.0.1\n        protocol: TCP\n' "${mapping#*:}" "${mapping%:*}"
          done
        fi
      } > "${config}"
      kind create cluster --name "${name}" --image "${KIND_NODE_IMAGE}" --config "${config}" --wait 600s
      rm -f "${config}"
      ;;
```
- kind reads a configuration **file**, so the function writes one. `mktemp` creates an empty temporary file and prints its name.
- `{ … } > "${config}"` groups several commands and sends all their output to the file.
- `cat <<'CONFIG' … CONFIG` is a **here-document**: the lines between the two `CONFIG` markers are fed to `cat` as if typed. Quoting the first marker (`'CONFIG'`) turns off variable replacement inside, so the text is copied exactly.
- The text is **YAML** (a format for settings; see its note). `kubeadmConfigPatches` raise kubeadm's waiting limits to ten minutes, because on a busy laptop the default limits ran out; `dataDir: /tmp/etcd` puts the database of the cluster (`etcd`) on a memory-backed folder, which is much faster; `nodes: - role: control-plane` asks for one node.
- If there are port mappings, `${#mappings[@]}` (the number of items in the array) is more than zero, so the function adds an `extraPortMappings:` block with one entry per mapping, using `printf` with `%s` placeholders. `listenAddress: 127.0.0.1` keeps the port private to this machine.
- `kind create cluster … --wait 600s` does the work; `rm -f` deletes the temporary file (`-f` = do not complain if missing).

```bash
provider_load_images() { # <cluster> <image>...
  local name="$1" missing=() image
  shift
  for image in "$@"; do
    docker exec "$(provider_node "${name}")" crictl inspecti "${image}" >/dev/null 2>&1 || missing+=("${image}")
  done
  [ "${#missing[@]}" -gt 0 ] || { log "the images are already on ${name}"; return 0; }
  set -- "${missing[@]}"
  case "${CLUSTER_PROVIDER}" in
    k3d) k3d image import --cluster "${name}" "$@" ;;
    kind) kind load docker-image --name "${name}" "$@" ;;
    …
```
- The cluster machine is itself a container with its own storage, so images built on your computer are not visible to it. This function copies them in. (There is no registry here, which is a server that stores images.)
- `docker exec container command` runs a command inside a running container. `crictl inspecti image` asks the cluster machine's container runtime whether it already has the image. If not, the name is added to `missing`.
- If nothing is missing, log and `return 0`. Copying is slow, so a second `make up` skips it.
- `set -- list` replaces the function's own argument list with the missing images, so `"$@"` can be passed on. Then `k3d image import` or `kind load docker-image` copies them.

```bash
with_cluster_lock() {
  local lock=/tmp/plainround-kind-create.lock waited=0 holder status
  until mkdir "${lock}" 2>/dev/null; do
    holder="$(cat "${lock}/pid" 2>/dev/null || true)"
    if [ -n "${holder}" ] && ! kill -0 "${holder}" 2>/dev/null; then rm -rf "${lock}"; continue; fi
    [ "${waited}" -lt 7200 ] || die "gave up waiting for another cluster to finish starting"
    [ $((waited % 60)) -ne 0 ] || log "another cluster is starting; waiting for ${lock}"
    sleep 5
    waited=$((waited + 5))
  done
  echo "$$" > "${lock}/pid"
  status=0
  "$@" || status=$?
  rm -rf "${lock}"
  return "${status}"
}
```
- Starting a cluster is heavy. If several are created at the same time on one laptop they all time out. This function makes them take turns, by using a **lock**: a way for processes to agree that only one may do something at a time.
- The lock is a **folder**. `mkdir folder` either creates it (success) or fails because it exists. Creating a folder is atomic, which means two processes cannot both succeed. The process that creates it holds the lock.
- While `mkdir` fails, the loop checks who holds the lock: `cat lock/pid` prints the holder's process number. `kill -0 pid` does not kill anything; it only checks whether a process with that number is alive. `!` reverses a test. If the holder is dead, the lock is stale, so `rm -rf` removes it and `continue` jumps back to the start of the loop. (`-r` removes folders and their contents; `-f` never asks.)
- `[ condition ] || action` is a short "if not … then" form: it gives up with an error after 7200 seconds, and prints a message every 60 seconds (`%` is the remainder after division; `-ne` means "not equal").
- After the lock is taken, the function writes its own process number into the file: `$$` is the number of the current shell process. It runs the command given as arguments (`"$@"`), remembers its exit code in `status`, and **always** removes the lock afterwards, then returns the saved code.

---

### 5.3 The scripts behind `make up`

`make up` runs `scripts/up.sh`. Each script below begins with the same two lines:

```bash
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
```
- the shebang (section 4); the three safety switches (section 4); and the load of `lib.sh`, found by the script's own location, so it works from any current folder.

**`scripts/up.sh`**
```bash
require docker kubectl git curl kubeconform

"${ROOT}/scripts/cluster-up.sh"
"${ROOT}/scripts/build-images.sh"
"${ROOT}/scripts/install-git-server.sh"
"${ROOT}/scripts/install-argocd.sh"
"${ROOT}/scripts/seed-repo.sh"
"${ROOT}/scripts/bootstrap.sh"
wait_for "the web app to be synced and healthy" "${WAIT_TIMEOUT}" app_synced_and_healthy_at "$(work_head)"
"${ROOT}/scripts/status.sh"
```
- First checks the tools are installed. Then runs the six steps by their **full paths**, one after the other. Because of `set -e`, if one fails the rest do not run.
- The last two commands wait until Argo CD reports the web application as synced and healthy at the newest commit (`$(work_head)` is evaluated once, which is correct here: the commit does not change), and print a summary.
- The scripts are called by path and not through `make` so that they can be run alone, and so another process killing "make" does not stop them.

**`scripts/cluster-up.sh`**
```bash
require "${CLUSTER_PROVIDER}" kubectl docker

if provider_exists "${CLUSTER_NAME}" && ! kubectl config get-contexts -o name | grep -qx "${KUBE_CONTEXT}"; then
  log "cluster ${CLUSTER_NAME} is half-made; deleting it"
  provider_delete "${CLUSTER_NAME}"
fi
```
- `require "${CLUSTER_PROVIDER}"` checks that `k3d` (or `kind`) is installed.
- A cluster that was interrupted halfway exists as a container but has no `kubectl` context. `kubectl config get-contexts -o name` prints the context names; `grep -qx` checks for ours; `!` reverses it. Together with `provider_exists`, the test reads: "the cluster exists, but its context does not". Then it is deleted so it can be made again. (A slow but healthy cluster is never deleted; only a missing context counts.)

```bash
if provider_exists "${CLUSTER_NAME}"; then
  log "cluster ${CLUSTER_NAME} already exists"
else
  log "creating cluster ${CLUSTER_NAME} with ${CLUSTER_PROVIDER}"
  create_cluster() {
    docker rm --force "$(provider_node "${CLUSTER_NAME}")" >/dev/null 2>&1 || true
    provider_create "${CLUSTER_NAME}" "${GIT_HOST_PORT}:30418"
  }
  with_cluster_lock retry 6 10 create_cluster || die "the cluster did not start after six attempts"
fi
kc wait --for=condition=Ready node --all --timeout=180s
```
- If the cluster is already there, nothing to do. Otherwise a function `create_cluster` is defined inside the `else` branch (functions can be defined anywhere; they exist from then on).
- `create_cluster` first removes a left-over container of an earlier failed attempt (`docker rm --force name`; `|| true` because "no such container" is fine), then creates the cluster publishing port `30418` of your computer to node port `30418` (the Git server's door).
- `with_cluster_lock retry 6 10 create_cluster` combines the two tools from `lib.sh` and `provider.sh`: take the lock, then try up to 6 times with 10 seconds between tries.
- Finally, `kc wait --for=condition=Ready node --all --timeout=180s` blocks until Kubernetes says the node is ready (up to 3 minutes).

**`scripts/build-images.sh`**
```bash
require docker

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
provider_load_images "${CLUSTER_NAME}" plainround/web:1.0.0 plainround/web:1.1.0 plainround/git-server:1.0.0
```
- A **container image** is a packed folder of files plus a start command. `docker build` makes one from a recipe called a Dockerfile (see the Docker note).
- The function `build folder tag [flags]` builds the image in `${ROOT}/folder` and names it `tag`. After `shift 2`, `"$@"` holds any extra flags. `--quiet` prints only the image id, which is thrown away. `--build-arg NAME=value` passes a named value into the Dockerfile.
- Two versions of the web image (1.0.0 and 1.1.0) exist so the lesson has an "old" and a "new" to move between. The third image is the Git server. The versions come from `versions.env`.
- The last line copies all three into the cluster (section 5.2).

**`scripts/install-git-server.sh`**
```bash
require kubectl curl

kc apply --server-side -k "${ROOT}/platform/git-server" >/dev/null
kc -n git-server rollout status deployment/git-server --timeout="${WAIT_TIMEOUT}s"
wait_for "the Git server on ${GIT_HOST_URL}" 60 curl -fsS "${GIT_HOST_URL}/info/refs?service=git-upload-pack"
```
- `kubectl apply -k folder` builds the Kubernetes objects from the folder (with a tool called Kustomize) and sends them to the cluster. `--server-side` lets the cluster itself merge the change, which is what large objects need. Output is hidden.
- `rollout status deployment/git-server --timeout=…s` waits until the Deployment has finished starting its pod.
- The last line polls with `curl`, a program that makes a web request. `-f` fail on an HTTP error status, `-s` silent (no progress bar), `-S` still show an error message if it fails. The address asks the Git server for the list of branches; when it answers, the server works from your computer through port 30418.

**`scripts/install-argocd.sh`**
```bash
require kubectl

pinned="$(grep -oE 'argo-cd/v[0-9.]+/' "${ROOT}/platform/argocd/kustomization.yaml" | head -1 | tr -d '/' | sed 's/argo-cd//')"
[ "${pinned}" = "${ARGOCD_VERSION}" ] || die "platform/argocd pins ${pinned}, versions.env says ${ARGOCD_VERSION}"
```
- The Argo CD version is written in two files. This pipeline pulls it out of the Kustomize file and compares it to `versions.env`, so the two cannot disagree. Step by step: `grep -oE 'argo-cd/v[0-9.]+/'` prints only the part of the file that looks like `argo-cd/v3.5.6/` (`-o` print only the match, `-E` extended pattern; `[0-9.]+` means one or more digits or dots); `head -1` keeps the first match; `tr -d '/'` deletes slash characters; `sed 's/argo-cd//'` deletes the text `argo-cd` (`sed` edits text; `s/old/new/` replaces). What is left is `v3.5.6`.

```bash
log "installing Argo CD ${ARGOCD_VERSION}"
kc apply --server-side --force-conflicts -k "${ROOT}/platform/argocd" >/dev/null
kc -n argocd rollout status statefulset/argocd-application-controller --timeout="${WAIT_TIMEOUT}s"
for deployment in argocd-repo-server argocd-server argocd-applicationset-controller argocd-redis; do
  kc -n argocd rollout status "deployment/${deployment}" --timeout="${WAIT_TIMEOUT}s"
done
```
- Applies Argo CD. `--server-side` is needed because Argo CD's definitions are too large for the other method; `--force-conflicts` lets this command take over fields another tool had set.
- Then waits for each Argo CD part to be ready: one StatefulSet (a Deployment-like object for programs that keep stable names) and four Deployments, in a loop.

**`scripts/seed-repo.sh`**
```bash
require git curl

if [ "${1:-}" = "--reset" ]; then
  rm -rf "${WORK_CLONE}"
fi

if [ -d "${WORK_CLONE}/.git" ]; then
  log "working clone already exists at ${WORK_CLONE#"${ROOT}"/}"
  exit 0
fi
```
- `${1:-}` is the first argument, or empty text if none (with `set -u`, an unset `$1` would be an error). With `--reset`, the working clone is deleted first.
- `[ -d path ]` tests that a **directory** exists. A `.git` folder inside means "this is already a Git repository", so the script stops with `exit 0` (success). `${WORK_CLONE#"${ROOT}"/}` removes the repository folder from the front of the path so the message is short.

```bash
mkdir -p "${WORK_CLONE}"
cp -R "${ROOT}/manifests/." "${WORK_CLONE}/"
git -C "${WORK_CLONE}" init --quiet --initial-branch=main
git -C "${WORK_CLONE}" config user.name "Runbook"
git -C "${WORK_CLONE}" config user.email "runbook@example.invalid"
git -C "${WORK_CLONE}" config commit.gpgsign false
```
- `mkdir -p` creates the folder (and parents; no error if it exists). `cp -R source/. dest/` copies a folder's contents, including hidden files, recursively. The `manifests/` folder is the desired state to be put in Git.
- `git init` makes an empty repository; `--initial-branch=main` names the first branch `main`. The next three lines set the author name and email for commits (a fixed fake address on the reserved domain `example.invalid`) and switch off commit signing, so a person's global Git settings cannot stop the script.

```bash
cat > "${WORK_CLONE}/.git/hooks/pre-push" <<HOOK
#!/usr/bin/env bash
exec "${ROOT}/scripts/validate.sh" "${WORK_CLONE}"
HOOK
chmod +x "${WORK_CLONE}/.git/hooks/pre-push"
```
- A Git **hook** is a script that Git runs at a certain moment; `pre-push` runs just before a push and cancels it if it fails. This here-document (with an **unquoted** marker, so `${ROOT}` is replaced now) writes a two-line script. `exec program` replaces the shell with that program, so its exit code becomes the hook's. `chmod +x` makes the file executable.

```bash
work_git add --all
work_git commit --quiet -m "Initial desired state: web app 1.0.0, two replicas"
work_git remote add origin "${GIT_HOST_URL}"
work_git push --quiet --force origin main
log "seeded gitops-demo at $(work_head | cut -c1-7)"
```
- Stage all, make the first commit, tell Git where the **remote** copy lives (named `origin`, the address of the Git server), and push. `--force` replaces whatever is on the server (needed after a reset). `cut -c1-7` keeps the first seven characters of the commit hash for the message.

**`scripts/bootstrap.sh`**
```bash
require kubectl

kc apply -f "${ROOT}/manifests/clusters/local/project.yaml" -f "${ROOT}/manifests/clusters/local/application.yaml"
```
- The only objects applied by hand: Argo CD's **project** (what it may do) and **Application** (where to look in Git). From now on Argo CD itself keeps the cluster equal to Git. `-f file` applies a file.

**`scripts/status.sh`**
```bash
printf 'application  sync=%s  health=%s  revision=%s\n' \
  "$(app_field '{.status.sync.status}')" "$(app_field '{.status.health.status}')" \
  "$(app_field '{.status.sync.revision}' | cut -c1-7)"
printf 'syncPolicy   selfHeal=%s  prune=%s\n' \
  "$(app_field '{.spec.syncPolicy.automated.selfHeal}')" "$(app_field '{.spec.syncPolicy.automated.prune}')"
printf 'deployment   replicas=%s  image=%s\n' \
  "$(deploy_field '{.spec.replicas}')" "$(deploy_field '{.spec.template.spec.containers[0].image}')"
kc -n "${APP_NAMESPACE}" get pods,configmap web-config --no-headers 2>&1 || true
```
- Prints a three-line summary. A backslash at the end of a line continues the command on the next line. Each `%s` in the format takes the next value. The values are read with the helper functions. `containers[0]` means "the first container" of the pod description. The last line lists the pods and the ConfigMap (a Kubernetes object holding named settings) with no heading line; `2>&1` shows errors too; `|| true` keeps the script from failing.

---

---

### 5.4 The other helper scripts

**`scripts/validate.sh`: check the manifests**
```bash
require kubectl kubeconform

tree="${1:-${ROOT}/manifests}"
cache="${XDG_CACHE_HOME:-${HOME}/.cache}/plainround-kubeconform"
mkdir -p "${cache}"
common=(-strict -summary -kubernetes-version "${KUBECONFORM_KUBERNETES_VERSION}" -cache "${cache}")
crds='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```
- `kubeconform` checks Kubernetes files against the official rules for each kind of object, without needing a cluster (see its note).
- `tree` is the folder to check. `${1:-default}` means "the first argument, or the default if none was given". Without an argument it checks this repository's `manifests/`; the Git hook passes the working clone.
- `cache` is a folder where downloaded rule files are kept so later runs are faster. `${XDG_CACHE_HOME:-${HOME}/.cache}` uses the person's cache folder setting, or `~/.cache` if there is none. `$HOME` is the person's home folder.
- `common=( … )` is an **array** of options reused twice below: `-strict` (unknown fields are errors), `-summary` (print counts), the Kubernetes version to check against, and the cache folder.
- `crds` is a web address **template** for the rules of non-standard object kinds (Argo CD's). kubeconform fills in the `{{…}}` parts.

```bash
status=0
for overlay in "${tree}"/apps/*/overlays/*; do
  [ -d "${overlay}" ] || continue
  log "kustomize build ${overlay#"${tree}"/}"
  kubectl kustomize "${overlay}" | kubeconform "${common[@]}" - || status=1
done
```
- `status=0` is the result the script will exit with. The loop covers every folder that matches the pattern `apps/*/overlays/*`; the `*` is a **glob**, a wildcard that the shell expands into all matching names. If nothing matches, the pattern stays as plain text, so `[ -d "${overlay}" ] || continue` skips anything that is not a real folder.
- `kubectl kustomize folder` builds the final Kubernetes objects from a folder of Kustomize files and prints them as YAML. The pipe sends that text to `kubeconform … -`; the final `-` means "read from standard input". The file is built **first** because the pieces are only complete after the build.
- `|| status=1` records a failure without stopping the loop, so all folders are checked and all errors are shown.

```bash
if [ -d "${tree}/clusters" ]; then
  log "clusters/"
  kubeconform "${common[@]}" -schema-location default -schema-location "${crds}" "${tree}/clusters" || status=1
fi
exit "${status}"
```
- The `clusters/` folder holds Argo CD objects, which are not standard Kubernetes kinds. `-schema-location default` keeps the standard rules; the second `-schema-location` adds the community catalog for Argo CD kinds. The script ends with the saved status: 0 only if every check passed.

**`scripts/diff.sh`**
```bash
kubectl kustomize "${WORK_CLONE}/apps/web/overlays/local" | kc diff -f - || true
```
- Builds what Git says, then `kubectl diff -f -` compares it to what is live in the cluster and prints the differences. `diff` exits with 1 when it finds a difference, which would stop a `set -e` script, so `|| true` turns that into success. The script always exits 0; it is for looking, not for testing.

**`scripts/reset.sh`**
```bash
log "resetting the demo"
kc -n argocd delete application "${APP_NAME}" --ignore-not-found --wait=true --timeout=120s >/dev/null
kc delete namespace "${APP_NAMESPACE}" --ignore-not-found --wait=true --timeout=120s >/dev/null
"${ROOT}/scripts/seed-repo.sh" --reset
"${ROOT}/scripts/bootstrap.sh" >/dev/null
wait_for "the web app to be synced and healthy" "${WAIT_TIMEOUT}" app_synced_and_healthy_at "$(work_head)"
```
- Goes back to the first state of the lesson. Delete the Argo CD Application and the whole `web` namespace (`--ignore-not-found` = not an error if missing; `--wait=true` = do not return until it is really gone), then recreate the Git repository from scratch (`--reset`), apply the Application again and wait until it is healthy. The tests call this before each scenario.

**`scripts/down.sh`**
```bash
require "${CLUSTER_PROVIDER}"

provider_delete "${CLUSTER_NAME}"
rm -rf "${WORK_DIR}"
```
- Deletes the cluster and the working clone folder. Nothing else is left on the machine except the images.

**`scripts/ci-install-tools.sh`** (runs only on the automated-checks machine, not on yours)
```bash
version="v0.8.0"
curl -fsSL "https://github.com/yannh/kubeconform/releases/download/${version}/kubeconform-linux-amd64.tar.gz" | sudo tar -xz -C /usr/local/bin kubeconform
kubeconform -v
```
- Downloads kubeconform at an exact version and installs it. `curl -L` follows redirects. The download is a compressed archive (`.tar.gz`) sent through a pipe into `tar`: `-x` extract, `-z` it is gzip-compressed, `-C folder` put the result in that folder, and the last word names the one file to take from the archive. `sudo` runs the command with administrator rights (needed to write to `/usr/local/bin`). `kubeconform -v` prints its version as a check.

---

### 5.5 `scripts/run.sh` and the runbook

```bash
step() { printf '\n==== %s ====\n' "$*"; }

"${ROOT}/scripts/reset.sh"
step "Step 2: change it through Git"
"${ROOT}/scripts/runbook/02-change-through-git.sh"
step "Step 3a: drift it by hand, self-heal off"
"${ROOT}/scripts/runbook/03-drift.sh" off
…
```
- `step` prints a banner line so the output is easy to follow. `run.sh` resets, then runs every runbook script in order. Several scripts take one **argument** (`off`, `on`, `bad`, `rollback`, `restore`) that chooses a variant. The step numbers follow the lesson.

First, three words from the lesson. **Drift** means the live cluster differs from Git because someone changed it by hand. **Self-heal** is Argo CD's option to undo such changes automatically. **Prune** is its option to delete cluster objects that were removed from Git.

**`scripts/runbook/02-change-through-git.sh`**
```bash
deployment="${WORK_CLONE}/apps/web/base/deployment.yaml"
configmap="${WORK_CLONE}/apps/web/base/configmap.yaml"

perl -pi -e 's/^  replicas: 2$/  replicas: 3/' "${deployment}"
perl -pi -e 's/(plainround.dev\/config-revision: )"1"/$1"2"/' "${deployment}"
perl -pi -e 's/^  GREETING: hello$/  GREETING: hi there/' "${configmap}"
```
- Edits three lines in the working clone with `perl`. `perl -pi -e 'code' file`: `-e` gives the code, `-p` runs it for every line of the file and prints the line, `-i` writes the result back into the same file. `s/old/new/` replaces text matching a **regular expression** (a pattern): `^` is the start of a line, `$` the end, `(…)` remembers a part and `$1` writes it back. In the second command the slash inside the pattern is escaped as `\/`.
- Effects: two replicas become three; a note (annotation) on the pod template changes from `"1"` to `"2"` so the pods restart (environment variables are only read when a container starts, so a ConfigMap change alone would not reach running pods); the greeting changes.

```bash
sha="$(commit_and_push "Scale web to 3 replicas and change the greeting")"
log "pushed ${sha:0:7}; waiting for the controller (it polls Git every 20 seconds)"
wait_for "the app synced and healthy at ${sha:0:7}" "${WAIT_TIMEOUT}" app_synced_and_healthy_at "${sha}"
three_ready() { [ "$(deploy_field '{.status.readyReplicas}')" = "3" ] && [ "$(deploy_field '{.status.updatedReplicas}')" = "3" ]; }
wait_for "3 ready replicas on the new pods" "${WAIT_TIMEOUT}" three_ready
```
- Commit and push; `${sha:0:7}` is the first 7 characters of the hash (start at 0, length 7). Wait until Argo CD has applied exactly this commit, then until three pods are ready and all three are new (a function, so it is re-run at each poll).

```bash
echo "replicas:  $(deploy_field '{.spec.replicas}')"
echo "GREETING:  $(kc -n "${APP_NAMESPACE}" exec deploy/web -- printenv GREETING)"
echo "running from commit: $(app_field '{.status.sync.revision}' | cut -c1-7)  (git log: $(work_git log -1 --format='%h %s'))"
echo "history (deployment id, commit):"
kc -n argocd get application "${APP_NAME}" -o 'jsonpath={range .status.history[*]}  {.id}  {.revision}{"\n"}{end}'
```
- Prints the proof: the replica count; the greeting seen **inside** a pod (`kubectl exec deploy/web -- printenv GREETING` runs the program `printenv` inside a pod of the Deployment); the commit that is running next to the newest Git commit (`git log -1 --format='%h %s'` prints the short hash and the subject of the last commit); and Argo CD's history list. The JSONPath `range … end` loops over the list `history`, printing id and commit on each line.

**`scripts/runbook/03-drift.sh`** takes one argument, `off` or `on`.
```bash
drift_by_hand() {
  kc -n "${APP_NAMESPACE}" scale deploy web --replicas=5
  kc -n "${APP_NAMESPACE}" patch configmap web-config --type merge -p '{"data":{"GREETING":"hacked"}}'
}

live_greeting() { kc -n "${APP_NAMESPACE}" get configmap web-config -o 'jsonpath={.data.GREETING}'; }
live_replicas() { deploy_field '{.spec.replicas}'; }
git_replicas() { grep -E '^  replicas:' "${WORK_CLONE}/apps/web/base/deployment.yaml" | awk '{print $2}'; }
git_greeting() { grep -E '^  GREETING:' "${WORK_CLONE}/apps/web/base/configmap.yaml" | sed 's/^  GREETING: //'; }
back_to_git() { [ "$(live_replicas)" = "$(git_replicas)" ] && [ "$(live_greeting)" = "$(git_greeting)" ]; }
```
- `drift_by_hand` changes the live cluster directly: `scale` sets five replicas; `patch` rewrites the greeting. Git is untouched.
- The `live_*` functions read the cluster; the `git_*` functions read the working clone: `grep -E 'pattern'` prints matching lines; `awk '{print $2}'` prints the second word of the line (the number); `sed 's/^  GREETING: //'` deletes the key and leaves the value. `back_to_git` is true when cluster and Git agree on both values.

```bash
case "${1:-}" in
  off)
    set_sync_policy selfHeal false
    drift_by_hand
    wait_for "the app to report OutOfSync" 60 output_is OutOfSync app_field '{.status.sync.status}'
    echo "--- what differs between Git and the cluster (kubectl diff):"
    "${ROOT}/scripts/diff.sh" | grep -E '^[-+] +(replicas|GREETING):' || true
    sleep 45 # two poll intervals: a controller that was going to revert it would have done so
    echo "after 45 seconds: replicas=$(live_replicas) GREETING=$(live_greeting) sync=$(app_field '{.status.sync.status}')"
    ;;
```
- Variant `off`: turn self-heal off, drift, wait until Argo CD reports `OutOfSync` (it noticed), show the differing lines from `diff.sh` (`grep` keeps lines that start with `-` or `+`, then spaces, then the words), then wait 45 seconds, which is two poll intervals, to prove that nothing reverts it, and print the live values. This proves a negative: if Argo CD were going to fix it, it would have by now.

```bash
  on)
    set_sync_policy selfHeal true
    wait_for "the leftover drift to be reverted" 60 back_to_git
    drift_by_hand
    echo "drifted by hand: replicas=$(live_replicas) GREETING=$(live_greeting)"
    started=$SECONDS
    wait_for "both objects to return to Git's values" 60 back_to_git
    echo "reverted in $((SECONDS - started))s: replicas=$(live_replicas) GREETING=$(live_greeting) sync=$(app_field '{.status.sync.status}')"
    ;;
  *)
    die "usage: 03-drift.sh off|on"
    ;;
esac
```
- Variant `on`: turn self-heal on (Argo CD first reverts the leftover drift from the previous variant), drift again, and time how long the revert takes. `SECONDS` is a Bash variable that counts the seconds since the script started; subtracting two readings gives the elapsed time. The `*)` branch is the usage error for any other argument.

**`scripts/runbook/04-prune.sh`** takes `off`, `on` or `restore`.
```bash
marker="${WORK_DIR}/prune-commit"
configmap_present() { kc -n "${APP_NAMESPACE}" get configmap web-config >/dev/null 2>&1; }
configmap_gone() { ! configmap_present; }
```
- `marker` is a file that remembers the hash of the deleting commit between runs. `configmap_present` succeeds if the object can be fetched; `configmap_gone` is its opposite (`!` reverses an exit code).

```bash
  off)
    set_sync_policy prune false
    work_git rm --quiet apps/web/base/configmap.yaml
    perl -ni -e 'print unless /^  - configmap.yaml$/' "${WORK_CLONE}/apps/web/base/kustomization.yaml"
    sha="$(commit_and_push "Delete the web ConfigMap")"
    echo "${sha}" > "${marker}"
    wait_for "the app to report OutOfSync" 90 output_is OutOfSync app_field '{.status.sync.status}'
    sleep 30
    echo "ConfigMap web-config in the cluster: $(configmap_present && echo present || echo gone)"
    echo "sync=$(app_field '{.status.sync.status}')  resources needing prune:"
    kc -n argocd get application "${APP_NAME}" \
      -o 'jsonpath={range .status.resources[?(@.requiresPruning==true)]}  {.kind}/{.name}{"\n"}{end}'
    ;;
```
- Turn prune off. `git rm` removes the ConfigMap's file from Git and stages the removal. The `perl -ni -e 'print unless …'` command removes the line `- configmap.yaml` from the list in the Kustomize file (`-n` means do not print automatically, so only lines that pass the `unless` test are printed; with `-i` that rewrites the file without that line). Without this, building the manifests would fail on a missing file.
- Commit, remember the hash, wait for `OutOfSync`, wait 30 seconds, then show that the ConfigMap is **still there** (`a && echo present || echo gone` prints one word depending on the result) and print which resources Argo CD says need pruning (a JSONPath filter `[?(@.requiresPruning==true)]` selects list entries that have that field set to true).

```bash
  on)
    set_sync_policy prune true
    wait_for "the ConfigMap to be pruned" 90 configmap_gone
    wait_for "the app to be Synced" 60 output_is Synced app_field '{.status.sync.status}'
    kc -n "${APP_NAMESPACE}" get configmap web-config 2>&1 || true
    ;;
  restore)
    [ -f "${marker}" ] || die "no deletion commit recorded; run 04-prune.sh off first"
    work_git revert --no-edit "$(cat "${marker}")" >/dev/null
    work_git push --quiet origin main
    wait_for "the ConfigMap to be back" 90 configmap_present
    wait_for "the app to be Synced and Healthy" "${WAIT_TIMEOUT}" app_synced_and_healthy_at "$(work_head)"
    ;;
```
- `on`: turn prune on; the same Git state now makes Argo CD delete the object. The last line shows the "not found" error as proof.
- `restore`: `git revert` creates a **new commit that undoes** the earlier one (history is kept). `--no-edit` accepts the default message. Push it and wait until the ConfigMap is back. `cat "${marker}"` supplies the saved hash; `[ -f … ] || die …` checks the marker exists.

**`scripts/runbook/05-break-and-rollback.sh`** takes `bad` or `rollback`.
```bash
  bad)
    perl -pi -e 's/newTag: 1\.0\.0/newTag: 1.1.0/' "${WORK_CLONE}/apps/web/overlays/local/kustomization.yaml"
    perl -0pi -e 's#(readinessProbe:\s+httpGet:\s+path: )/healthz#$1/definitely-missing#' \
      "${WORK_CLONE}/apps/web/base/deployment.yaml"
    sha="$(commit_and_push "Ship web 1.1.0 (readiness probe points at a missing path)")"
    echo "${sha}" > "${marker}"
    wait_for "the controller to report Degraded" "${WAIT_TIMEOUT}" output_is Degraded app_field '{.status.health.status}'
    echo "health=$(app_field '{.status.health.status}')  image=$(live_image)"
    echo "ready replicas: $(deploy_field '{.status.readyReplicas}') of $(deploy_field '{.spec.replicas}') (the old pods keep serving)"
    ;;
```
- Ships a version that cannot become ready. The first `perl` changes the image tag from 1.0.0 to 1.1.0 (`\.` is a literal dot). The second uses `-0` (read the whole file as one string) so the pattern can span several lines: `\s+` matches any run of spaces and line breaks. It finds the **readiness probe** (the check Kubernetes uses to decide if a pod may receive traffic) and changes its path from `/healthz` to a path that does not exist. `#` is used as the delimiter instead of `/`, so the slashes in the path need no escaping.
- Commit, wait for Argo CD to report `Degraded`, and print the state. Because the Deployment replaces pods one by one and never removes an old pod before a new one is ready, the old pods keep serving.

```bash
  rollback)
    [ -f "${marker}" ] || die "no bad commit recorded; run 05-break-and-rollback.sh bad first"
    work_git revert --no-edit "$(cat "${marker}")" >/dev/null
    work_git push --quiet origin main
    sha="$(work_head)"
    wait_for "the app Synced and Healthy at ${sha:0:7}" "${WAIT_TIMEOUT}" app_synced_and_healthy_at "${sha}"
    echo "health=$(app_field '{.status.health.status}')  image=$(live_image)  (rolled back by $(work_git log -1 --format='%h %s'))"
    ;;
```
- The rollback is a Git revert of the bad commit. No `kubectl` command touches the cluster: Argo CD applies the revert like any other commit. `live_image` (defined at the top) prints the image of the running Deployment.

**`scripts/runbook/06-bad-manifest.sh`**
```bash
before_replicas="$(deploy_field '{.spec.replicas}')"
perl -pi -e 's/^  replicas: \d+$/  replicas: "many"/' "${WORK_CLONE}/apps/web/base/deployment.yaml"
work_git add --all
work_git commit --quiet -m "Set replicas to a string"
bad="$(work_head)"
```
- Replaces a number (`\d+` = one or more digits) by the text `"many"`, which is not a valid replica count, and commits it locally (not pushed yet).

```bash
echo "--- 1. the pre-push hook refuses it:"
if work_git push origin main; then die "the hook let an invalid manifest through"; fi

echo "--- 2. skipping the hook (--no-verify): the cluster refuses it:"
work_git push --quiet --no-verify origin main
operation_failed() { [[ "$(app_field '{.status.operationState.phase}')" =~ ^(Failed|Error)$ ]]; }
wait_for "the controller to report a failed sync" 120 operation_failed
echo "operation phase: $(app_field '{.status.operationState.phase}')"
echo "message: $(app_field '{.status.operationState.message}' | cut -c1-200)"
echo "live replicas still: $(deploy_field '{.spec.replicas}') (was ${before_replicas})"

echo "--- 3. git revert clears it:"
work_git revert --no-edit "${bad}" >/dev/null
work_git push --quiet origin main
wait_for "the app Synced and Healthy again" "${WAIT_TIMEOUT}" app_synced_and_healthy_at "$(work_head)"
```
- Defense 1: the push is **expected to fail** because the Git hook (which runs the manifest check) rejects it. `if command; then die …; fi` reverses the usual use: if the push succeeds, the script stops with an error.
- Defense 2: `--no-verify` skips the hook. The push succeeds, but the cluster refuses the object, and Argo CD reports a failed sync. `[[ … =~ regex ]]` is Bash's own pattern test (double brackets); the regex `^(Failed|Error)$` means the whole text is `Failed` or `Error`. The script prints the first 200 characters of the message and shows that the live replica count did not change.
- Recovery: revert and push.

---

### 5.6 The second tool: `scripts/compare/`

Step 6 of the lesson repeats the same three behaviors with Flux in a second cluster.

**`scripts/compare/env.sh`**
```bash
COMPARE_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export CLUSTER_NAME=gitops-drift-flux
export GIT_HOST_PORT=30419
export WORK_DIR="${COMPARE_ROOT}/.work-flux"
```
- Sourced **before** `lib.sh`. It sets a different cluster name, a different port and a different working folder. Because `lib.sh` uses `${CLUSTER_NAME:-default}`, these values win, so every helper acts on the second cluster. The two clusters never share anything.

**`scripts/compare/flux-up.sh`**
```bash
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "${COMPARE_ROOT}/scripts/lib.sh"

pinned="$(grep -oE 'flux2/releases/download/v[0-9.]+/' "${ROOT}/platform/flux/kustomization.yaml" | head -1 | cut -d/ -f4)"
[ "${pinned}" = "${FLUX_VERSION}" ] || die "platform/flux pins ${pinned}, versions.env says ${FLUX_VERSION}"

"${ROOT}/scripts/cluster-up.sh"
"${ROOT}/scripts/build-images.sh"
"${ROOT}/scripts/install-git-server.sh"
"${ROOT}/scripts/seed-repo.sh"
```
- Same version check as for Argo CD. `cut -d/ -f4` splits each line at `/` and keeps the fourth piece. Then the same first steps as `make up`, all acting on the second cluster because `env.sh` was loaded first.

```bash
log "installing Flux ${FLUX_VERSION}"
kc apply --server-side --force-conflicts -k "${ROOT}/platform/flux" >/dev/null
kc -n flux-system rollout status deployment/source-controller --timeout=240s
kc -n flux-system rollout status deployment/kustomize-controller --timeout=240s
kc apply -f "${ROOT}/platform/flux/sync.yaml"
wait_for "the Flux Kustomization to be Ready" "${WAIT_TIMEOUT}" \
  bash -c "kubectl --context ${KUBE_CONTEXT} -n flux-system get kustomization web -o 'jsonpath={.status.conditions[?(@.type==\"Ready\")].status}' | grep -qx True"
```
- Install Flux, wait for its two controllers, apply the two objects that point it at Git, and wait for it to report `Ready`. The last wait uses `bash -c "…"`, which runs a string as a command; this is how a `|` pipeline is passed to `wait_for`. `grep -qx True` succeeds only if the status is exactly `True`.

**`scripts/compare/flux-behaviors.sh`**
```bash
kustomization_field() { kc -n flux-system get kustomization web -o "jsonpath=${1}" 2>/dev/null || true; }
ready() { kustomization_field '{.status.conditions[?(@.type=="Ready")].status}'; }
ready_is() { [ "$(ready)" = "$1" ]; }
configmap_present() { kc -n "${APP_NAMESPACE}" get configmap web-config >/dev/null 2>&1; }
configmap_gone() { ! configmap_present; }
replicas_are() { [ "$(deploy_field '{.spec.replicas}')" = "$1" ]; }
greeting_is() { [ "$(kc -n "${APP_NAMESPACE}" get configmap web-config -o 'jsonpath={.data.GREETING}')" = "$1" ]; }
drift_reverted() { replicas_are 2 && greeting_is hello; }

wait_for "Flux Ready before the experiments" "${WAIT_TIMEOUT}" ready_is True
```
- Small question-functions, as in `lib.sh`, but for Flux's object (a Flux `Kustomization` reports `Ready` True or False).

```bash
# 1. Self-healing: nothing to switch on.
started=$SECONDS
kc -n "${APP_NAMESPACE}" scale deploy web --replicas=5 >/dev/null
kc -n "${APP_NAMESPACE}" patch configmap web-config --type merge -p '{"data":{"GREETING":"hacked"}}' >/dev/null
wait_for "Flux to revert the drift" 120 drift_reverted
echo "RESULT drift: replicas 5 -> $(deploy_field '{.spec.replicas}') and GREETING hacked -> hello in $((SECONDS - started))s with prune=false and no self-heal setting"
```
- The same drift as with Argo CD. Flux needs no option for self-healing because it re-applies Git on every interval. The line starting `RESULT` is read by the test.

```bash
# 2. Pruning
work_git rm --quiet apps/web/base/configmap.yaml
perl -ni -e 'print unless /^  - configmap.yaml$/' "${WORK_CLONE}/apps/web/base/kustomization.yaml"
deletion="$(commit_and_push "Delete the web ConfigMap")"
sleep 40
echo "RESULT prune-off: ConfigMap $(configmap_present && echo present || echo gone) after 40s, Kustomization Ready=$(ready) (Flux raises no out-of-sync flag)"
kc -n flux-system patch kustomization web --type merge -p '{"spec":{"prune":true}}' >/dev/null
wait_for "Flux to prune the ConfigMap" 120 configmap_gone
echo "RESULT prune-on: ConfigMap gone after spec.prune=true"
work_git revert --no-edit "${deletion}" >/dev/null
work_git push --quiet origin main
wait_for "the ConfigMap to come back" 120 configmap_present
wait_for "Flux Ready again" 120 ready_is True
```
- Delete the file; with prune off the object stays after 40 seconds; turn prune on and the object disappears; revert brings it back.

```bash
# 3. Health
perl -pi -e 's/newTag: 1\.0\.0/newTag: 1.1.0/' "${WORK_CLONE}/apps/web/overlays/local/kustomization.yaml"
perl -0pi -e 's#(readinessProbe:\s+httpGet:\s+path: )/healthz#$1/definitely-missing#' "${WORK_CLONE}/apps/web/base/deployment.yaml"
bad="$(commit_and_push "Ship web 1.1.0 (readiness probe points at a missing path)")"
wait_for "Flux Ready=False after the bad commit" 240 ready_is False
echo "RESULT health: Ready=False, reason=$(kustomization_field '{.status.conditions[?(@.type=="Ready")].reason}') after the bad commit"
work_git revert --no-edit "${bad}" >/dev/null
work_git push --quiet origin main
wait_for "Flux Ready=True after git revert" 240 ready_is True
echo "RESULT rollback: Ready=True, image=$(deploy_field '{.spec.template.spec.containers[0].image}') after git revert"
```
- The bad commit makes Flux report `Ready=False` (because its configuration waits for the application's health); the revert restores `Ready=True`.

**`scripts/compare/flux-down.sh`**
```bash
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
source "${COMPARE_ROOT}/scripts/lib.sh"
require "${CLUSTER_PROVIDER}"

provider_delete "${CLUSTER_NAME}"
rm -rf "${WORK_DIR}"
```
- Deletes the second cluster and its working folder. `make compare` runs this even if the tests failed.

---

### 5.7 The Git server's start-up script

**`docker/git-server/entrypoint.sh`** is the program a container runs when it starts. It uses `#!/bin/sh`, the smaller standard shell, because the container image has no Bash.
```sh
#!/bin/sh
set -eu

for repo in ${REPOS:?set REPOS to the repository names to create}; do
  path="/srv/git/${repo}.git"
  if [ ! -d "${path}" ]; then
    git init --quiet --bare --initial-branch=main "${path}"
    git -C "${path}" config http.receivepack true
  fi
done

rm -f /tmp/fcgiwrap.sock
fcgiwrap -s unix:/tmp/fcgiwrap.sock &
exec nginx -g 'daemon off;'
```
- `set -eu`: stop on error and on unset variables (`pipefail` does not exist in plain `sh`).
- `${REPOS:?message}` reads the variable `REPOS` and **stops with the message** if it is unset or empty. The Kubernetes manifest sets it to `gitops-demo`. The unquoted use in the `for` list lets the shell split a list of names separated by spaces.
- For each name, if the folder does not exist (`! [ -d … ]` written `[ ! -d … ]`), create a **bare** repository (`--bare` = only the history, no working files; what a server holds). `config http.receivepack true` allows pushes over HTTP.
- `rm -f` removes an old socket file (a socket is a special file used for talking between two programs on the same machine). `fcgiwrap -s unix:/tmp/fcgiwrap.sock &` starts a helper program in the **background** (the `&` at the end). It lets the web server run Git. `exec nginx -g 'daemon off;'` replaces the shell with the nginx web server, running in the foreground (a container ends when its main process ends). Being the main process, nginx receives the stop signal directly when Kubernetes stops the container.

<!-- full-walkthrough:begin -->
### 5.8 The remaining lines: the configuration files and a few repeated lines

#### The two small configuration files

`versions.env` and `.env` are **environment files**: plain text with one `NAME=value` per line. They are not run; the scripts load them with `source`, which turns each line into a variable.

```bash
# Every version this project pins. Scripts and the Makefile source this file; change a version here only.
KIND_NODE_IMAGE=kindest/node:v1.35.8@sha256:07b2536e30b803ed61d1677a79df6115f798ce64c80f9e22f6ed45afd09323c0
ARGOCD_VERSION=v3.5.6
FLUX_VERSION=v2.10.0
WEB_BASE_IMAGE=nginxinc/nginx-unprivileged:1.31.7-alpine@sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e
GIT_SERVER_BASE_IMAGE=alpine:3.24.3@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a
KUBECONFORM_KUBERNETES_VERSION=1.35.0
K3S_IMAGE=rancher/k3s:v1.35.5-k3s1
```

- Every version the project depends on, in one place. `KIND_NODE_IMAGE`, `WEB_BASE_IMAGE` and `GIT_SERVER_BASE_IMAGE` are container images written as `name:tag@sha256:…`. The part after `@sha256:` is a **digest**, a long checksum of the exact bytes of the image; unlike a tag it cannot be re-pointed, so the build always gets the same image. `ARGOCD_VERSION` and `FLUX_VERSION` are the controller versions (checked against the Kustomize files by the scripts). `KUBECONFORM_KUBERNETES_VERSION` is the Kubernetes version the manifest checker uses. `K3S_IMAGE` is the k3s image `provider_create` passes to k3d.

The `.env` file is copied from `.env.example` by `make up`. The example holds two settings with a comment above each explaining what it is for; the values are the defaults that `lib.sh` would use anyway, so a person can see them and change them:

```
# Copied to .env by `make up`. Nothing here is a secret; every value has a default in scripts/lib.sh.
CLUSTER_NAME=gitops-drift
# How long the runbook and the tests wait for the controller, in seconds.
WAIT_TIMEOUT=240
```

- `CLUSTER_NAME` is the name of the local cluster (and so of its `kubectl` context); `WAIT_TIMEOUT` is how many seconds scripts and tests wait for the controller.

#### Lines that repeat in every script

Each runbook script loads the library with the same line, which differs from the other scripts' because they sit one folder deeper:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/../lib.sh"
```

- `"$(dirname "${BASH_SOURCE[0]}")/../lib.sh"`: the folder of this script, then `..` (up one level, from `scripts/runbook/` to `scripts/`), then `lib.sh`. The same line is the 6th line in `03-drift.sh` and `06-bad-manifest.sh`, the 7th in `04-prune.sh`, and in `05-break-and-rollback.sh`.

```bash
    k3d) echo "k3d-$1-serverlb" ;;
```

- In `provider_api_host`, for k3d: the API server of a k3d cluster is reached through the cluster's **load balancer** container, named `k3d-<cluster>-serverlb`.

```bash
    k3d) k3d cluster delete "$1" ;;
    kind) kind delete cluster --name "$1" ;;
```

- In `provider_delete`: `k3d cluster delete <name>` for k3d, and `kind delete cluster --name <name>` for kind.

#### `scripts/run.sh` lines 14-28

```bash
step "Step 3b: drift it by hand, self-heal on"
"${ROOT}/scripts/runbook/03-drift.sh" on
step "Step 4a: delete the ConfigMap's file, prune off"
"${ROOT}/scripts/runbook/04-prune.sh" off
step "Step 4b: the same deletion, prune on"
"${ROOT}/scripts/runbook/04-prune.sh" on
step "Step 4c: bring the ConfigMap back with git revert"
"${ROOT}/scripts/runbook/04-prune.sh" restore
step "Step 5a: a bad commit"
"${ROOT}/scripts/runbook/05-break-and-rollback.sh" bad
step "Step 5b: git revert"
"${ROOT}/scripts/runbook/05-break-and-rollback.sh" rollback
step "Extra: a manifest the schema refuses"
"${ROOT}/scripts/runbook/06-bad-manifest.sh"
step "Where it ended"
```

- Continue the list started in section 5.5: step 3b (self-heal on), step 4 in three parts (prune off, prune on, restore), step 5 in two parts (a bad commit, `git revert`), the manifest the schema refuses, and a final status. Each runbook script is called by its full path; the argument chooses the variant.

#### Three more lines of the runbook

```bash
    die "usage: 04-prune.sh off|on|restore"
```

- The `*)` branch of the `case` is the usage error: any argument other than `off`, `on` or `restore` makes the script stop with `die` and the message `usage: 04-prune.sh off|on|restore`.

```bash
marker="${WORK_DIR}/bad-commit"
live_image() { deploy_field '{.spec.template.spec.containers[0].image}'; }
```

- `marker` is the file in which the bad commit's hash is remembered, so `rollback` knows what to revert. `live_image` is a small function that prints the image of the running Deployment (`jsonpath` of `.spec.template.spec.containers[0].image`).

```bash
    die "usage: 05-break-and-rollback.sh bad|rollback"
```

- The same usage-error branch for `bad|rollback`.
<!-- full-walkthrough:end -->

## 6. Try it yourself

1. Check every script for mistakes without running them: `shellcheck scripts/*.sh scripts/*/*.sh docker/git-server/entrypoint.sh`. No output means no findings.
2. Load the library and test a helper: `bash -c 'source scripts/lib.sh; output_is hi echo hi && echo yes'`. It prints `yes`. Change the first `hi` to `no`: nothing is printed, because the command succeeded silently with exit code 1; run `echo $?` right after to see `1`.
3. See that messages go to standard error: `bash -c 'source scripts/lib.sh; log hello' 2>/dev/null` prints nothing (the message was thrown away); remove `2>/dev/null` and it appears.
4. Watch a script run line by line: `bash -x scripts/status.sh 2>&1 | head -30` (needs the cluster; `-x` prints each command before running it with a `+` in front).
5. Count words in a pattern: `grep -oE 'argo-cd/v[0-9.]+/' platform/argocd/kustomization.yaml` prints `argo-cd/v3.5.6/`.

## 7. Mistakes people make

- **Leaving a variable unquoted.** `rm -rf $dir/` with an empty `dir` becomes `rm -rf /`. Every variable here is in double quotes, and `set -u` stops on unset names.
- **Forgetting that `$(…)` runs once.** `wait_for "x" 60 test "$(cmd)" = ok` never recovers if the first answer is wrong. Use a function, as this repository does.
- **Ignoring failures.** Without `set -e`, a script continues after an error and does damage later. `set -euo pipefail` is on in every script.
- **Using `cd` in a script and then relative paths.** The scripts compute `ROOT` once and use full paths.
- **Writing Bash features in `sh` scripts.** `[[ … ]]`, arrays and `${var:0:7}` do not exist in plain `sh`; the container's entrypoint avoids them.
- **Using `echo` for exact output.** `printf` is predictable; `echo` differs between systems about backslashes and `-n`.

## 8. Check yourself

1. What does the exit code `0` mean, and how does `if`, `&&` or `until` use it?
   *Answer:* It means success. `if`, `&&`, `||`, `while` and `until` run commands or stop depending on whether the previous command returned 0 or another number.
2. What is the difference between `source lib.sh` and `./lib.sh`?
   *Answer:* `source` runs the lines in the current shell, so its functions and variables stay available. `./lib.sh` starts a child process whose variables and functions vanish when it ends.
3. Why does `wait_for` get a function name, not `"$(command)"`?
   *Answer:* `$(…)` is evaluated once before the call, so the loop would compare the same text forever. A function is re-run at every poll.
4. What do the three parts of `set -euo pipefail` do?
   *Answer:* `-e` stops at the first failing command; `-u` makes an unset variable an error; `pipefail` makes a pipeline fail if any part fails.
5. In `a=$(cd "$(dirname "$0")/.." && pwd)`, why does the `cd` not change the folder of the running script?
   *Answer:* `$( … )` runs in a sub-shell (a child copy of the shell); changes made there do not affect the parent.

## 9. Further reading

- Bash Reference Manual: <https://www.gnu.org/software/bash/manual/bash.html> (shell parameter expansion, conditional constructs, redirections, the `set` builtin, arrays).
- `perl -pi -e` options: <https://perldoc.perl.org/perlrun>.
- `kubectl` JSONPath: <https://kubernetes.io/docs/reference/kubectl/jsonpath/>.
- Versions: the Mac that built this uses Bash 3.2; the checks run on Bash 5. The scripts use only features available in both. (Not re-checked against the manuals in this session.)
