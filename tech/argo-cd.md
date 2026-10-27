# Argo CD

## 1. What it is

Argo CD is a Kubernetes controller that watches a Git repository and keeps the cluster equal to it. You describe *where* the desired state is (an `Application` object), and Argo CD builds the manifests, compares them with the live objects, and applies the difference. It also reports whether the live state is **Synced** or **OutOfSync** and whether it is **Healthy**.

## 2. Why this repository uses it

It is the controller the lesson teaches: automated sync, self-heal, pruning, health, and rollback by `git revert`. Version v3.5.6 is pinned.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `platform/argocd/` | the install (remote `install.yaml` at v3.5.6, trimmed) and the 20 s poll setting |
| `manifests/clusters/local/application.yaml` | the `Application` that points at the Git server |
| `manifests/clusters/local/project.yaml` | the `AppProject` that limits it |
| `scripts/install-argocd.sh, bootstrap.sh` | install and the one hand-applied step |
| `scripts/lib.sh (`app_field`, `refresh_app`, `set_sync_policy`)` | reading and changing the Application |
| `tests/support/kube.py (`application()`)` | the typed view of the Application used by tests |

## 4. How it works underneath

- Argo CD runs several Pods in the `argocd` namespace: the **repo-server** (clones Git and renders Kustomize), the **application-controller** (a StatefulSet that compares and syncs), the **server** (UI/API), **redis** (cache) and the **applicationset-controller** (unused here).
- Every poll (20 s here) the controller asks the repo-server for the manifests at the head of `main`, compares them with the live objects, and sets `status.sync.status` (`Synced` or `OutOfSync`) and `status.health.status` (`Healthy`, `Progressing`, `Degraded`, `Missing`).
- `syncPolicy.automated` lets it apply without a human. Two switches: **selfHeal** (also revert changes made directly in the cluster) and **prune** (delete objects that left Git). With both off Argo CD only *reports*.
- Argo CD watches live objects as well, so a hand change is noticed within seconds; Git is polled at the interval.
- Each sync is recorded in `status.history` with the commit; `status.operationState.phase` is `Succeeded`, `Failed` or `Error`.
- **Rollback in GitOps** means a new commit (`git revert`), not a command to the cluster.

## 5. Walkthrough of this repository's use

### Installing it
`platform/argocd/kustomization.yaml` (see the Kustomize note) pulls the official install file. `install-argocd.sh`:

```bash
pinned="$(grep -oE 'argo-cd/v[0-9.]+/' ... | head -1 | tr -d '/' | sed 's/argo-cd//')"
[ "${pinned}" = "${ARGOCD_VERSION}" ] || die "..."
kc apply --server-side --force-conflicts -k "${ROOT}/platform/argocd" >/dev/null
```
It checks the tag in the Kustomize file against `versions.env` (two places must not disagree), then applies **server-side** because Argo CD's CRDs are larger than the annotation `kubectl apply` would add. `--force-conflicts` lets this apply take over fields. Then `kc -n argocd rollout status ...` waits for the controller StatefulSet and four Deployments.

### The Application
```yaml
spec:
  project: gitops-demo
  source: { repoURL: http://git-server.git-server.svc.cluster.local/gitops-demo.git, targetRevision: main, path: apps/web/overlays/local }
  destination: { server: https://kubernetes.default.svc, namespace: web }
  syncPolicy: { automated: { prune: false, selfHeal: false } }
```
`https://kubernetes.default.svc` means "the cluster Argo CD runs in". `path` is the Kustomize overlay. The starting state has both switches off; the runbook turns them on one at a time with `set_sync_policy`.

