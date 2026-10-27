# Kustomize

## 1. What it is

Kustomize builds Kubernetes YAML from other YAML without templates. A **base** holds the plain manifests; an **overlay** points at a base and changes a few things (an image tag, a name prefix, a patch). `kubectl kustomize <dir>` prints the result and `kubectl apply -k <dir>` applies it. It is built into `kubectl`.

## 2. Why this repository uses it

Argo CD does not apply raw files; it runs Kustomize on the path in Git. The overlay lets the lesson change the **image tag** in one line (`newTag`), and the same build is used by `make lint` and by `kubectl diff`.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `manifests/apps/web/base/kustomization.yaml` | lists the four base files |
| `manifests/apps/web/overlays/local/kustomization.yaml` | includes the base and sets the image tag |
| `platform/argocd/kustomization.yaml` | pulls Argo CD's remote install file and trims it with patches |
| `platform/flux/kustomization.yaml` | the same for Flux |
| `platform/git-server/kustomization.yaml` | lists the Git server file |
| `scripts/validate.sh, scripts/diff.sh` | build with `kubectl kustomize` before checking or comparing |

## 4. How it works underneath

- A directory becomes a Kustomize unit when it holds a file named `kustomization.yaml`. Its `resources:` list names files or other directories to include.
- `images:` rewrites an image's name or tag everywhere it appears, so an overlay changes only one line to ship a new version.
- `patches:` apply a small YAML edit to a matching object, including `$patch: delete` to remove one.
- `namespace:` sets the namespace of every object it builds.
- The output is ordinary YAML. Nothing runs inside the cluster; the cluster (or Argo CD, which runs the same build) just receives the result.

## 5. Walkthrough of this repository's use

### The base and the overlay
```yaml
# base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources: [namespace.yaml, configmap.yaml, deployment.yaml, service.yaml]
```
```yaml
# overlays/local/kustomization.yaml
resources:
  - ../../base
images:
  - name: plainround/web
    newTag: 1.0.0
```
The overlay includes the base directory and rewrites the tag of the image named `plainround/web`. The base file says `image: plainround/web:1.0.0` as well; Kustomize replaces the tag everywhere that image appears. The "bad commit" of the lesson changes `newTag: 1.0.0` to `1.1.0` with one `perl` substitution.

### Trimming Argo CD
```yaml
namespace: argocd
resources:
  - namespace.yaml
  - https://raw.githubusercontent.com/argoproj/argo-cd/v3.5.6/manifests/install.yaml
patches:
  - path: controller-settings.yaml
  - target: { kind: Deployment, name: argocd-dex-server }
    patch: |-
      $patch: delete
      ...
```
* A remote URL in `resources` is downloaded and built. The tag `v3.5.6` pins it; `install-argocd.sh` checks that the tag matches `ARGOCD_VERSION`.
* `namespace: argocd` puts every object in that namespace.
* `path: controller-settings.yaml` is a **strategic merge patch**: it contains the `argocd-cm` ConfigMap with two keys; Kustomize merges them into the real one. `timeout.reconciliation: 20s` makes Argo CD poll Git every 20 seconds; `timeout.reconciliation.jitter: 0s` removes the random extra delay.
* `target: {...}` with `$patch: delete` removes whole objects: Dex (single sign-on) and the notifications controller, which a laptop lesson does not need. The `Flux` file does the same for four controllers.

### In the scripts
`kubectl kustomize apps/web/overlays/local | kubeconform ... -` (validation) and `kubectl kustomize ... | kc diff -f -` (what differs from the cluster). `kubectl apply --server-side -k platform/argocd` builds and applies in one step.

<!-- full-walkthrough:begin -->
### 5.A Full walkthrough: every Kustomize file

**Words you need first.** **Kustomize** builds the final Kubernetes YAML from simple pieces, without templates. A folder becomes a Kustomize unit when it contains a file named exactly `kustomization.yaml`. Every such file starts with `apiVersion` and `kind: Kustomization` (this is **Kustomize's** Kustomization, a file; it is not the same as Flux's `Kustomization`, an object in the cluster).

#### `manifests/apps/web/base/kustomization.yaml`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - namespace.yaml
  - configmap.yaml
  - deployment.yaml
  - service.yaml
```

- `resources:` lists the files (or folders) to include. The four files are the namespace, the ConfigMap, the Deployment and the Service. A file not listed here is ignored, which is why the runbook removes the ConfigMap's file **and** its line from this list when it deletes it from Git.

#### `manifests/apps/web/overlays/local/kustomization.yaml`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../../base
images:
  - name: plainround/web
    newTag: 1.0.0
```

- An **overlay** includes a base and changes small things. `resources: - ../../base` includes the folder two levels up. `images:` rewrites the tag of the image named `plainround/web` everywhere it appears: `newTag: 1.0.0`. The bad-commit step changes this one line to `1.1.0`.

#### `platform/git-server/kustomization.yaml`

```yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - git-server.yaml
```

- Lists the single file with all the Git server objects.

#### `platform/argocd/kustomization.yaml` and `platform/flux/kustomization.yaml`

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

- `namespace: argocd` puts every built object in that namespace.
- Under `resources`, a plain address starting with `https://` is downloaded and built; here the official install file of Argo CD at version `v3.5.6` (the version is in the address, so it cannot change silently).
- `patches:` changes parts of the downloaded objects. `path: controller-settings.yaml` merges that file into the object with the same kind and name (`argocd-cm`). The two others use `target:` to pick an object (`kind: Deployment`, `name: argocd-dex-server`) and a `patch: |-` block (a block of text, written under a `|-`) whose content is `$patch: delete` plus the object's identity: it tells Kustomize to **remove** that object from the result. The same is done for the notifications controller.

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

- The same method for Flux at version `v2.10.0`: download the install file and delete four controllers the lesson does not use (Helm, notifications, image reflector and image automation), leaving the two it needs (source and kustomize controllers).
<!-- full-walkthrough:end -->

## 6. Try it yourself

1. `kubectl kustomize manifests/apps/web/overlays/local | grep image:` : `image: plainround/web:1.0.0`.
2. Edit `newTag` to `1.1.0` in a copy, rebuild : the Deployment shows `1.1.0`.
3. `kubectl kustomize platform/git-server | head` : the Git server objects.
4. `kubectl kustomize platform/argocd | grep -c 'kind: Deployment'` : Dex and notifications are gone.
5. `kubectl kustomize platform/argocd | grep -A3 'timeout.reconciliation'` : the 20s setting merged into `argocd-cm`.

## 7. Mistakes people make

- Editing the built output instead of the source files.
- Forgetting to list a new file under `resources:`: it is silently ignored. (This repository's runbook deletes a ConfigMap by removing the file *and* its `resources` line.)
- Using a remote base without a pinned version, so the content moves.

## 8. Check yourself

1. What makes a directory a Kustomize unit?
   *Answer:* A `kustomization.yaml` file in it.
2. What does an overlay do?
   *Answer:* It includes a base and changes small parts of it.
3. How does `images:` help a release?
   *Answer:* One line changes the tag of every matching container image.
4. What command prints the built result?
   *Answer:* `kubectl kustomize <directory>`.
5. What happens to a file not listed in `resources:`?
   *Answer:* It is ignored.

## 9. Further reading

- Kustomize: <https://kubectl.docs.kubernetes.io/references/kustomize/> and <https://kubernetes.io/docs/tasks/manage-kubernetes-objects/kustomization/>. The version is the one built into your `kubectl` (`kubectl version --client`).
