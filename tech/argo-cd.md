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
