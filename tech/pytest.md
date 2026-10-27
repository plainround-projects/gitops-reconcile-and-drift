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

<!-- full-walkthrough:begin -->
### 5.A Full walkthrough: every test file

**A pytest primer.**
- A **test** is a function whose name starts with `test_`. pytest finds it, calls it, and reports "passed" if it ends without an error. The keyword `assert condition` raises an error when the condition is false; so each `assert` is one thing the test insists must be true.
- A **fixture** is a function marked `@pytest.fixture` that prepares something a test needs. A test asks for it by writing its name as a parameter; pytest calls the fixture and passes the result in. `scope="session"` means "make it once for the whole run", `scope="module"` "once per test file", no scope "once per test". `autouse=True` means "apply it to every test without being asked".
- A **marker** is a label on tests (`@pytest.mark.cluster`). `pytest -m "not cluster"` runs only tests without the label.
- A file named `conftest.py` is read automatically by pytest; fixtures defined there are available to all tests next to it.
- The tests are of two kinds. **Unit tests** (`tests/unit/`) need no cluster: they use fakes. **Cluster tests** (`tests/cluster/`, `tests/compare/`) run the real scripts against a running cluster.

#### `tests/conftest.py`: shared fixtures

```python
"""Fixtures shared by the cluster tests."""

from __future__ import annotations

import os
from pathlib import Path

import pytest

from tests.support.kube import Kube
from tests.support.shell import run

ROOT = Path(__file__).resolve().parent.parent

```

- The docstring, the imports and one constant. `import os` is used for the operating-system helpers; `pytest` is the test framework; `Kube` and `run` come from the helpers explained in the Python note.
- `ROOT = Path(__file__).resolve().parent.parent` finds the repository folder. `__file__` is this file's path; `.resolve()` makes it absolute; `.parent` goes one folder up each time (`tests/` then the repository).

```python
def pytest_collection_modifyitems(items: list[pytest.Item]) -> None:
    """Tests under tests/cluster are marked ``cluster`` so `-m "not cluster"` runs the offline ones."""
    for item in items:
        if "tests/cluster" in str(item.fspath).replace(os.sep, "/"):
            item.add_marker(pytest.mark.cluster)
```

- `pytest_collection_modifyitems` is a **hook**: pytest calls any function with this exact name after it has collected the tests, passing the list `items`. The loop looks at each test's file path (`item.fspath`; `.replace(os.sep, "/")` makes the folder separator the same on every system) and, if it is under `tests/cluster`, adds the `cluster` marker. That is how `-m "not cluster"` finds the offline tests.

```python
@pytest.fixture(scope="session")
def root() -> Path:
    """The repository root."""
    return ROOT


@pytest.fixture(scope="session")
def cluster_name() -> str:
    """The kind cluster this project owns."""
    return os.environ.get("CLUSTER_NAME", "gitops-drift")
```

- `root` (session fixture) hands the repository folder to any test that asks.
- `cluster_name` returns the environment variable `CLUSTER_NAME`, or `gitops-drift` if it is not set (`os.environ.get(name, default)`).

```python
def context_of(cluster_name: str) -> str:
    """The kubectl context of the cluster: k3d's or kind's, whichever `make up` created."""
    contexts = run(["kubectl", "config", "get-contexts", "-o", "name"], check=False).stdout.split()
    for candidate in (f"k3d-{cluster_name}", f"kind-{cluster_name}"):
        if candidate in contexts:
            return candidate
    pytest.fail(f"no kubectl context for cluster {cluster_name}: run `make up` first", pytrace=False)
```

- `context_of` finds the `kubectl` context for the cluster. It runs `kubectl config get-contexts -o name` (a list of context names, one per line; `.split()` splits the text at whitespace into a list), then tries `k3d-<name>` and `kind-<name>` in that order and returns the first that exists.
- If none exists, `pytest.fail(…, pytrace=False)` ends the test with a short message and no long Python error trace. The message tells the person to run `make up`.

```python
@pytest.fixture(scope="session")
def kube(cluster_name: str) -> Kube:
    """kubectl pinned to the project's cluster; the tests need `make up` to have run."""
    client = Kube(context_of(cluster_name))
    if client.kubectl("get", "namespace", "argocd", check=False).returncode != 0:
        pytest.fail("the cluster is not up: run `make up` first", pytrace=False)
    return client
```

- The `kube` fixture creates a `Kube` pinned to the right context, then checks that the `argocd` namespace exists (`check=False` so a failure is an answer, not an exception). If it does not, the cluster is not up, and the test fails with a clear message.

```python
@pytest.fixture(scope="module")
def runbook_module(root: Path) -> Runbook:
    """The same as ``runbook``, for fixtures that live for a whole module."""
    return Runbook(root)


@pytest.fixture
def runbook(root: Path) -> Runbook:
    """Run the repository's scripts from the repository root."""
    return Runbook(root)
```

- Two fixtures that return a `Runbook` object, one per test and one per test file. `Runbook` is defined just below; Python allows using the name in a hint because of `from __future__ import annotations`.

