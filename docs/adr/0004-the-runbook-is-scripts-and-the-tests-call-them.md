# 0004. The runbook is scripts, and the tests call the scripts

## Context

The lesson's steps are commands a person types. The task is also to prove each behavior with a test.

## Decision

Each step is a shell script under `scripts/runbook/` that does the work (edit, commit, push, drift, wait) and prints what it saw. The Python tests under `tests/cluster/` run those scripts and then assert on the cluster and the controller's status with read-only `kubectl` calls. There is one implementation of every step, so `make run` and `make test` cannot disagree.

## Alternatives

- **Re-implement the steps in Python.** Two copies of the runbook that drift apart, the failure this repository teaches about.
- **Bash test files (bats).** Fewer dependencies, but no typed helpers, no fixtures and no unit tests for the polling logic.

## Consequences

- Python is only the test language. The helpers (`tests/support`) are typed, have their own unit tests with an injected clock and an injected `kubectl`, and run at 100 percent coverage without a cluster.
- The tests never change the cluster except through the scripts; the one exception is the drift the lesson asks for, which is also a script.
