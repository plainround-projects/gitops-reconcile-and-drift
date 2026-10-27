# 0005. A twenty-second poll interval

## Context

Argo CD polls Git every three minutes with up to a minute of random delay. The lesson tells the reader to wait for it. A scripted runbook with a dozen waits would take most of an hour.

## Decision

`platform/argocd/controller-settings.yaml` sets `timeout.reconciliation: 20s` and `timeout.reconciliation.jitter: 0s`. Nothing else about the controller is changed; self-heal reacts to live-object changes through the controller's watch, not the poll.

## Alternatives

- **Webhooks.** Needs the Git server to call the controller; one more moving part for no lesson value.
- **`argocd app refresh` after every push.** Hides the interval, which the lesson's common-mistakes list says to respect. `refresh_app` exists in `scripts/lib.sh` but the runbook does not use it.

## Consequences

- Every "wait for the controller" in the scripts has a 240-second budget, about ten polls.
- The README says the default is three minutes and shows where to change it back.
