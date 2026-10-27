# Flux

## 1. What it is

Flux is another GitOps controller. Where Argo CD is one application, Flux is a set of small controllers: the **source-controller** fetches Git, the **kustomize-controller** applies a path of it. Its objects are `GitRepository` (where) and `Kustomization` (what to apply).

## 2. Why this repository uses it

Step 6 of the lesson runs the same three behaviors (drift, prune, health) on Flux in a second cluster to show how the two tools name the same ideas. Version v2.10.0 is pinned.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `platform/flux/kustomization.yaml` | the pinned install, trimmed to two controllers |
| `platform/flux/sync.yaml` | the `GitRepository` and `Kustomization` that mirror the Argo CD Application |
| `scripts/compare/*.sh` | bring Flux up in a second cluster, run the three behaviors, delete it |
| `tests/compare/test_flux_behaviors.py` | asserts on the script's RESULT lines |

## 4. How it works underneath

- `GitRepository` (`interval: 10s`): clone `ref.branch: main` every 10 seconds into an artifact.
- `Kustomization` (`flux`'s kind, not Kustomize's): build `path: ./apps/web/overlays/local` of that source and apply it every `interval`. Because it applies on every interval, **drift is reverted with no setting**; Argo CD needs `selfHeal`.
- `prune: false` is the default; set it to `true` to delete what left Git. Flux raises no "out of sync" flag when prune is off.
- `wait: true` makes `Ready` depend on the health of every applied object (using the kstatus library), so a Deployment that never becomes ready makes `Ready=False`. `timeout: 60s` bounds that wait.

## 5. Walkthrough of this repository's use

```yaml
kind: GitRepository
spec: { interval: 10s, url: http://git-server.git-server.svc.cluster.local/gitops-demo.git, ref: { branch: main } }
---
kind: Kustomization
spec:
  interval: 10s
  sourceRef: { kind: GitRepository, name: gitops-demo }
  path: ./apps/web/overlays/local
  prune: false
  wait: true
  timeout: 60s
```
Each key is explained above. Together they say: "every 10 seconds fetch `main`, build the overlay, apply it, report Ready only when everything is healthy".

`platform/flux/kustomization.yaml` pulls `https://github.com/fluxcd/flux2/releases/download/v2.10.0/install.yaml` and deletes four controllers (Helm, notification, image-reflector, image-automation) with `$patch: delete`, leaving source and kustomize.

### `scripts/compare/`
* `env.sh` sets `CLUSTER_NAME=gitops-drift-flux`, `GIT_HOST_PORT=30419` and a different working folder, then `lib.sh` is sourced, so every helper acts on the **second** cluster. The two clusters never share an object.
* `flux-up.sh` creates the cluster, builds and imports images, installs the Git server, seeds the repository, installs Flux (`kc apply --server-side --force-conflicts -k platform/flux`), waits for the two controllers, applies `sync.yaml` and waits for `Ready=True`.
* `flux-behaviors.sh` defines readers such as `ready() { kustomization_field '{.status.conditions[?(@.type=="Ready")].status}'; }`, then performs: drift (scale to 5 and patch the greeting; wait for the revert), prune off (delete the file; sleep 40; the ConfigMap is still there), prune on (`patch kustomization web ... {"spec":{"prune":true}}`; the ConfigMap goes), then a bad commit (`Ready=False`) and `git revert` (`Ready=True`). Each outcome prints one `RESULT ...` line.
* `flux-down.sh` deletes the cluster. `make compare` guarantees it runs even if the tests fail.

<!-- full-walkthrough:begin -->
### 5.A Full walkthrough: every Flux file

#### `platform/flux/sync.yaml`

