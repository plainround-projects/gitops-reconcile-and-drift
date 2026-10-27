# k3d and kind (local clusters)

## 1. What it is

k3d and kind each create a whole Kubernetes cluster inside Docker containers on your laptop, so you can test cluster software without a cloud account. **k3d** runs **k3s**, a small Kubernetes distribution; **kind** runs the standard `kubeadm` way. This repository uses k3d by default and can use kind with `CLUSTER_PROVIDER=kind`.

## 2. Why this repository uses it

A local cluster with no cloud account. k3d starts quickly and needs little memory, which matters on a shared laptop; kind is available for people who prefer it and is what CI uses.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `scripts/provider.sh` | all k3d and kind calls behind `provider_*` functions |
| `scripts/cluster-up.sh, down.sh` | create and delete the cluster |
| `versions.env` | `K3S_IMAGE=rancher/k3s:v1.35.5-k3s1` and the kind node image with its digest |
| `scripts/compare/` | a second cluster `gitops-drift-flux` |

## 4. How it works underneath

- The "node" is one Docker container (`k3d-<name>-server-0`) that runs the control plane and the workloads. A second container (`...-serverlb`) is a small load balancer that publishes ports to the host.
- `k3d cluster create <name>` pulls the node image, starts the container, waits for the API server and writes a kubeconfig context named `k3d-<name>`. kind's context is `kind-<name>`.
- A port written `-p "127.0.0.1:30418:30418@loadbalancer"` publishes the node port on your loopback address only, so nothing outside your machine can reach it.
- Images built with `docker build` live in your Docker, not in the node. `k3d image import` copies them in. Pods then use `imagePullPolicy: IfNotPresent` so they never try to pull them from the internet.
- `k3d cluster delete <name>` removes the containers, network and kubeconfig entry.
- k3s disables bundled extras on request (`--disable=traefik` and others) to save memory.

## 5. Walkthrough of this repository's use

For k3d, `provider_create` builds:

```bash
args=(cluster create "${name}" --servers 1 --agents 0 --image "${K3S_IMAGE}" --wait --timeout 1800s
  --k3s-arg "--disable=traefik@server:0" --k3s-arg "--disable=servicelb@server:0"
  --k3s-arg "--disable=metrics-server@server:0")
args+=(-p "127.0.0.1:${mapping%:*}:${mapping#*:}@loadbalancer")
```
* `--servers 1 --agents 0`: one node that is both control plane and worker.
* `--image` pins the k3s version. `--wait --timeout 1800s` blocks until ready (a long timeout because the laptop may be slow).
* `--k3s-arg "--disable=X@server:0"` turns off k3s's bundled ingress (traefik), service load balancer and metrics server to save memory; this lesson needs none.
* `${mapping%:*}` and `${mapping#*:}` are Bash string cuts: for `30418:30418` they give the part before and after the colon. The result `127.0.0.1:30418:30418@loadbalancer` publishes node port 30418 on the host loopback only.

For kind, `provider_create` writes a configuration file: `kubeadmConfigPatches` raise kubeadm's waiting limits (a loaded laptop missed the defaults) and `etcd.local.dataDir: /tmp/etcd` moves etcd's data to memory-backed storage, and `extraPortMappings` publish the same port. `kind create cluster --name ... --image <image@digest> --config ... --wait 600s`.

`provider_load_images` checks each image on the node with `docker exec <node> crictl inspecti <image>` and imports only missing ones with `k3d image import --cluster ...` (or `kind load docker-image`). `provider_context` returns `k3d-<name>` or `kind-<name>`. `down.sh` is `provider_delete`.

## 6. Try it yourself

1. `k3d version` : k3d and k3s versions.
2. `k3d cluster list` : `gitops-drift  1/1  0/0  true` while up.
3. `docker ps --filter name=k3d-gitops-drift` : the node and the load balancer containers.
4. `docker exec k3d-gitops-drift-server-0 crictl images | grep plainround` : the imported images.
5. `CLUSTER_PROVIDER=kind scripts/cluster-up.sh` : the same cluster with kind (needs `kind` installed).

## 7. Mistakes people make

- Creating several clusters at once on a small machine: the control planes miss their start-up deadlines. This repository takes a machine-wide lock first.
- Forgetting to delete the cluster afterwards; it keeps using memory.
- Expecting `docker build` images to be visible in the cluster without importing them.

## 8. Check yourself

1. What is the cluster's node here?
   *Answer:* A Docker container.
2. Why bind a published port to `127.0.0.1`?
   *Answer:* So only the local machine can reach it.
3. How does a locally built image reach a pod?
   *Answer:* It is imported into the node, and the pod uses `IfNotPresent`.
4. How do k3d and kind differ?
   *Answer:* k3d runs k3s (small, quick); kind runs standard kubeadm Kubernetes.
5. What removes a cluster completely?
   *Answer:* `k3d cluster delete <name>` (or `kind delete cluster --name <name>`).

## 9. Further reading

- k3d: <https://k3d.io/> (5.9.0 used). k3s: <https://docs.k3s.io/>. kind: <https://kind.sigs.k8s.io/>.
