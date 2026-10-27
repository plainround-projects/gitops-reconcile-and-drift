# kubectl

## 1. What it is

`kubectl` is the command-line program that sends requests to a Kubernetes API server: read objects, create them, change them, delete them, run a command inside a Pod. Almost every script in this repository calls it.

## 2. Why this repository uses it

Every script and test talks to the cluster through kubectl, always with `--context`.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `scripts/lib.sh (`kc`)` | the one wrapper |
| `scripts/*.sh, scripts/runbook/*.sh` | apply, rollout status, patch, scale, annotate, diff, exec, wait, jsonpath reads |
| `tests/support/kube.py` | the same calls from Python |
| `scripts/validate.sh, diff.sh` | `kubectl kustomize` |

## 4. How it works underneath

- `kubectl` reads a **kubeconfig** file (`~/.kube/config`) that lists clusters, users and **contexts** (a pairing of a cluster and a user). `--context <name>` picks one.
- `get`, `describe`, `apply`, `delete`, `patch`, `scale`, `exec`, `rollout status`, `wait` and `diff` are the verbs used here.
- `-n <namespace>` selects a namespace. `-o json` or `-o jsonpath='{...}'` prints parts of an object so a script can read one field.
- `apply` sends the file and lets the server merge it. **Server-side apply** (`--server-side`) lets the API server track which tool owns which field, and avoids the size limit of the client-side annotation.
- `kubectl diff -f -` shows what an apply would change; its exit code is 1 when there is a difference.

## 5. Walkthrough of this repository's use

```bash
kc() { kubectl --context "${KUBE_CONTEXT}" "$@"; }
```
Everything uses this function.

Commands used and what they do:
* `kc apply --server-side -k platform/git-server` : build with Kustomize (`-k`) and apply, with the API server doing the merge.
* `kc -n git-server rollout status deployment/git-server --timeout=240s` : wait until the new ReplicaSet is fully available.
* `kc wait --for=condition=Ready node --all --timeout=180s` : wait for a condition on objects.
* `kc -n argocd annotate application web argocd.argoproj.io/refresh=normal --overwrite` : set an annotation; Argo CD treats it as "look at Git now".
* `kc -n argocd patch application web --type merge -p '{...}'` : a JSON merge patch that changes one setting.
* `kc -n web scale deploy web --replicas=5` and `patch configmap web-config --type merge -p '{"data":{"GREETING":"hacked"}}'` : the manual drift.
* `kc -n web exec deploy/web -- printenv GREETING` : run a command in a Pod of the Deployment.
* `kubectl kustomize <dir> | kc diff -f -` : compare Git's rendering with the live cluster (`|| true` because diff exits 1 when they differ).
* `-o 'jsonpath={range .status.history[*]}  {.id}  {.revision}{"\n"}{end}'` : loop over a list and print two fields per line.
* In Python, `Kube.get_through_service` runs `kubectl get --raw /api/v1/namespaces/web/services/web:80/proxy/` to GET a page through the API server.

## 6. Try it yourself

1. `kubectl config get-contexts` : includes `k3d-gitops-drift` while the cluster is up.
2. `kubectl --context k3d-gitops-drift get pods -A` : every Pod in the cluster.
3. `kubectl --context k3d-gitops-drift -n web get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}'` : the image.
4. `scripts/diff.sh` : empty when Git and the cluster agree.
5. `kubectl --context k3d-gitops-drift api-resources | grep argoproj` : the custom kinds Argo CD added.

## 7. Mistakes people make

- Running against the wrong cluster because the current context was something else. All scripts here pass `--context` explicitly.
- Reading output with `grep` instead of `-o jsonpath`, which breaks when the layout changes.
- Using `--force` or `delete` as a first step; a reconciling controller will undo them anyway.

## 8. Check yourself

1. What is a context?
   *Answer:* A kubeconfig entry that pairs a cluster with a user.
2. How do you print one field of an object?
   *Answer:* `kubectl get <kind> <name> -o jsonpath='{.path.to.field}'`.
3. What does `--server-side` change about `apply`?
   *Answer:* The API server merges and records field ownership, instead of the client.
4. Why does every script pass `--context`?
   *Answer:* So it can never act on whichever cluster happens to be current.
5. What does `kubectl diff` return when there is a difference?
   *Answer:* Exit code 1, with the differences printed.

## 9. Further reading

- kubectl reference: <https://kubernetes.io/docs/reference/kubectl/> (client 1.35).
