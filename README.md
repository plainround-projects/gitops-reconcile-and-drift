# gitops-reconcile-and-drift

A local Kubernetes cluster (k3d by default, kind optional) managed by Argo CD from a small Git repository: the controller applies a web app from Git, puts back a manual edit, prunes what you delete from Git, and rolls back with `git revert`. Every step of the lesson is a script, and a test proves each one.

| | |
| --- | --- |
| **Lesson** | `/prep/gitops/project-reconcile-and-drift`, "Run a GitOps controller and watch it reconcile" (`data-structure-explainer/src/content/tracks/gitops/13-project-reconcile-and-drift.md` in the Plainround app) |
| **Planned hours** | 5 |
| **Level** | Beginner |
| **Architecture** | [ARCHITECTURE.md](ARCHITECTURE.md), decisions in [docs/adr](docs/adr) |

## Prerequisites

| Tool | Version | Used for |
| --- | --- | --- |
| Docker | 24 or newer (tested with 24.0.6), 4 GB or more of memory for its VM | the cluster node, the image builds |
| k3d | 5.9 or newer (tested with 5.9.0, k3s v1.35.5) | the local cluster, the default (`brew install k3d`); the k3s image is pinned in `versions.env` |
| kind | 0.33 or newer (tested with 0.33.0) | optional: `CLUSTER_PROVIDER=kind make up` uses kind (`kindest/node:v1.35.8`, pinned by digest in `versions.env`) |
| kubectl | 1.35 (includes Kustomize) | every script |
| kubeconform | 0.8 | the schema check in the pre-push hook and in `make lint` (`brew install kubeconform`) |
| shellcheck, yamllint | any recent | `make lint` (`brew install shellcheck yamllint`; yamllint is also installed into `.venv`) |
| Python | 3.12 or 3.13 (tested with 3.13) | the tests; `make` installs `pytest`, `ruff`, `mypy` and `pyyaml` into `.venv/` from a hash-pinned lock file |
| git, curl, GNU Make | any recent | scripts |
| Argo CD | v3.5.6, installed by `make up` from the pinned manifests | the controller |
| Network | for the first `make up` | Argo CD's manifests, the kubeconform schemas and the base images |

No cloud account, no secrets, no Git hosting account: the repository the controller watches is served from inside the cluster (see [ADR 0002](docs/adr/0002-an-in-cluster-git-server.md)). Port 30418 on `127.0.0.1` must be free.

## Setup, run, test, stop

```bash
make up              # cluster, images, Git server, Argo CD, the seeded repository, the Application (about 5 minutes on a warm cache)
make run             # the whole lesson as one scripted run (about 10 minutes)
make test            # offline tests with coverage, then the cluster tests (about 15 minutes)
make lint            # yamllint, kubeconform, shellcheck, ruff, mypy
make compare         # step 6: install Flux in a second cluster, run the same three behaviors, delete it
make down            # delete the cluster and the working clone
```

`make help` lists every target. `make status` prints one screen: what the controller reports and what the cluster holds. The working clone of the repository the controller watches is `.work/gitops-demo`; look at its `git log` after a run.

## Done when: the lesson's checklist and the proof for each line

