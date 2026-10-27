# 0002. A Git server inside the cluster

## Context

The lesson's controller watches "a Git repository you own". The repository must be reachable from inside the cluster and writable from the host, without a GitHub account, a token or a public IP.

## Decision

Deploy a small smart-HTTP Git server (nginx and `git-http-backend`, built from `docker/git-server`) in the `git-server` namespace. Inside the cluster it is `http://git-server.git-server.svc.cluster.local/gitops-demo.git`; from the host a kind port mapping publishes it on `127.0.0.1:30418`. The working clone in `.work/gitops-demo` pushes to it.

## Alternatives

- **GitHub or another hosted Git service.** Needs an account and credentials the controller must hold; not reproducible by a stranger.
- **`file://` or a mounted volume.** Argo CD's repo server does not read the host's files, and a mount would bypass the pull-over-network path the lesson is about.
- **Gitea.** A full forge for a job that needs three HTTP endpoints; 200 MB of memory the laptop does not have to spare.

## Consequences

- The server has no authentication. It listens on the loopback interface of the host and on a cluster-internal service; that is acceptable for a throwaway local cluster and is named in the README. To use a real repository, change `repoURL` in `manifests/clusters/local` and the project's `sourceRepos`.
- Repositories live in an `emptyDir`. A pod restart empties them; `make up` seeds them again.