### The three behaviors in the runbook
* **Drift**, self-heal off: `kubectl scale deploy web --replicas=5` and a patched ConfigMap; `status.sync.status` becomes `OutOfSync` and nothing is reverted. With self-heal **on**, both objects return to Git's values with no command.
* **Prune**: the ConfigMap's file is removed in Git. With prune off the object stays and the Application lists it under `status.resources[?(@.requiresPruning==true)]`; with prune on it is deleted. `git revert` brings it back.
* **Rollback**: the bad commit raises `1.1.0` with a failing readiness probe. `maxUnavailable: 0` keeps the old Pods; Argo CD reports `Degraded` after `progressDeadlineSeconds`. `git revert` of that commit restores `1.0.0` and `Healthy`.

### Reading state from scripts and tests
`app_field '{.status.sync.status}'` is a JSONPath over the Application. `tests/support/kube.py` turns the same fields into a frozen `ApplicationState` dataclass (sync, health, revision, operation phase, message, history, self-heal, prune).

### The settings patched in
`timeout.reconciliation: 20s` in `argocd-cm`: how often the repo-server re-reads Git (default 3 minutes plus up to 1 minute of jitter, which is why the lesson sets it).

<!-- full-walkthrough:begin -->
### 5.A Full walkthrough: every Argo CD file

**Words you need first.** A **custom resource** is a kind of Kubernetes object that is not built in; a program adds it. Argo CD adds `Application` and `AppProject`. A **namespace** is a named folder of objects. A **ConfigMap** holds named settings. **Reconciliation** means a program keeps comparing the wanted state with the real state and fixing the difference.

#### `platform/argocd/namespace.yaml`

```yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: argocd
```

- Creates the namespace `argocd`, where all of Argo CD's parts run. It has no label because Argo CD's own pods are not restricted.

#### `platform/argocd/controller-settings.yaml`

```yaml
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
data:
  # Poll Git every 20 seconds with no random delay (the default is three minutes plus up to a minute).
  timeout.reconciliation: 20s
  timeout.reconciliation.jitter: 0s
```

- A ConfigMap named `argocd-cm`: Argo CD reads its settings from the object with exactly this name. It has no namespace here because the Kustomize file below sets the namespace of everything to `argocd`.
- `timeout.reconciliation: 20s`: how often Argo CD asks Git whether anything changed. The default is three minutes, too slow to watch in a lesson. `timeout.reconciliation.jitter: 0s` removes the random extra delay Argo CD normally adds to spread load (the default is up to a minute).
- Kustomize merges this into the real `argocd-cm` that comes with Argo CD's install file. See the Kustomize note.

#### `platform/argocd/kustomization.yaml`

```yaml
---
# Argo CD at the version in versions.env (the tag below must match ARGOCD_VERSION), trimmed for a laptop:
# no Dex (no single sign-on), no notifications, and a short poll interval so the runbook does not wait
# three minutes for every change.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: argocd
resources:
  - namespace.yaml
  - https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.6/manifests/install.yaml
patches:
  - path: controller-settings.yaml
  - target: { kind: Deployment, name: argocd-dex-server }
    patch: |-
      $patch: delete
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: argocd-dex-server
  - target: { kind: Deployment, name: argocd-notifications-controller }
    patch: |-
      $patch: delete
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: argocd-notifications-controller
```

- (See the Kustomize note for the keys.) What matters here: the install file is downloaded from the exact release `v3.5.6` of Argo CD; the namespace of every object is set to `argocd`; the file `controller-settings.yaml` is merged in as a patch; and two parts the lesson does not need, Dex (single sign-on) and the notifications controller, are deleted with `$patch: delete`.

#### `manifests/clusters/local/project.yaml`

```yaml
---
# The project limits what the controller may do for this app: one repository, one namespace, one
# cluster-scoped kind (the Namespace itself).
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: gitops-demo
  namespace: argocd
spec:
  description: The web demo app and nothing else
  sourceRepos:
    - http://git-server.git-server.svc.cluster.local/gitops-demo.git
  destinations:
    - server: https://kubernetes.default.svc
      namespace: web
  clusterResourceWhitelist:
    - group: ""
      kind: Namespace
```

