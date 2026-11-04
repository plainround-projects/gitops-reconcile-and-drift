# Changelog

All notable changes to this project are recorded here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- Drawn architecture and flow figures in `docs/diagrams/`, light and dark, shown in the README.

### Fixed

- Findings of the first live run: pushing a leftover working clone, keeping the hook's report out of the captured commit hash, reading managed fields, recognising a refused sync that is being retried, letting the caller's cluster name win over `.env`, and a Flux pruning comparison that waits for Flux to apply each commit.

## [0.1.0] - 2026-10-27

### Added

- A kind cluster (`make up`) with Argo CD v3.5.6 installed from pinned manifests and an in-cluster Git server holding the repository the controller watches.
- The desired-state tree (`manifests/`): a Kustomize base and a `local` overlay for a web app (Namespace, ConfigMap, Deployment, Service) and the Argo CD project and application that point at it.
- The scripted runbook for the lesson's steps: change through Git, drift with self-heal off and on, prune off and on, a bad commit and its `git revert`, and a manifest the schema refuses.
- Offline tests for the helper code and the manifests, and cluster tests that prove each runbook step.
- yamllint, kubeconform, shellcheck, ruff and mypy in `make lint`, and a CI workflow that also runs the cluster tests on a kind cluster.
