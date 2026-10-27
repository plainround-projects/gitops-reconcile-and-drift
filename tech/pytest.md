# pytest

## 1. What it is

pytest is a Python test runner. It finds files named `test_*.py`, runs every function named `test_*`, and reports which passed. A test passes when it finishes without an error; the `assert` statement raises one when its condition is false.

## 2. Why this repository uses it

Two kinds of proof: **offline** tests that need nothing running (helpers, manifests, the validation gate) and **cluster** tests that run the real runbook against the cluster.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `tests/unit/` | unit tests of the helpers, the manifests and the validation script |
| `tests/cluster/test_01..06` | one module per lesson step: first sync, change through Git, drift, prune, rollback, bad manifest |
| `tests/compare/test_flux_behaviors.py` | the Flux comparison |
| `pyproject.toml` | `[tool.pytest.ini_options]`: markers, `--strict-markers`, `-ra`; `[tool.coverage.*]` |
| `Makefile` | `test-offline`, `test-cluster`, `test`, `compare` |

## 4. How it works underneath

- A **fixture** is a function marked `@pytest.fixture` that builds something a test needs (a client, a folder). A test asks for it by writing the fixture's name as a parameter. `scope="session"` builds it once for the whole run, `scope="module"` once per file.
- A **marker** (`@pytest.mark.cluster`) tags tests; `-m "not cluster"` selects or skips tags. `--strict-markers` makes an unregistered tag an error.
- `conftest.py` files hold fixtures shared by the tests in their folder.
- `monkeypatch` and `tmp_path` are built-in fixtures for replacing things and getting a throwaway folder.
- `pytest-cov` measures which lines the tests ran; `fail_under = 90` fails the run below 90 percent.

## 5. Walkthrough of this repository's use

### Configuration (`pyproject.toml`)
```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["."]
addopts = "-ra --strict-markers"
markers = ["cluster: ...", "compare: ..."]
```
`testpaths` and `pythonpath` make `import tests.support...` work from the repository root. `-ra` prints a short reason for every skipped or failed test. `--strict-markers` makes a typo in `@pytest.mark.clustr` an error. Two markers are registered so `-m "not cluster and not compare"` selects the offline tests.

```toml
[tool.coverage.run]
source = ["tests/support"]
branch = true
[tool.coverage.report]
fail_under = 90
```
Coverage measures `tests/support` (the code that is Python logic, with branch coverage) and fails the run below 90 percent.

### A cluster test (`tests/cluster/test_03_drift.py`)
```python
def test_with_self_heal_off_the_drift_is_reported_and_left_alone(kube: Kube, runbook: Runbook) -> None:
    runbook.script("runbook/02-change-through-git.sh")
    output = runbook.script("runbook/03-drift.sh", "off")
    assert kube.deployment_replicas(NAMESPACE, "web") == 5
    assert kube.application(APP).sync_status == "OutOfSync"
```
The test names say what is proven. Fixtures `kube` and `runbook` come from `conftest.py`. The test runs the real scripts, then asserts on the real cluster. A module-scoped, automatic fixture `clean_demo` in `tests/cluster/conftest.py` calls `reset.sh` first, so every module starts from the lesson's first state.

The second test turns self-heal on and uses `wait_until("the app to be Synced", lambda: ..., timeout=60)` to wait for the revert.

### The offline tests
They use `monkeypatch`-free dependency injection: `Kube(context, runner=fake)` gets a fake runner; `wait_until` gets a fake clock. So `test_waiting.py` tests timeouts without sleeping.

## 6. Try it yourself

1. `make test-offline` : 26 tests pass in a few seconds with the coverage table (needs no cluster).
2. `.venv/bin/pytest -m cluster --collect-only -q` : lists the cluster tests without running them.
3. `.venv/bin/pytest tests/unit/test_waiting.py -q -k timeout` : `-k` selects by name.
4. `.venv/bin/pytest tests/unit -q --cov --cov-report=term-missing` : the lines not covered.
5. `make test-cluster` (cluster up) : runs the six modules in order.

## 7. Mistakes people make

- Tests that depend on the order they run in. Here each cluster module resets the demo first.
- Real sleeps in tests. The waiting helper takes an injected clock, so its tests take no time.
- Marking a test "skip" to make a run green. A skip hides a real failure.

## 8. Check yourself

1. How does pytest find tests?
   *Answer:* Files named `test_*.py` and functions named `test_*`.
2. What is a fixture?
   *Answer:* A function that builds something a test needs, passed in by parameter name.
3. What does `-m "not cluster"` do?
   *Answer:* It runs only tests that do not carry the `cluster` marker.
4. What makes a test fail?
   *Answer:* An exception, usually from a false `assert`.
5. What does `fail_under = 90` do?
   *Answer:* It fails the run when less than 90 percent of the measured lines ran.

## 9. Further reading

- pytest documentation: <https://docs.pytest.org/en/stable/> (version 9). pytest-cov: <https://pytest-cov.readthedocs.io/>.