```python
class Runbook:
    """Calls the scripts under scripts/ (the same ones a person runs) and returns what they printed."""

    def __init__(self, root: Path) -> None:
        """Remember where the scripts live."""
        self.root = root

    def script(self, relative: str, *args: str, check: bool = True, timeout: float = 600) -> str:
        """Run ``scripts/<relative>``; return its combined output."""
        result = run([str(self.root / "scripts" / relative), *args], cwd=self.root, check=check, timeout=timeout)
        return result.output

    def work_head(self) -> str:
        """The commit at the tip of the working clone."""
        return run(["git", "-C", str(self.root / ".work" / "gitops-demo"), "rev-parse", "HEAD"]).stdout.strip()
```

- `class Runbook` calls the repository's scripts, "the same ones a person runs".
- `script(relative, *args, check=True, timeout=600)` runs `scripts/<relative>` from the repository folder with the extra arguments and returns everything it printed (`result.output`). A test then asserts on that text.
- `work_head` runs `git -C .work/gitops-demo rev-parse HEAD` and returns the newest commit of the working clone (`.strip()` removes the line break).

#### `tests/cluster/conftest.py`: every module starts from a clean demo

```python
"""Every cluster test module starts from the first state of the lesson."""

from __future__ import annotations

from pathlib import Path

import pytest

from tests.conftest import Runbook
from tests.support.kube import Kube

APP = "web"
NAMESPACE = "web"


@pytest.fixture(scope="module", autouse=True)
def clean_demo(root: Path, kube: Kube) -> None:
    """Delete the demo, reseed the repository and let the controller deploy it again."""
    Runbook(root).script("reset.sh")
```

- `APP` and `NAMESPACE` are the names of the demo; the tests import them.
- The fixture `clean_demo` has `scope="module", autouse=True`: **before each test file**, automatically, it runs `scripts/reset.sh`, which deletes the demo and sets it up again. That way no test file depends on what an earlier file left behind. It asks for `root` and `kube` so those exist (and the cluster is checked) first.

#### `tests/cluster/test_01_first_sync.py`

```python
"""Lesson step 1: the app appears without a kubectl apply, synced and healthy."""

from __future__ import annotations

from tests.conftest import Runbook
from tests.support.kube import Kube
from tests.support.waiting import wait_until

from .conftest import APP, NAMESPACE
```

- The docstring names the lesson step. The imports bring in the helper classes and the two names from the local `conftest` (`from .conftest import …`: the dot means "this folder").

```python
def test_the_app_appears_synced_and_healthy_from_git(kube: Kube, runbook: Runbook) -> None:
    head = runbook.work_head()

    state = wait_until(
        "the app synced and healthy at the seeded commit",
        lambda: (s := kube.application(APP)).sync_status == "Synced" and s.health_status == "Healthy" and s,
        timeout=240,
    )

    assert state.revision == head

```

- Test 1: the application appears, synced and healthy, from Git. `head` is the newest commit of the working clone.
- `wait_until(description, probe, timeout=240)` waits up to four minutes for the probe. The probe is a `lambda` using the **walrus operator** `:=`, which assigns and tests in one expression: `(s := kube.application(APP)).sync_status == "Synced" and s.health_status == "Healthy" and s` reads the state once, checks both fields, and (if both are right) returns `s` itself as the truthy result. `wait_until` returns that state.
- The final `assert` insists that the revision Argo CD applied equals the newest commit.

```python
def test_the_workloads_were_written_by_the_controller_and_not_by_kubectl(kube: Kube) -> None:
    managers = kube.field_managers("deployment", "web", NAMESPACE)

    assert "argocd-controller" in managers
    assert not any(manager.startswith("kubectl") for manager in managers)
```

- Test 2: the workloads were written by the controller, not by `kubectl apply`. `field_managers` returns who wrote the Deployment. The first assert needs `argocd-controller` among them; the second uses `any(manager.startswith("kubectl") for …)`: "is there any manager whose name starts with kubectl?". `assert not any(...)` demands there is none.

```python
def test_two_pods_run_and_the_service_answers_with_the_greeting(kube: Kube) -> None:
    wait_until(
        "two ready replicas",
        lambda: kube.get("deployment", "web", NAMESPACE)["status"].get("readyReplicas") == 2,
        timeout=120,
    )

    assert kube.get_through_service(NAMESPACE, "web") == "hello"
    assert kube.get_through_service(NAMESPACE, "web", "/version") == "1.0.0"
```

- Test 3: two pods run and the Service answers. The first `wait_until` waits for `readyReplicas == 2` (`["status"].get("readyReplicas")` returns nothing while no pod is ready). Then it fetches `/` through the Service and expects the greeting `hello`, and `/version` and expects `1.0.0`.

#### `tests/cluster/test_02_change_through_git.py`

```python
"""Lesson step 2: a commit reaches the cluster, and every running object can be traced to a commit."""

from __future__ import annotations

from tests.conftest import Runbook
from tests.support.kube import Kube

from .conftest import APP, NAMESPACE

```

- Docstring and imports; nothing new.