| # | Done when (from the lesson) | Command | What proves it |
| --- | --- | --- | --- |
| 1 | The app appears in the cluster without any `kubectl apply` from you, and the controller shows it as synced and healthy. | `make up`, then `make status` | `tests/cluster/test_01_first_sync.py`: the Application is `Synced` and `Healthy` at the seeded commit, the Deployment's `managedFields` name `argocd-controller` and no `kubectl` manager, two pods run, and the Service answers `hello`. |
| 2 | The cluster follows within the sync interval, and you can name the commit each running object came from. | `scripts/runbook/02-change-through-git.sh` | `test_02_change_through_git.py`: 3 replicas, the greeting `hi there` in the ConfigMap, in the pod's environment and in the Service's answer; `status.sync.revision` and the last `status.history` entry equal the commit the script pushed. |
| 3 | With self-healing off, the controller reports the app as out of sync and shows the difference; with it on, both changes are reverted automatically. | `scripts/runbook/03-drift.sh off`, then `on` | `test_03_drift.py`: after `kubectl scale` and `kubectl patch`, the Application is `OutOfSync`, `kubectl diff` shows `replicas` and `GREETING`, and the objects are still changed 45 seconds later; after `selfHeal: true` both return to 3 and `hi there` with no command from the tester. |
| 4 | With pruning off the object stays and is flagged; with it on, the object is removed, and you write down when you would turn pruning off. | `scripts/runbook/04-prune.sh off`, `on`, `restore` | `test_04_prune.py`: the ConfigMap is present and `ConfigMap/web-config` is listed as needing pruning with prune off; `NotFound` with prune on; `git revert` brings it back. When to turn pruning off: [below](#when-i-would-turn-pruning-off). |
| 5 | The controller reports the app as degraded after the bad commit, and healthy again after the revert, with no command run against the cluster. | `scripts/runbook/05-break-and-rollback.sh bad`, `rollback` | `test_05_rollback.py`: `Degraded` after the commit (image 1.1.0, readiness probe on a missing path) while the old pods keep answering `1.0.0`; after `git revert` the image is `plainround/web:1.0.0` again and the Application is `Healthy` and `Synced` at the revert commit. The scripts run only `git` against the repository. |
| 6 | A short table in the README compares how each one handles self-healing, pruning and health checks. | `make compare` | [The table below](#argo-cd-and-flux-compared); `tests/compare/test_flux_behaviors.py` checks each behavior against Flux v2.10.0 in a second cluster. |

Also proven, because the task asks for a bad manifest to be refused: `test_06_bad_manifest.py` pushes `replicas: "many"`. The pre-push hook (`kubeconform`) refuses the push; with `--no-verify` the push goes through, the Kubernetes API server refuses the apply, the Application reports a failed operation, and the live Deployment keeps its last good state. `tests/unit/test_validate_script.py` shows the same gate refusing a wrong type, an unknown field and a misspelled `Application` field, offline.

### When I would turn pruning off

For anything that is hard to recreate or that holds data: a PersistentVolumeClaim, a namespace that contains objects outside Git's view, a database Secret. A deleted file should mean a deleted object only where the object can be recreated from Git alone. Turning it off is the default for production, turning it on is a decision per application. The [fleet project](../gitops-fleet-and-bad-commit) goes further and marks the Namespace itself `Prune=false`.

### Argo CD and Flux compared

What each controller does with the three behaviors, as the Argo CD runbook and `make compare` (Flux v2.10.0, in a second cluster that is deleted afterwards) check them:

| Behavior | Argo CD | Flux |
| --- | --- | --- |
| **Self-healing** | Opt-in: `syncPolicy.automated.selfHeal`, default `false`. With it off, a manual edit is reported as `OutOfSync` and left alone; with it on, the controller's watch reverts it within seconds. | No switch: the `Kustomization` applies Git again on every `interval` (10 seconds here), so a manual scale and a ConfigMap edit were reverted without any setting. A person who wants the edit to stay has to suspend the `Kustomization`. |
| **Pruning** | A separate flag: `syncPolicy.automated.prune`, default `false`. With it off, the deleted file's object stays and is listed as needing pruning, and the Application is `OutOfSync`. | A separate flag: `spec.prune`, default `false`. With it off, the object stays and Flux reports `Ready=True`: there is no out-of-sync flag to see. With it on, the object is removed. |
| **Health** | Lua health checks per resource kind, shown as `Healthy`, `Progressing` or `Degraded` beside the sync status. A Deployment whose rollout exceeded its progress deadline is `Degraded`. | kstatus, used when `spec.wait: true` (or `healthChecks`): the `Kustomization` is `Ready=False` until the applied objects are healthy, and `Ready=True` again after the revert. Sync and health are one condition, not two statuses. |

The Flux column is asserted by `tests/compare/test_flux_behaviors.py`, which `make compare` runs.

## Stretch goals

| Stretch (from the lesson) | Built? |
| --- | --- |
| Add a Helm chart as a second app and pin its version in Git. | No. [ARCHITECTURE.md](ARCHITECTURE.md#how-to-extend-it) says how: a second `Application` with `source.chart` and `targetRevision`, and the chart repository added to the project. |
| Turn on notifications so a failed sync posts a message to a chat channel you own. | No. The notifications controller is removed from the install to save memory; ARCHITECTURE.md says where to put it back. |
| Make the controller itself managed from Git, so its configuration is reconciled too. | No. The `Application` and the `AppProject` are applied by `scripts/bootstrap.sh`. The fleet project builds an app-of-apps root. |

## What is simplified for teaching

Only what the lesson scopes out, plus where this build differs from the lesson's text:

- One cluster node, one controller replica, a Git server with no authentication on a loopback-only port ([ADR 0002](docs/adr/0002-an-in-cluster-git-server.md)). Production uses a hosted repository, SSH keys or tokens, and sharded controllers.
- The poll interval is 20 seconds instead of Argo CD's three minutes plus jitter ([ADR 0005](docs/adr/0005-a-twenty-second-poll-interval.md)).
- The lesson uses `nginx:1.27`; this build uses a small nginx-unprivileged image that prints the greeting and its version, so the tests can see which image answered ([ADR 0003](docs/adr/0003-images-built-locally-and-loaded-into-the-cluster.md)).
- The lesson says a ConfigMap edit lands in a pod's environment. It does not: environment variables are read at container start. The pod template carries a `plainround.dev/config-revision` annotation that the same commit bumps, so the change rolls out as part of the commit.
- The lesson turns prune on by re-pushing the deletion; here turning prune on makes the controller prune the already-flagged object, which shows the same flag.
- The lesson's Argo CD CLI (`argocd app diff`, `argocd app history`) is replaced by `kubectl diff` and the Application's `status.history`, so nothing beyond `kubectl` is needed. The controller's configuration (`selfHeal`, `prune`) is changed with `kubectl patch application`.

## Project structure

```text
manifests/               the content of the repository the controller watches ("gitops-demo")
  apps/web/base/         Namespace, ConfigMap, Deployment, Service and their kustomization
  apps/web/overlays/local/   the image tag (the one line a rollback restores)
  clusters/local/        the Argo CD AppProject and Application for this cluster
platform/                what the cluster needs besides the app (never in the watched repository)
  argocd/                Argo CD v3.5.6 from pinned manifests, trimmed, with a 20-second poll
  git-server/            the in-cluster Git server
  flux/                  Flux v2.10.0 and its GitRepository/Kustomization, used only by make compare
docker/                  web (the demo app) and git-server images
scripts/                 up, down, reset, status, validate, seed-repo, provider.sh (k3d or kind) ...
scripts/runbook/         one script per lesson step; the tests call these
scripts/compare/         the Flux comparison
tests/support/           typed helpers: command runner, polling with an injected clock, a kubectl view of the Application
tests/unit/              helper code and manifest conformance; no cluster
tests/cluster/           one module per lesson step, run against the cluster
tests/compare/           the same three behaviors on Flux
docs/adr/                decision records
versions.env             every pinned version
```

Dependency rule: tests depend on the scripts and on `tests/support`; scripts depend on `scripts/lib.sh`; `manifests/` depends on nothing. `platform/` is never read by the watched repository.

## Troubleshooting

- **`make up` is slow or a cluster does not start:** the machine is short of CPU or memory (several clusters starting at once is enough). `scripts/cluster-up.sh` takes a machine-wide lock so that only one cluster is created at a time, and retries up to six times. k3d starts a control plane in seconds; kind's kubeadm has hard deadlines that a starved machine can miss, which is why k3d is the default.
- **`error: timed out ... waiting for the web app`:** `kubectl --context k3d-gitops-drift -n argocd get application web -o yaml` shows the controller's message.
- **Port 30418 is in use:** change the NodePort in `platform/git-server/git-server.yaml`, the port mapping in `scripts/cluster-up.sh` and `GIT_HOST_PORT` in `scripts/lib.sh`.
- **A test left the demo in a strange state:** `scripts/reset.sh` deletes the app and the namespace and starts again from the seeded commit.

## Verification status

Verified on 2026-10-27 in the session that built this repository:

- `make lint`: yamllint, shellcheck, ruff, mypy and `scripts/validate.sh` (kubectl kustomize and kubeconform against the Kubernetes and Argo CD schemas) all pass.
- `make test-offline`: the unit tests of the helpers (100 percent coverage of `tests/support`), the manifest conformance tests and the validation-gate tests pass; `scripts/validate.sh` refuses a string where a number belongs, an unknown field and a misspelled `Application` field.
- The images build, and the demo web image was run read-only and non-root and answered `/`, `/version` and `/healthz`.

Not completed in that session, and why: the Mac the repositories were built on was out of memory and swap for most of the night (swap at about 70 GB, load average above 150, Docker's virtual machine at full CPU, and its disk went read-only once), shared with a dozen other builds. kind's control plane failed to start about fifteen times in a row (kubeadm's fixed deadlines), which is why k3d is the default provider; a k3d cluster did start, but its API server then stopped answering and `make up` could not finish. The cluster/stack commands above are written to run on a quiet machine (`make up && make test && make compare`); until they have run once on yours, treat the runbook, the cluster tests and the Flux comparison as unproven. Nothing in this repository was marked passing that did not run.

## Author and license

Written by Sumit Srivastava. Released under the MIT License, see [LICENSE](LICENSE). Changes are in [CHANGELOG.md](CHANGELOG.md).
