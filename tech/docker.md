# Docker and the Dockerfile

## 1. What it is

Docker runs programs in **containers**: isolated processes that see their own file system, their own network and their own process list, but share the host's kernel. An **image** is the read-only bundle (files plus start command) a container starts from. A **Dockerfile** is the recipe that builds an image, one instruction per line.

## 2. Why this repository uses it

The application and the Git server are small images built locally and loaded into the cluster, so the lesson needs no registry and no cloud account. The images are tiny on purpose: the lesson is about the controller, not the app.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `docker/web/Dockerfile` | the demo application: an unprivileged nginx with a template |
| `docker/git-server/Dockerfile` | a minimal Git server (nginx, git, fcgiwrap, tini) on Alpine |
| `scripts/build-images.sh` | runs `docker build` three times and imports the images |
| `versions.env` | the base images, pinned by tag and digest |

## 4. How it works underneath

- `docker build` reads the Dockerfile top to bottom. Each instruction (`FROM`, `RUN`, `COPY`...) produces a **layer**, a set of file changes stored by its content hash. Docker re-uses a layer when the instruction and everything before it are unchanged, so put the slow, rarely-changing steps first.
- `FROM` picks the starting image. A **digest** (`image@sha256:...`) pins the exact bytes; a tag such as `1.31.7-alpine` can be re-pushed to point somewhere else.
- `ARG` is a build-time variable; `ENV` is a variable inside the running container.
- `ENTRYPOINT` is the program the container runs; `CMD` gives its default arguments. `USER` sets who runs it. `EXPOSE` only documents a port. `HEALTHCHECK` runs a command periodically and marks the container healthy or not.
- A container is a normal process on the host, started in new Linux **namespaces** (own view of files, network, processes) and limited by **cgroups** (CPU and memory caps).
- Images live in the local Docker store. A cluster node is itself a container, with its own store, so a locally built image must be **imported** into the node before a pod can use it (there is no registry here).

## 5. Walkthrough of this repository's use

### `docker/web/Dockerfile`

```dockerfile
ARG BASE_IMAGE=nginxinc/nginx-unprivileged:1.31.7-alpine
FROM ${BASE_IMAGE}
```
An `ARG` before `FROM` can pick the base image. `build-images.sh` passes the digest-pinned value from `versions.env`. `nginx-unprivileged` runs as a normal user (uid 101) and listens on port 8080, because ports under 1024 need root.

```dockerfile
ARG APP_VERSION=dev
ENV APP_VERSION=${APP_VERSION}
```
The build argument becomes an environment variable inside the container. The two builds (1.0.0 and 1.1.0) differ only by this value, so there is an "old" and a "new" image to roll between.

```dockerfile
COPY default.conf.template /etc/nginx/templates/default.conf.template
```
The base image's start-up script renders every `*.template` file in that folder, replacing `${NAME}` with environment variables (`envsubst`), and writes the result to `/etc/nginx/conf.d/`. This is how `GREETING` (from the ConfigMap) and `APP_VERSION` reach the web page.

```dockerfile
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
```
`EXPOSE` documents the port. `HEALTHCHECK` runs `wget` quietly (`-q`), discarding the body (`-O /dev/null`) and marks the container unhealthy if it fails. Kubernetes ignores this and uses its own probes, but `docker ps` shows it.

### `docker/git-server/Dockerfile`

```dockerfile
RUN apk add --no-cache git git-daemon nginx fcgiwrap tini \
 && adduser -D -u 10001 git \
 && mkdir -p /srv/git && chown git:git /srv/git
```
One `RUN` means one layer. `apk` is Alpine's package manager; `--no-cache` keeps the package index out of the image. `adduser -D -u 10001 git` makes a user without a password and with a fixed uid, so the pod can say `runAsUser: 10001`. `/srv/git` holds the repositories.

```dockerfile
COPY nginx.conf /etc/nginx/nginx.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
USER 10001
ENTRYPOINT ["/sbin/tini", "--", "/usr/local/bin/entrypoint.sh"]
```
`tini` is a tiny init process: it is process 1 in the container, passes signals on and cleans up finished child processes. The script is started by tini. `USER 10001` runs everything as the unprivileged user (so nginx writes only to `/tmp`, set in `nginx.conf`).

### `scripts/build-images.sh`
`docker build --quiet --tag plainround/web:1.0.0 --build-arg BASE_IMAGE=... --build-arg APP_VERSION=1.0.0 docker/web`. `--quiet` prints only the image id (thrown away). Then `provider_load_images` imports the three images into the cluster node.

## 6. Try it yourself

1. `docker image ls plainround/*` : shows the three local images.
2. `docker run --rm -d -p 18080:8080 -e GREETING=hi plainround/web:1.1.0` then `curl localhost:18080/` and `/version` : `hi` and `1.1.0`. Stop it with `docker stop <id>`.
3. `docker history plainround/git-server:1.0.0` : lists the layers, one per instruction.
4. `docker inspect --format '{{.Config.User}}' plainround/git-server:1.0.0` : `10001`.
5. `docker exec k3d-gitops-drift-server-0 crictl images | grep plainround` : the images inside the cluster node.

## 7. Mistakes people make

- **Running as root inside the container.** The images here switch to an unprivileged user and the pods drop all capabilities.
- **A tag that moves.** `latest` can change under you; this repository pins versions and, for base images, digests.
- **Copying secrets into a layer.** A deleted file still exists in an earlier layer. No secret is ever copied into an image here.
- **Forgetting that `RUN` lines each add a layer**, so `apk add` and the clean-up belong in one `RUN` joined with `&&`.
- **Assuming the node can see your local images.** It cannot until they are imported.

## 8. Check yourself

1. What is the difference between an image and a container?
   *Answer:* An image is the read-only package; a container is a running process started from it.
2. Why pin a base image by digest?
   *Answer:* A digest names exact bytes and cannot be re-pointed, unlike a tag.
3. What is the difference between `ENTRYPOINT` and `CMD`?
   *Answer:* `ENTRYPOINT` is the program; `CMD` is its default arguments, which a caller can replace.
4. Why put `COPY` of a changing file after `RUN apk add`?
   *Answer:* A changed file invalidates its layer and every layer after it; the slow install stays cached.
5. How does a locally built image reach a cluster node?
   *Answer:* It is imported into the node's own image store (`k3d image import` or `kind load docker-image`).

## 9. Further reading

- Dockerfile reference: <https://docs.docker.com/reference/dockerfile/>. Engine used while building this repository: Docker 24.0.6 (`docker version`).
