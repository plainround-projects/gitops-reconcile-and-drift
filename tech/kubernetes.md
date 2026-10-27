# Kubernetes

## 1. What it is

Kubernetes is a system that runs containers across one or more machines and keeps them running as you described. You do not tell it *what to do*; you give it **objects** that say *what should exist* (for example "two copies of this container"), and its **controllers** keep comparing that wish with reality and fix the difference. This idea is called **declarative** configuration and the comparing loop is called **reconciliation**.

## 2. Why this repository uses it

Kubernetes is both the thing being managed (the demo app runs on it) and the foundation of the controller (Argo CD itself is Kubernetes objects and custom resources). The lesson's three behaviors are Kubernetes reconciliation loops watching each other: Kubernetes reconciles Pods to the Deployment, Argo CD reconciles the Deployment to Git.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `manifests/apps/web/base/{namespace,configmap,deployment,service}.yaml` | the demo application |
| `manifests/clusters/local/{project,application}.yaml` | Argo CD's custom resources |
| `platform/git-server/git-server.yaml` | Namespace, Deployment and two Services for the Git server |
| `platform/argocd/` | Argo CD's own Deployments, a StatefulSet and its settings |

## 4. How it works underneath

- The **API server** is the front door. Every `kubectl` command and every controller talks to it over HTTPS and stores objects in a database called **etcd**.
- The main objects used here: **Namespace** (a named folder of objects), **Pod** (one or more containers that run together), **Deployment** (keeps N identical Pods and replaces them in a rolling update), **ReplicaSet** (created by a Deployment, one per version of the Pod template), **Service** (a stable name and address in front of Pods chosen by labels), **ConfigMap** (named key-value settings).
- A **label** is a key-value tag on an object. A **selector** picks objects by label; a Service finds its Pods this way.
- **Probes** let Kubernetes ask a container whether it is alive (liveness) and ready for traffic (readiness). A Pod that is not ready receives no Service traffic.
- A **rolling update** starts new Pods and stops old ones in steps. With `maxUnavailable: 0` an old Pod stays until a new one is ready.
- **Custom resources** (CRDs) extend the API with new kinds, such as Argo CD's `Application`. The API server validates objects against their schema and refuses wrong types.
- A **node** is a machine that runs Pods. Here the cluster has one node, itself a container.

## 5. Walkthrough of this repository's use

### The Namespace
```yaml
kind: Namespace
metadata:
  name: web
  labels:
    pod-security.kubernetes.io/enforce: restricted
```
The label turns on the **restricted Pod Security Standard** for this namespace: Kubernetes itself refuses Pods that run as root, add capabilities or lack a seccomp profile. The Deployment is written to pass it.

### The ConfigMap
`data: { GREETING: hello }`. One key. Changing it is the lesson's first change.

### The Deployment (`manifests/apps/web/base/deployment.yaml`)
* `replicas: 2`: two Pods.
* `progressDeadlineSeconds: 60`: if a rollout makes no progress for a minute, Kubernetes marks the Deployment `ProgressDeadlineExceeded`, and Argo CD reports `Degraded`. The default is ten minutes, too slow for a lesson.
* `strategy.rollingUpdate: maxUnavailable: 0, maxSurge: 1`: start one extra new Pod, wait until it is ready, then stop an old one. This is why, in the bad-commit step, the old Pods keep serving while the new Pod never becomes ready.
* `selector.matchLabels: app: web` and `template.metadata.labels: app: web`: the Deployment owns Pods with this label. The two must match.
* `annotations: plainround.dev/config-revision: "1"`: environment variables are read once, so a ConfigMap change does not restart Pods. Changing this annotation changes the Pod template, which triggers a rolling update; the runbook bumps it in the same commit as the greeting.
* `automountServiceAccountToken: false`: the app does not need to call the API, so it gets no token.
* `securityContext` (Pod): `runAsNonRoot: true`, `fsGroup: 101` (volume files are owned by group 101, nginx's group, so `emptyDir` is writable), `seccompProfile: RuntimeDefault` (the container runtime's default system-call filter).
* `envFrom: configMapRef: name: web-config`: every key of the ConfigMap becomes an environment variable.
* `readinessProbe` and `livenessProbe` call `GET /healthz` on port `http` (the named port). Readiness checks every 3 s and fails after 3 misses; liveness every 10 s. The bad commit changes only the readiness path to a missing one.
* `resources.requests` (what the scheduler reserves: 25m CPU, 32Mi) and `limits` (hard cap: 100m CPU, 64Mi).
* container `securityContext`: `allowPrivilegeEscalation: false`, `readOnlyRootFilesystem: true` (the app can write only to the two `emptyDir` volumes, `/tmp` and `/etc/nginx/conf.d` where the start-up script writes the rendered config), `capabilities.drop: ["ALL"]`.