```python
def test_a_commit_scales_the_app_and_changes_the_greeting(kube: Kube, runbook: Runbook) -> None:
    output = runbook.script("runbook/02-change-through-git.sh")

    assert kube.deployment_replicas(NAMESPACE, "web") == 3
    assert kube.configmap_value(NAMESPACE, "web-config", "GREETING") == "hi there"
    assert "GREETING:  hi there" in output
    assert kube.get_through_service(NAMESPACE, "web") == "hi there"
```

- Runs the script of step 2 and keeps its printed output. Then, asking the real cluster, it asserts: three replicas, the greeting `hi there`, the same greeting in the script's own output (`"GREETING:  hi there" in output` tests that the text contains that piece), and the greeting returned by the Service.

```python
def test_the_running_objects_name_the_commit_they_came_from(kube: Kube, runbook: Runbook) -> None:
    state = kube.application(APP)

    assert state.revision == runbook.work_head()
    assert state.history_revisions[-1] == runbook.work_head()
    assert len(state.history_revisions) >= 2
```

- The second test asks: can every running object be traced to a commit? Argo CD's `revision` must equal the newest commit; the last entry of the history must be that commit too (`[-1]` is the last item of a list); and at least two deployments exist in the history (the initial one and this change).

#### `tests/cluster/test_03_drift.py`

```python
"""Lesson step 3: drift is reported with self-heal off and reverted with it on."""

from __future__ import annotations

from tests.conftest import Runbook
from tests.support.kube import Kube
from tests.support.waiting import wait_until

from .conftest import APP, NAMESPACE
```

- Docstring and imports, including `wait_until`.

```python
def test_with_self_heal_off_the_drift_is_reported_and_left_alone(kube: Kube, runbook: Runbook) -> None:
    runbook.script("runbook/02-change-through-git.sh")

    output = runbook.script("runbook/03-drift.sh", "off")

    assert kube.deployment_replicas(NAMESPACE, "web") == 5
    assert kube.configmap_value(NAMESPACE, "web-config", "GREETING") == "hacked"
    assert kube.application(APP).sync_status == "OutOfSync"
    assert not kube.application(APP).self_heal
    assert "+  replicas: 5" in output or "replicas: 5" in output
    assert "GREETING: hacked" in output
```

- With self-heal off: first run step 2 so the cluster has three replicas and the greeting `hi there`; then run `03-drift.sh off`. The asserts: the live replica count is **5** and the greeting is **hacked** (the drift is still there), Argo CD says `OutOfSync`, self-heal is off, and the script's printed diff contains the changed lines.
- `assert "+  replicas: 5" in output or "replicas: 5" in output` accepts either form of the diff line (with or without the leading plus sign).

```python
def test_with_self_heal_on_both_changes_are_reverted_without_a_command(kube: Kube, runbook: Runbook) -> None:
    output = runbook.script("runbook/03-drift.sh", "on")

    wait_until(
        "the app to be Synced",
        lambda: kube.application(APP).sync_status == "Synced",
        timeout=60,
    )
    assert kube.deployment_replicas(NAMESPACE, "web") == 3
    assert kube.configmap_value(NAMESPACE, "web-config", "GREETING") == "hi there"
    assert kube.application(APP).self_heal
    assert "reverted in" in output
```

