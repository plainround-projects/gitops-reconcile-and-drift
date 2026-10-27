# 0001. Argo CD as the controller

## Context

The lesson allows Argo CD or Flux. Step 6 asks for a comparison of how the two handle self-healing, pruning and health checks.

## Decision

Run Argo CD v3.5.6 as the controller for the whole runbook, and put the comparison with Flux in the README as a table.

## Alternatives

- **Flux.** Its drift handling is on by default at every interval, which would make the lesson's "first off, then on" step impossible to show. Argo CD makes self-heal and prune explicit switches on the Application, which is what step 3 and step 4 need.

## Consequences

- The `Application` object is the place the runbook flips `selfHeal` and `prune`. It is configuration of the controller, not of the workload, and it is not itself synced from Git (that is the lesson's third stretch goal).
- Every observable (sync status, health, revision, history, last operation) comes from the Application's status, so the tests read one object.