```yaml
---
# The same repository and path the Argo CD Application watches, with Flux's equivalents of its settings.
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: gitops-demo
  namespace: flux-system
spec:
  interval: 10s
  url: http://git-server.git-server.svc.cluster.local/gitops-demo.git
  ref:
    branch: main
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: web
  namespace: flux-system
spec:
  interval: 10s
  sourceRef:
    kind: GitRepository
    name: gitops-demo
  path: ./apps/web/overlays/local
  # prune is off by default in Flux too; the comparison turns it on for the second half of the test.
  prune: false
  # wait: true makes Ready depend on the health of every applied object (kstatus), not just on the apply.
  wait: true
  timeout: 60s
```

- Two objects. The first is a **GitRepository**: it tells Flux's source controller what to fetch. `interval: 10s` asks every ten seconds; `url` is the in-cluster Git server; `ref.branch: main` the branch to follow.
- The second is a **Kustomization** (Flux's kind: an object in the cluster, not a file). `interval: 10s` re-applies every ten seconds; this is the reason Flux needs no self-heal switch. `sourceRef` points at the GitRepository above. `path: ./apps/web/overlays/local` is the folder to build and apply. `prune: false` leaves objects that left Git alone (the default). `wait: true` makes the Kustomization report "Ready" only when the applied objects are healthy; `timeout: 60s` limits that wait.

#### `platform/flux/kustomization.yaml`

```yaml
---
# Flux at the version in versions.env (the tag below must match FLUX_VERSION), trimmed to the two controllers
# a plain Git-to-cluster sync needs: no Helm, notification or image-automation controllers.
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - https://github.com/fluxcd/flux2/releases/download/v2.10.0/install.yaml
patches:
  - target: { kind: Deployment, name: helm-controller }
    patch: |-
      $patch: delete
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: helm-controller
  - target: { kind: Deployment, name: notification-controller }
    patch: |-
      $patch: delete
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: notification-controller
  - target: { kind: Deployment, name: image-reflector-controller }
    patch: |-
      $patch: delete
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: image-reflector-controller
  - target: { kind: Deployment, name: image-automation-controller }
    patch: |-
      $patch: delete
      apiVersion: apps/v1
      kind: Deployment
      metadata:
        name: image-automation-controller
```

- (See the Kustomize note.) The install file of Flux at `v2.10.0`, with four unneeded controllers deleted.
<!-- full-walkthrough:end -->

## 6. Try it yourself

1. `make compare` (needs a quiet machine; about 10 minutes) : prints four `RESULT` lines.
2. `kubectl --context k3d-gitops-drift-flux -n flux-system get gitrepository,kustomization` while it runs : both `Ready`.
3. `kubectl kustomize platform/flux | grep -c 'kind: Deployment'` : 2 (source and kustomize controllers).
4. `grep -n 'interval' platform/flux/sync.yaml` : both are 10s.
5. Compare the RESULT lines with the Argo CD runbook output: Argo CD flags `OutOfSync` for pending prune; Flux does not.

## 7. Mistakes people make

- Confusing Flux's `Kustomization` with Kustomize's file of the same name. They differ: Flux's is a cluster object that points at a path; Kustomize's is a file in that path.
- Expecting drift to need a setting: in Flux it does not.
- Forgetting `wait: true`, then reading `Ready=True` for an app whose Pods never start.

## 8. Check yourself

1. Which Flux controller fetches Git?
   *Answer:* The source-controller.
2. Which object tells Flux what to apply?
   *Answer:* A `Kustomization` in `kustomize.toolkit.fluxcd.io`.
3. How does Flux revert drift?
   *Answer:* It re-applies the desired state on every interval, with no extra setting.
4. What does `wait: true` change?
   *Answer:* Ready then depends on the health of every applied object.
5. Why is there a second cluster?
   *Answer:* So the two controllers never touch each other's objects.

## 9. Further reading

- Flux documentation: <https://fluxcd.io/flux/> (v2.10; the Kustomization API is `kustomize.toolkit.fluxcd.io/v1`). Not re-checked against the v2.10 docs in this session; the API versions were taken from the install file used.