- With self-heal on: run `03-drift.sh on`, then `wait_until` the app is `Synced` (60 seconds at most). The cluster must be back to **3** replicas and the greeting `hi there` (Git's values), self-heal must be on, and the script output must contain `reverted in` (it prints the revert time).

#### `tests/cluster/test_04_prune.py`

```python
"""Lesson step 4: with prune off a deleted file leaves its object (flagged); with prune on it is removed."""

from __future__ import annotations

from tests.conftest import Runbook
from tests.support.kube import Kube

from .conftest import APP, NAMESPACE

```

- Docstring and imports.

```python
def test_with_prune_off_the_object_stays_and_the_app_is_out_of_sync(kube: Kube, runbook: Runbook) -> None:
    output = runbook.script("runbook/04-prune.sh", "off")

    assert kube.exists("configmap", "web-config", NAMESPACE)
    assert kube.application(APP).sync_status == "OutOfSync"
    assert "ConfigMap/web-config" in output
```

- Prune off: after `04-prune.sh off`, the ConfigMap **still exists** (`kube.exists`), the application is `OutOfSync`, and the script output mentions `ConfigMap/web-config` as needing pruning.

```python
def test_with_prune_on_the_object_is_removed(kube: Kube, runbook: Runbook) -> None:
    runbook.script("runbook/04-prune.sh", "on")

    assert not kube.exists("configmap", "web-config", NAMESPACE)
    assert kube.application(APP).sync_status == "Synced"
```

- Prune on: the ConfigMap is gone and the app is `Synced`.

```python
def test_git_revert_brings_the_object_back(kube: Kube, runbook: Runbook) -> None:
    runbook.script("runbook/04-prune.sh", "restore")

    assert kube.exists("configmap", "web-config", NAMESPACE)
    assert kube.application(APP).sync_status == "Synced"
```

- `git revert` of the deleting commit: the ConfigMap is back and the app is `Synced`.

#### `tests/cluster/test_05_rollback.py`

```python
"""Lesson step 5: a bad commit degrades the app; git revert restores the previous image with no kubectl."""

from __future__ import annotations

from tests.conftest import Runbook
from tests.support.kube import Kube

from .conftest import APP, NAMESPACE

PREVIOUS_IMAGE = "plainround/web:1.0.0"
BAD_IMAGE = "plainround/web:1.1.0"
```

- Two constants name the two images so the asserts read clearly.

```python
def test_the_bad_commit_makes_the_controller_report_degraded_while_old_pods_keep_serving(
    kube: Kube, runbook: Runbook
) -> None:
    runbook.script("runbook/05-break-and-rollback.sh", "bad")

    assert kube.application(APP).health_status == "Degraded"
    assert kube.deployment_image(NAMESPACE, "web") == BAD_IMAGE
    assert kube.get_through_service(NAMESPACE, "web", "/version") == "1.0.0"
```

- The bad commit: the signature is written over three lines because it is long. After `05-break-and-rollback.sh bad` the app is `Degraded`; the Deployment **asks for** the bad image; yet the Service still answers with version `1.0.0`: the old pods keep serving.

```python
def test_git_revert_restores_the_previous_image_and_health(kube: Kube, runbook: Runbook) -> None:
    runbook.script("runbook/05-break-and-rollback.sh", "rollback")

    state = kube.application(APP)
    assert state.health_status == "Healthy"
    assert state.sync_status == "Synced"
    assert state.revision == runbook.work_head()
    assert kube.deployment_image(NAMESPACE, "web") == PREVIOUS_IMAGE
    assert kube.get_through_service(NAMESPACE, "web", "/version") == "1.0.0"
```

- The rollback: health `Healthy`, sync `Synced`, the revision equals the newest commit (the revert), the Deployment image is the previous one again, and the Service answers `1.0.0`.

#### `tests/cluster/test_06_bad_manifest.py`

```python
"""A manifest the schema refuses never reaches the cluster: the hook, then the API server, say no."""

from __future__ import annotations

from tests.conftest import Runbook
from tests.support.kube import Kube

from .conftest import APP, NAMESPACE

```

- The docstring states the claim: an invalid manifest never reaches the cluster.

```python
def test_an_invalid_manifest_is_refused_by_the_hook_and_by_the_api_server(kube: Kube, runbook: Runbook) -> None:
    replicas_before = kube.deployment_replicas(NAMESPACE, "web")

    output = runbook.script("runbook/06-bad-manifest.sh")

    assert "1. the pre-push hook refuses it" in output
    assert "replicas" in output
    assert "operation phase: Error" in output or "operation phase: Failed" in output
    assert kube.deployment_replicas(NAMESPACE, "web") == replicas_before
    state = kube.application(APP)
    assert (state.sync_status, state.health_status) == ("Synced", "Healthy")
```

- Remember the replica count; run the script; assert its output shows the hook refusing (`1. the pre-push hook refuses it`) and mentions `replicas`; assert the operation phase was `Error` or `Failed`; the live replica count did **not** change; and the app ends `Synced` and `Healthy` after the revert. `(a, b) == ("Synced", "Healthy")` compares two values at once as a pair.

#### `tests/compare/test_flux_behaviors.py`

```python
"""Step 6: the same three behaviors on Flux, so the README's comparison table rests on a run, not on reading."""

from __future__ import annotations

import pytest

from tests.conftest import Runbook

pytestmark = pytest.mark.compare

```

- `pytestmark = pytest.mark.compare` puts the `compare` label on every test in the file.

```python
@pytest.fixture(scope="module")
def results(runbook_module: Runbook) -> dict[str, str]:
    output = runbook_module.script("compare/flux-behaviors.sh", timeout=1200)
    lines = [line.removeprefix("RESULT ") for line in output.splitlines() if line.startswith("RESULT ")]
    return {line.split(":", 1)[0]: line for line in lines}
```

- A module-scoped fixture runs `compare/flux-behaviors.sh` once (up to 20 minutes) and builds a dictionary from its lines. `line.removeprefix("RESULT ")` removes that start; `line.split(":", 1)[0]` takes the text before the first colon as the key (`drift`, `prune-off`, `prune-on`, `health`, `rollback`).

```python
def test_flux_reverts_drift_with_no_self_heal_setting(results: dict[str, str]) -> None:
    assert "replicas 5 -> 2" in results["drift"]
    assert "hacked -> hello" in results["drift"]


def test_flux_leaves_a_deleted_object_alone_until_prune_is_on(results: dict[str, str]) -> None:
    assert "ConfigMap present" in results["prune-off"]
    assert "Ready=True" in results["prune-off"]
    assert "gone after spec.prune=true" in results["prune-on"]


def test_flux_reports_an_unhealthy_rollout_as_not_ready_and_recovers_on_revert(results: dict[str, str]) -> None:
    assert "Ready=False" in results["health"]
    assert "Ready=True" in results["rollback"]
    assert "plainround/web:1.0.0" in results["rollback"]
```

- Three tests, each reading from the dictionary: Flux reverted the drift (`replicas 5 -> 2`, `hacked -> hello`); Flux left a deleted object until pruning was turned on (`ConfigMap present`, `Ready=True`, then `gone after spec.prune=true`); Flux reported `Ready=False` for the unhealthy rollout, and `Ready=True` with image `plainround/web:1.0.0` after the revert.

#### `tests/unit/test_shell.py`

```python
from __future__ import annotations

import pytest

from tests.support.shell import CommandError, run


def test_run_returns_output_and_status() -> None:
    result = run(["sh", "-c", "echo out; echo err >&2; exit 0"])

    assert (result.returncode, result.stdout, result.stderr) == (0, "out\n", "err\n")
    assert result.output == "out\nerr\n"
```

- Test 1 runs `sh -c "echo out; echo err >&2; exit 0"`, a tiny shell program that prints one line to each output stream and exits with 0. The assert compares a triple: exit code `0`, standard output `"out\n"`, standard error `"err\n"`. `result.output` must be the two joined.

```python
def test_a_failing_command_raises_with_its_output() -> None:
    with pytest.raises(CommandError) as raised:
        run(["sh", "-c", "echo broken >&2; exit 3"])

    assert raised.value.result.returncode == 3
    assert "broken" in str(raised.value)
```

- Test 2: `with pytest.raises(CommandError) as raised:` says "an error of this kind **must** happen inside this block; the test fails if it does not". The command exits with code 3. Afterwards the test checks the error carries the result (exit code 3) and that its text contains `broken`.

```python
def test_check_false_returns_the_failure_instead_of_raising() -> None:
    assert run(["sh", "-c", "exit 4"], check=False).returncode == 4
```

- Test 3: with `check=False` no error is raised; the exit code `4` comes back.

```python
def test_a_command_that_runs_too_long_is_reported_as_timed_out() -> None:
    with pytest.raises(CommandError, match=r"timed out after 0\.2s"):
        run(["sleep", "5"], timeout=0.2)
```

- Test 4: `sleep 5` with a timeout of `0.2` seconds must raise `CommandError` whose message matches the pattern `timed out after 0\.2s` (the backslash makes the dot a literal dot in the regular expression).

#### `tests/unit/test_waiting.py`

```python
from __future__ import annotations

import pytest

from tests.support.shell import CommandError, CommandResult
from tests.support.waiting import WaitTimeout, wait_until

```

- Imports, including the real `wait_until` and `WaitTimeout`.

```python
class FakeClock:
    """A clock that only moves when the code sleeps."""

    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now

    def sleep(self, seconds: float) -> None:
        self.now += seconds
```

- `FakeClock` is a clock that moves only when the code sleeps. `__call__` makes an object callable like a function (`clock()` returns `now`); `sleep` adds the seconds to `now`. With it, the test passes `clock=clock, sleep=clock.sleep`, and no real time passes.

```python
def test_returns_the_probe_value_as_soon_as_it_is_truthy() -> None:
    clock = FakeClock()
    answers = iter([None, False, "ready"])

    value = wait_until("the answer", lambda: next(answers), timeout=30, interval=2, clock=clock, sleep=clock.sleep)

    assert value == "ready"
    assert clock.now == 4.0
```

- `iter([None, False, "ready"])` makes an iterator; `next(answers)` returns the next item each call. The probe answers "nothing", "no", then "ready". With an interval of 2 seconds, `wait_until` must return `"ready"` after two sleeps: the fake clock must read `4.0`.

```python
def test_a_failing_command_counts_as_not_yet() -> None:
    clock = FakeClock()
    calls = {"count": 0}

    def probe() -> bool:
        calls["count"] += 1
        if calls["count"] < 3:
            raise CommandError(CommandResult(("kubectl", "get"), 1, "", "NotFound"))
        return True

    assert wait_until("the object", probe, timeout=30, interval=1, clock=clock, sleep=clock.sleep) is True
    assert calls["count"] == 3
```

- A probe that fails with `CommandError` twice, then returns True. The test shows a failing command counts as "not yet": `wait_until` returns `True` and the probe was called exactly three times. `calls = {"count": 0}` is a dictionary used as a counter that the inner function can change.

```python
def test_times_out_and_says_what_it_last_saw() -> None:
    clock = FakeClock()

    with pytest.raises(WaitTimeout, match=r"timed out after 10s waiting for the sync: the probe returned False"):
        wait_until("the sync", lambda: False, timeout=10, interval=3, clock=clock, sleep=clock.sleep)

    assert clock.now >= 10
```

- A probe that is always False with a 10-second timeout: `pytest.raises(WaitTimeout, match=…)` demands the message `timed out after 10s waiting for the sync: the probe returned False`. The clock must have passed 10 seconds.

```python
def test_a_bug_in_the_probe_is_not_swallowed() -> None:
    clock = FakeClock()

    def probe() -> bool:
        raise KeyError("status")

    with pytest.raises(KeyError):
        wait_until("anything", probe, timeout=10, clock=clock, sleep=clock.sleep)
```

- A probe that raises `KeyError` (a bug in the test, not a `CommandError`) must **not** be swallowed: `wait_until` lets it escape and the test expects exactly that.

#### `tests/unit/test_kube.py`

```python
from __future__ import annotations

import json
from collections.abc import Sequence
from typing import Any

from tests.support.kube import Kube
from tests.support.shell import CommandError, CommandResult

```

- Imports for the fake and the objects.

```python
class FakeKubectl:
    """Answers kubectl calls from a table of canned JSON, and records each command line."""

    def __init__(self, objects: dict[str, dict[str, Any]], raw: str = "") -> None:
        self.objects = objects
        self.raw = raw
        self.commands: list[Sequence[str]] = []

    def __call__(self, args: Sequence[str], *, check: bool = True, timeout: float = 0) -> CommandResult:
        self.commands.append(args)
        if "--raw" in args:
            return CommandResult(tuple(args), 0, self.raw + "\n", "")
        key = f"{args[args.index('get') + 1]}/{args[args.index('get') + 2]}"
        if key in self.objects:
            return CommandResult(tuple(args), 0, json.dumps(self.objects[key]), "")
        result = CommandResult(tuple(args), 1, "", "NotFound")
        if check:
            raise CommandError(result)
        return result
```

- `FakeKubectl` is a fake runner. It stores a table of canned objects (`objects`) and a text for `--raw` calls, and records every command line in `self.commands`. When called, it looks at the arguments: for a raw request it returns the canned text; otherwise it builds the key `kind/name` from the words after `get` (`args.index('get')` finds the position of `get`), and, if the key is in the table, returns that object as JSON text (`json.dumps`). For an unknown object it behaves like a failing `kubectl`: exit code 1 and `NotFound`, and raises `CommandError` if `check` is true.

```python
APPLICATION = {
    "spec": {"syncPolicy": {"automated": {"selfHeal": True, "prune": False}}},
    "status": {
        "sync": {"status": "Synced", "revision": "abc123"},
        "health": {"status": "Healthy"},
        "operationState": {"phase": "Succeeded", "message": "successfully synced"},
        "history": [{"revision": "aaa111"}, {"revision": "abc123"}],
    },
}
DEPLOYMENT = {
    "metadata": {"managedFields": [{"manager": "argocd-controller"}, {"manager": "kube-controller-manager"}]},
    "spec": {"replicas": 3, "template": {"spec": {"containers": [{"image": "plainround/web:1.0.0"}]}}},
}
CONFIGMAP = {"data": {"GREETING": "hello"}}


def kube_with(raw: str = "") -> tuple[Kube, FakeKubectl]:
    fake = FakeKubectl(
        {"application/web": APPLICATION, "deployment/web": DEPLOYMENT, "configmap/web-config": CONFIGMAP}, raw
    )
    return Kube("kind-test", runner=fake), fake
```

- Three canned objects are described as plain dictionaries: an Argo CD Application (synced, healthy, two history entries, self-heal on, prune off), a Deployment (3 replicas, one image, two field managers) and a ConfigMap. `kube_with` builds a `Kube` that uses the fake instead of the real `kubectl`.

```python
def test_application_state_is_read_from_status_and_spec() -> None:
    kube, _ = kube_with()

    state = kube.application("web")

    assert (state.sync_status, state.health_status, state.revision) == ("Synced", "Healthy", "abc123")
    assert state.history_revisions == ("aaa111", "abc123")
    assert state.self_heal is True
    assert state.prune is False
    assert state.operation_phase == "Succeeded"
```

- The application state is read correctly from `status` and `spec`: all the fields.

```python
def test_an_application_without_status_reads_as_empty_strings() -> None:
    fake = FakeKubectl({"application/web": {"spec": {}}})

    state = Kube("kind-test", runner=fake).application("web")

    assert (state.sync_status, state.health_status, state.history_revisions) == ("", "", ())
    assert state.self_heal is False
```

- An Application with no `status` at all reads as empty strings and an empty tuple, with self-heal False: the defensive `.get` calls work.

```python
def test_deployment_and_configmap_fields() -> None:
    kube, _ = kube_with()

    assert kube.deployment_replicas("web", "web") == 3
    assert kube.deployment_image("web", "web") == "plainround/web:1.0.0"
    assert kube.configmap_value("web", "web-config", "GREETING") == "hello"
    assert kube.field_managers("deployment", "web", "web") == {"argocd-controller", "kube-controller-manager"}
```

- The Deployment and ConfigMap helpers return the right replica count, image, value and manager set.

```python
def test_exists_is_false_for_a_missing_object_and_true_for_a_present_one() -> None:
    kube, _ = kube_with()

    assert kube.exists("configmap", "web-config", "web") is True
    assert kube.exists("configmap", "gone", "web") is False
```

- `exists` is True for a present object and False for a missing one (`is True` / `is False` test the exact values).

```python
def test_every_command_is_pinned_to_the_context() -> None:
    kube, fake = kube_with(raw="hello")

    assert kube.get_through_service("web", "web") == "hello"
    kube.deployment_replicas("web", "web")

    assert all(command[:3] == ["kubectl", "--context", "kind-test"] for command in fake.commands)
    assert "/api/v1/namespaces/web/services/web:80/proxy/" in fake.commands[0]
```

- Every command begins with `kubectl --context kind-test` (the pin), and the proxy address of the Service call is the expected path. `all(… for command in fake.commands)` is true only if the test holds for every recorded command; `command[:3]` is the first three items.

#### `tests/unit/test_manifests.py`

```python
"""Offline checks of the desired-state tree: what the base declares and what the project pins."""

from __future__ import annotations

import re
from pathlib import Path
from typing import Any

import pytest
import yaml

from tests.support.shell import run

OVERLAY = "manifests/apps/web/overlays/local"
```

- `re` is Python's regular-expression module (text patterns). `yaml` reads YAML files into dictionaries. `OVERLAY` is the folder tested.

```python
def render(root: Path, overlay: str = OVERLAY) -> dict[tuple[str, str], dict[str, Any]]:
    """Render an overlay with kustomize and index the objects by (kind, name)."""
    output = run(["kubectl", "kustomize", str(root / overlay)]).stdout
    documents = [doc for doc in yaml.safe_load_all(output) if doc]
    return {(doc["kind"], doc["metadata"]["name"]): doc for doc in documents}
```

- `render` builds the overlay with `kubectl kustomize` (the real build Argo CD runs), parses the YAML output (`yaml.safe_load_all` yields one dictionary per YAML document; `if doc` skips empty ones) and returns a dictionary keyed by `(kind, name)`.

```python
@pytest.fixture(scope="module")
def objects(root: Path) -> dict[tuple[str, str], dict[str, Any]]:
    return render(root)
```

- A module-scoped fixture renders once and shares the result.

```python
def test_the_overlay_renders_the_four_objects_of_the_lesson(
    objects: dict[tuple[str, str], dict[str, Any]],
) -> None:
    assert set(objects) == {
        ("Namespace", "web"),
        ("ConfigMap", "web-config"),
        ("Deployment", "web"),
        ("Service", "web"),
    }
```

- The overlay must contain exactly four objects: Namespace `web`, ConfigMap `web-config`, Deployment `web`, Service `web`. Comparing two **sets** ignores order.

```python
def test_the_app_starts_with_two_replicas_and_the_greeting_hello(
    objects: dict[tuple[str, str], dict[str, Any]],
) -> None:
    assert objects[("Deployment", "web")]["spec"]["replicas"] == 2
    assert objects[("ConfigMap", "web-config")]["data"] == {"GREETING": "hello"}
```

- The Deployment starts with two replicas and the ConfigMap has exactly `{"GREETING": "hello"}`.

```python
def test_the_overlay_pins_the_application_image_by_version(
    objects: dict[tuple[str, str], dict[str, Any]],
) -> None:
    container = objects[("Deployment", "web")]["spec"]["template"]["spec"]["containers"][0]

    assert container["image"] == "plainround/web:1.0.0"
```

- The image is pinned to the version `plainround/web:1.0.0`: the Kustomize `images` setting works.

```python
def test_the_container_runs_unprivileged_with_limits_and_probes(
    objects: dict[tuple[str, str], dict[str, Any]],
) -> None:
    pod = objects[("Deployment", "web")]["spec"]["template"]["spec"]
    container = pod["containers"][0]

    assert pod["securityContext"]["runAsNonRoot"] is True
    assert container["securityContext"]["readOnlyRootFilesystem"] is True
    assert container["securityContext"]["allowPrivilegeEscalation"] is False
    assert container["securityContext"]["capabilities"]["drop"] == ["ALL"]
    assert {"requests", "limits"} <= set(container["resources"])
    assert {"readinessProbe", "livenessProbe"} <= set(container)
```

- Security checks: the pod must not run as root; the container's root file system is read-only; privilege escalation is off; all Linux capabilities are dropped; resource requests and limits exist; both probes exist. `{"requests", "limits"} <= set(container["resources"])` asks "is the left set contained in the right?".

```python
def test_the_namespace_enforces_the_restricted_pod_security_level(
    objects: dict[tuple[str, str], dict[str, Any]],
) -> None:
    labels = objects[("Namespace", "web")]["metadata"]["labels"]

    assert labels["pod-security.kubernetes.io/enforce"] == "restricted"
```

- The namespace carries the label that makes Kubernetes enforce the `restricted` Pod Security level.

```python
def test_the_application_has_an_explicit_automated_block(root: Path) -> None:
    application = yaml.safe_load((root / "manifests/clusters/local/application.yaml").read_text())

    assert application["spec"]["syncPolicy"]["automated"] == {"prune": False, "selfHeal": False}
    assert application["spec"]["source"]["path"] == "apps/web/overlays/local"
```

- The Argo CD Application starts with prune and self-heal off and reads the overlay path.

```python
def test_the_project_only_allows_this_repository_and_namespace(root: Path) -> None:
    project = yaml.safe_load((root / "manifests/clusters/local/project.yaml").read_text())

    assert [destination["namespace"] for destination in project["spec"]["destinations"]] == ["web"]
    assert project["spec"]["clusterResourceWhitelist"] == [{"group": "", "kind": "Namespace"}]
```

- The project allows only the namespace `web` and only the cluster-wide kind `Namespace`.

```python
def test_the_argo_cd_version_in_the_kustomization_matches_versions_env(root: Path) -> None:
    pinned = re.search(r"argo-cd/(v[\d.]+)/", (root / "platform/argocd/kustomization.yaml").read_text())
    versions = dict(
        line.split("=", 1)
        for line in (root / "versions.env").read_text().splitlines()
        if "=" in line and line[0] != "#"
    )

    assert pinned is not None
    assert pinned.group(1) == versions["ARGOCD_VERSION"]
```

- The Argo CD version must be written the same in two places. `re.search(r"argo-cd/(v[\d.]+)/", text)` finds the tag in the Kustomize file (`r"…"` is a raw string, so backslashes are kept; `\d` is a digit; the parentheses capture a part, read with `.group(1)`). The second part reads `versions.env`: it turns each `KEY=value` line into a pair with `line.split("=", 1)` and builds a dictionary with `dict(…)`, skipping comment lines (`line[0] != "#"`). Then it compares the two.

```python
def test_every_image_the_manifests_use_is_pinned_to_a_version(root: Path) -> None:
    text = "".join(path.read_text() for path in (root / "manifests").rglob("*.yaml"))
    text += (root / "platform/git-server/git-server.yaml").read_text()
    images = re.findall(r"^\s*image:\s*(\S+)", text, flags=re.MULTILINE)

    assert images, "expected at least one image reference"
    assert all(":" in image and not image.endswith(":latest") for image in images)
```

- Every `image:` in every manifest must be pinned to a version (contains `:` and does not end in `:latest`). `rglob("*.yaml")` finds all YAML files below a folder; `re.findall(…, flags=re.MULTILINE)` finds every line of the form `image: something`; the final assert lists the rule as a Python expression.

#### `tests/unit/test_validate_script.py`

```python
"""scripts/validate.sh is the gate for 'a bad manifest is refused'; prove it can say no."""

from __future__ import annotations

import shutil
from pathlib import Path

import pytest

from tests.support.shell import run

pytestmark = pytest.mark.skipif(shutil.which("kubeconform") is None, reason="kubeconform is not installed")

```

- `shutil` is Python's file-copy helper. `pytestmark = pytest.mark.skipif(shutil.which("kubeconform") is None, reason=…)` skips every test in this file if the `kubeconform` program is not installed (`shutil.which` finds a program on the `PATH`).

```python
def copy_tree(root: Path, target: Path) -> Path:
    shutil.copytree(root / "manifests", target)
    return target
```

- `copy_tree` copies the `manifests` folder to a target so a test can damage the copy, not the original.

```python
def test_the_shipped_manifests_pass(root: Path, tmp_path: Path) -> None:
    result = run([str(root / "scripts/validate.sh"), str(copy_tree(root, tmp_path / "ok"))], check=False)

    assert result.returncode == 0, result.output
```

- The shipped manifests pass: the script exits with 0. `tmp_path` is a built-in fixture giving a fresh temporary folder.

```python
def test_a_string_where_a_number_belongs_is_refused(root: Path, tmp_path: Path) -> None:
    tree = copy_tree(root, tmp_path / "string-replicas")
    deployment = tree / "apps/web/base/deployment.yaml"
    deployment.write_text(deployment.read_text().replace("replicas: 2", 'replicas: "many"'))

    result = run([str(root / "scripts/validate.sh"), str(tree)], check=False)

    assert result.returncode != 0
    assert "replicas" in result.output
```

- A string where a number belongs: replace `replicas: 2` with `replicas: "many"` in the copy; the script must fail and mention `replicas`.

```python
def test_an_unknown_field_is_refused(root: Path, tmp_path: Path) -> None:
    tree = copy_tree(root, tmp_path / "unknown-field")
    deployment = tree / "apps/web/base/deployment.yaml"
    deployment.write_text(deployment.read_text().replace("  replicas: 2", "  replicas: 2\n  replica_count: 3"))

    result = run([str(root / "scripts/validate.sh"), str(tree)], check=False)

    assert result.returncode != 0
    assert "replica_count" in result.output
```

- An unknown field: add `replica_count: 3`; the strict check must refuse it by name.

```python
def test_an_application_with_a_misspelled_field_is_refused(root: Path, tmp_path: Path) -> None:
    tree = copy_tree(root, tmp_path / "bad-application")
    application = tree / "clusters/local/application.yaml"
    application.write_text(application.read_text().replace("selfHeal", "selfHeel"))

    result = run([str(root / "scripts/validate.sh"), str(tree)], check=False)

    assert result.returncode != 0
```

- A misspelled field in the Argo CD Application (`selfHeel`): the check against the Argo CD rules must fail.
<!-- full-walkthrough:end -->

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