- An **AppProject** limits what the Applications in it may do. This is a safety fence.
- `sourceRepos`: the only Git address it may read from.
- `destinations`: the only place it may deploy to: this cluster (`https://kubernetes.default.svc` is the cluster Argo CD itself runs in) and only the namespace `web`.
- `clusterResourceWhitelist`: the only cluster-wide (not namespaced) kind it may create: a `Namespace` (`group: ""` is the core API group). That is needed because the repository contains the `web` namespace itself.

#### `manifests/clusters/local/application.yaml`

```yaml
---
# The starting state of lesson step 1: automated sync with self-heal and prune both off. The runbook
# turns them on one at a time (scripts/runbook).
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: web
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: gitops-demo
  source:
    repoURL: http://git-server.git-server.svc.cluster.local/gitops-demo.git
    targetRevision: main
    path: apps/web/overlays/local
  destination:
    server: https://kubernetes.default.svc
    namespace: web
  syncPolicy:
    automated:
      prune: false
      selfHeal: false
```

- An **Application** says "keep this part of Git deployed to this place".
- `metadata.finalizers`: a finalizer is a note that makes Kubernetes run a cleanup before it deletes the object. This one makes deleting the Application also delete everything it deployed.
- `spec.project: gitops-demo`: the fence above.
- `source`: `repoURL` the Git server inside the cluster; `targetRevision: main` the branch to follow; `path: apps/web/overlays/local` the folder to build and deploy.
- `destination`: `server` is the cluster; `namespace: web` where the objects go.
- `syncPolicy.automated`: Argo CD applies changes by itself. `prune: false` and `selfHeal: false` are the lesson's starting point: Argo CD only deploys new commits. The runbook turns the two switches on one at a time. (*Prune* = delete objects that left Git; *self-heal* = undo changes made by hand.)
<!-- full-walkthrough:end -->

## 6. Try it yourself

1. `kubectl --context k3d-gitops-drift -n argocd get application web` : columns `SYNC STATUS` and `HEALTH STATUS`.
2. `scripts/status.sh` : the Application, its sync policy and the Deployment on one screen.
3. `kubectl --context k3d-gitops-drift -n argocd get application web -o jsonpath='{.status.history[*].revision}'` : the commits it has deployed.
4. Run `scripts/runbook/03-drift.sh off` : the app turns `OutOfSync`; `scripts/diff.sh` shows the lines that differ.
5. `kubectl --context k3d-gitops-drift -n argocd get cm argocd-cm -o yaml | grep -A2 timeout` : the poll interval.

## 7. Mistakes people make

- Thinking Argo CD changes Git. It only reads Git.
- Turning on prune and self-heal without understanding that a manual `kubectl edit` is now reverted.
- Expecting a ConfigMap edit to restart Pods; the config-revision annotation handles that here.
- Rolling back with `kubectl rollout undo`: it works for a moment and is reverted by the next sync, because Git still holds the bad version.

## 8. Check yourself

1. What are the two statuses Argo CD reports?
   *Answer:* Sync (Synced or OutOfSync) and health (Healthy, Progressing, Degraded, Missing).
2. What does self-heal do?
   *Answer:* Reverts changes made directly in the cluster.
3. What does prune do?
   *Answer:* Deletes live objects that are no longer in Git.
4. How do you roll back in GitOps?
   *Answer:* `git revert` the commit and push; the controller applies the previous state.
5. Why is the poll interval set to 20 s here?
   *Answer:* The default is minutes; the runbook would wait too long for each change.

## 9. Further reading

- Argo CD v3.5 documentation: <https://argo-cd.readthedocs.io/en/stable/> (automated sync: operator-manual under 'Automated Sync Policy'; configuration key `timeout.reconciliation` under 'argocd-cm'). Not re-checked against the v3.5 docs site in this session (the source was the install manifest and live behavior).
