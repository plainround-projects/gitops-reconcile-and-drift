# 0003. Images built locally and loaded into the cluster

## Context

The application image and the Git server image must be available to the cluster without a registry account.

## Decision

`scripts/build-images.sh` builds `plainround/web:1.0.0`, `plainround/web:1.1.0` and `plainround/git-server:1.0.0` with Docker and loads them with `kind load docker-image`. Pods use `imagePullPolicy: IfNotPresent` and a fixed version tag, never `latest`.

## Alternatives

- **A local registry.** Needed only when something must be referenced by digest; the sibling project gitops-environments-and-secrets does that. Here a version tag is what the lesson's rollback restores.
- **The lesson's `nginx:1.27`.** It runs as root and cannot show a visible, per-version difference. The built image is nginx-unprivileged with a one-file configuration that prints the greeting and the version.

## Consequences

- `make up` needs Docker and builds in under a minute on a warm cache.
- The two web images differ only in the version string they print, which is what lets the tests see which image answered.