### The Service
Selector `app: web`, port 80 forwarded to the named container port `http`. It is a stable name (`web.web.svc`) in front of whichever Pods are ready.

### Argo CD's custom resources
The **AppProject** limits what the controller may do: one source repository, one destination namespace, and only the `Namespace` kind at cluster scope. The **Application** says: take `path: apps/web/overlays/local` of `targetRevision: main` from `repoURL: http://git-server.git-server.svc.cluster.local/gitops-demo.git` and apply it to `namespace: web`. `syncPolicy.automated.prune/selfHeal: false` is the lesson's starting point. `finalizers: resources-finalizer.argocd.argoproj.io` makes deleting the Application also delete what it created.

### The Git server
Strategy `Recreate` (stop the old Pod before starting the new one; there is one `emptyDir` of repositories). Two Services: `git-server` (ClusterIP, used inside the cluster) and `git-server-host` (`type: NodePort`, `nodePort: 30418`, so the host can push through the node's published port).

## 6. Try it yourself

1. `kubectl --context k3d-gitops-drift get all -n web` : the Deployment, ReplicaSet, two Pods and the Service.
2. `kubectl --context k3d-gitops-drift get deploy web -n web -o yaml | head -60` : the object as the cluster stores it, with `status`.
3. `kubectl --context k3d-gitops-drift describe pod -n web -l app=web | grep -A3 -i probe` : the probes.
4. `kubectl --context k3d-gitops-drift get events -n web --sort-by=.lastTimestamp | tail` : what Kubernetes did, step by step.
5. `kubectl --context k3d-gitops-drift scale deploy web -n web --replicas=5` (self-heal off) : the Deployment obeys; Argo CD reports OutOfSync.

## 7. Mistakes people make

- Editing the live object by hand. A controller that reconciles from Git will revert it; that is the point of the lesson.
- Selectors that do not match the Pod labels, so a Service has no endpoints.
- Setting no resource requests and limits, so one Pod can starve the node. Every container here sets both.
- Expecting an environment variable from a ConfigMap to change in a running Pod. It is read once at container start, so the Pod template must change as well.

## 8. Check yourself

1. What does 'declarative' mean in Kubernetes?
   *Answer:* You describe the state you want and controllers work to make reality match it.
2. What does a Deployment create to keep Pods running?
   *Answer:* A ReplicaSet, which creates the Pods.
3. How does a Service know which Pods to send traffic to?
   *Answer:* Its selector matches the Pods' labels.
4. What is the difference between a liveness and a readiness probe?
   *Answer:* Liveness failing restarts the container; readiness failing only removes the Pod from the Service.
5. Why does a ConfigMap change not reach a running Pod's environment variables?
   *Answer:* Environment variables are fixed when the container starts.

## 9. Further reading

- Kubernetes documentation: <https://kubernetes.io/docs/concepts/>. Version used here: Kubernetes 1.35 (k3s v1.35.5 inside the cluster).
