# Python

## 1. What it is

Python is a general-purpose programming language. In this repository it is used for the **tests** and the small helpers behind them, not for the application itself. Version 3.12 or newer is required.

## 2. Why this repository uses it

The tests (offline and cluster) and the typed helpers behind them are Python. They call the same scripts a person runs, so the tests prove the scripts work.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `tests/support/shell.py` | run a command and return a typed result, or raise a named error |
| `tests/support/waiting.py` | `wait_until`: poll with an injected clock and sleep |
| `tests/support/kube.py` | `Kube`: kubectl pinned to one context, with typed reads of Argo CD's Application |
| `tests/conftest.py, tests/cluster/conftest.py` | pytest fixtures: root, cluster name, `kube`, `runbook` |
| `tests/unit/, tests/cluster/, tests/compare/` | the test modules |

## 4. How it works underneath

- `python script.py` starts the interpreter, which compiles the file to bytecode in memory and runs it. A **module** is one `.py` file; a **package** is a folder of modules (with `__init__.py`).
- **Type hints** (`def f(x: int) -> str`) are labels for people and for checkers such as mypy. Python does not enforce them when it runs.
- A **dataclass** (`@dataclass(frozen=True)`) generates `__init__` and comparison methods for a class that is just named fields; `frozen` makes it read-only.
- `from __future__ import annotations` stores hints as text so they can refer to names defined later.
- A **context manager** (`with ...:`) runs set-up and clean-up around a block. A **generic function** such as `def wait_until[T](...)` (Python 3.12 syntax) works for any type `T` and returns the same type it was given.
- `subprocess.run([...])` starts another program and captures its output. A list of arguments (not one string) avoids shell-quoting mistakes.

## 5. Walkthrough of this repository's use

### `tests/support/shell.py`
```python
@dataclass(frozen=True)
class CommandResult:
    args: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str

    @property
    def output(self) -> str:
        return self.stdout + self.stderr
```
A read-only record of one finished command. `@property` makes `output` readable like a field.

```python
class CommandError(RuntimeError):
    def __init__(self, result: CommandResult) -> None:
        self.result = result
        super().__init__(f"{command!r} exited {result.returncode}\n{result.output.strip()}")
```
A named error that carries the whole result, so a failing test shows what the command printed. `!r` prints the string with quotes.

```python
def run(args, *, cwd=None, env=None, check=True, timeout=300) -> CommandResult:
    try:
        completed = subprocess.run(list(args), cwd=cwd, ..., capture_output=True, text=True, timeout=timeout, check=False)
    except subprocess.TimeoutExpired as expired:
        ...
        raise CommandError(result) from expired
```
The `*` makes everything after it keyword-only. `capture_output=True, text=True` returns output as strings. `check=False` stops `subprocess` raising by itself; the function raises its own `CommandError` when `check` is set. A timeout becomes exit code 124 (the same code the `timeout` command uses).

### `tests/support/waiting.py`
```python
def wait_until[T](description, probe, *, timeout, interval=2.0, clock=time.monotonic, sleep=time.sleep) -> T:
```
`[T]` is Python 3.12 generic syntax: whatever type the probe returns is what `wait_until` returns. `clock` and `sleep` are parameters with real defaults, so a test passes fake ones and finishes instantly. The loop calls the probe, returns on a truthy value, treats `CommandError` as "not yet" (the object may not exist yet), and raises `WaitTimeout(AssertionError)` at the deadline with the last problem in the message.

### `tests/support/kube.py`
`ApplicationState` is a frozen dataclass of the fields the tests assert on. `Kube.__init__(self, context, runner=run)` takes the command runner as a parameter (**dependency injection**), so unit tests give it a fake. `Kube.kubectl` always inserts `--context`. `Kube.application()` reads `status` and `spec.syncPolicy.automated` from the JSON with `.get(key, default)` so a missing field becomes an empty value, not a crash. `get_through_service` reads a Service through the API server's proxy URL, so no port-forward is needed.

### The conftest files
`pytest_collection_modifyitems` adds the `cluster` marker to every test under `tests/cluster`. `context_of` finds `k3d-<name>` or `kind-<name>` in `kubectl config get-contexts -o name`. `Runbook.script("reset.sh")` runs `scripts/reset.sh` from the repository root: the tests use the same scripts a person uses.

<!-- full-walkthrough:begin -->
### 5.A Full walkthrough: every line of the Python helpers (`tests/support/`)

This part follows the files one by one. If you have never programmed, read the small primer first.

**A Python primer for these files.**
- A Python file is a list of statements that run from top to bottom. A line that starts with `#` is a comment. A text in three quotes `"""…"""` at the very top of a file, class or function is a **docstring**: a description for people that Python keeps attached to the thing.
- `import name` makes the code of another file available. `from package import thing` imports one item from it. A **module** is one `.py` file. A **package** is a folder of modules (`tests/support/` is one).
- A **function** is a named recipe: `def name(arguments):` followed by indented lines. Everything indented under it belongs to it (Python uses indentation, not braces). `return value` hands a value back.
- A **type hint** writes the kind of value after a name: `name: str` says "name is text", `-> int` says "this function returns a whole number". Python does not check hints when it runs; a separate tool (mypy) reads them before. Common kinds: `str` text, `int` whole number, `float` number with a fraction, `bool` True/False, `list[str]` a list of texts, `dict[str, int]` a table from texts to numbers, `tuple[str, ...]` a fixed list of texts of any length, `X | None` "an X or nothing".
- A **class** groups data and functions: `class Name:`. A function inside a class is a **method**; its first parameter `self` is the object it works on. `__init__` runs when you create an object.
- An **exception** is how Python reports an error. `raise Something(...)` raises one. `try: … except Something as name: …` catches it. A class can inherit from another: `class MyError(RuntimeError)` makes a new kind of error.
- An **f-string** is text with values inserted: `f"exited {code}"`. A **list comprehension** builds a list: `[x for x in items if x]`.
- A **dictionary** (`dict`) maps keys to values: `{"a": 1}`. `d.get("a", 0)` reads a key and returns 0 if it is missing.
- A **lambda** is a tiny unnamed function: `lambda: 5`.

#### `tests/support/__init__.py`

```python
"""Helpers the tests share: running commands, waiting for a condition, reading the controller's state."""
```

A file named `__init__.py` marks a folder as a Python package, so `from tests.support.kube import Kube` works. The only line is the docstring that says what the package holds.

#### `tests/support/shell.py`: run a program and report what it did

When a test needs to run another program (for example one of the repository's scripts), it should get back the exit code and the output, and get a clear error if the program failed. This file does that.

```python
"""Run external commands and report what they did, with typed results and a named error."""

from __future__ import annotations

import subprocess
from collections.abc import Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path

```

- Line 1 is the module's docstring.
- `from __future__ import annotations` tells Python to keep type hints as plain text instead of evaluating them at once. That lets a hint mention a class defined later in the file.
- `import subprocess` loads Python's own module for starting other programs. A **subprocess** is a child process (see the Bash note).
- `from collections.abc import Mapping, Sequence` imports two names used only in type hints: a `Mapping` is anything that behaves like a dictionary, a `Sequence` is anything that behaves like a list.
- `from dataclasses import dataclass` imports a helper described just below.
- `from pathlib import Path` imports the `Path` class: an object that stands for a file or folder path.

```python
@dataclass(frozen=True)
class CommandResult:
    """The outcome of one finished command."""

    args: tuple[str, ...]
    returncode: int
    stdout: str
    stderr: str

    @property
    def output(self) -> str:
        """Standard output and standard error together, the way a terminal shows them."""
        return self.stdout + self.stderr

```

- `@dataclass(frozen=True)` is a **decorator**: a line starting with `@` that changes the class right below it. `dataclass` writes the boring parts of a class for you (the `__init__` method and a readable printout) from the list of fields. `frozen=True` makes objects **read-only** after they are created, so a result cannot be changed by mistake.
- `class CommandResult:` and its docstring: a class that holds the outcome of one finished command.
- The four lines `args`, `returncode`, `stdout`, `stderr` declare the **fields**: the command words (`tuple[str, ...]`), its exit code, what it printed on standard output, and what it printed on standard error (see the Bash note for these).
- `@property` turns the next method into something you read without parentheses (`result.output`). `output` returns the two texts joined, "the way a terminal shows them". The docstring inside the method says so.

```python
class CommandError(RuntimeError):
    """A command exited with a non-zero status (or did not finish in time)."""

    def __init__(self, result: CommandResult) -> None:
        """Keep the whole result so the test report shows what the command printed."""
        self.result = result
        command = " ".join(result.args)
        super().__init__(f"{command!r} exited {result.returncode}\n{result.output.strip()}")

```

- `class CommandError(RuntimeError)` creates a new kind of error that is a special case of `RuntimeError`. A named error lets a caller catch exactly this problem.
- `__init__(self, result)` runs when the error is created. It stores the whole result (`self.result = result`) so a test report can show what the command printed.
- `" ".join(result.args)` joins the command words with spaces into one line.
- `super().__init__(…)` calls the parent class's `__init__` with the error message. The message is an f-string: `{command!r}` inserts the command text with quotes around it (`!r` = "show it the way Python would write it in code"), `{result.returncode}` its exit code, `\n` a line break, and `result.output.strip()` the command's output without leading or trailing blank space.

```python
def run(
    args: Sequence[str],
    *,
    cwd: Path | None = None,
    env: Mapping[str, str] | None = None,
    check: bool = True,
    timeout: float = 300,
) -> CommandResult:
    """Run ``args`` and return the result; raise CommandError on a non-zero exit when ``check`` is set."""
```

- The function `run` has a long list of parameters, one per line. `args: Sequence[str]` is the command words. The lone `*` means everything after it **must be given by name** (`run(cmd, check=False)`), which makes calls readable.
- `cwd: Path | None = None` is the folder to run in, or nothing (`= None` is the default). `env: Mapping[str, str] | None = None` replaces the environment variables (see the Bash note), or nothing. `check: bool = True` says "treat a non-zero exit code as an error". `timeout: float = 300` is the longest time to wait, in seconds.
- `-> CommandResult` says what it returns. The docstring explains the behavior.

```python
    try:
        completed = subprocess.run(
            list(args),
            cwd=cwd,
            env=None if env is None else dict(env),
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
```

- `try:` starts a block where an error may happen.
- `subprocess.run(…)` starts the program and waits for it to finish. `list(args)` copies the command words into a list. A list (not one long string) means each word is one argument and nothing is split or re-interpreted by a shell.
- `cwd=cwd` runs it in that folder. `env=None if env is None else dict(env)` uses the normal environment unless one was given (a conditional expression: `A if condition else B`).
- `capture_output=True` collects what the program prints instead of showing it. `text=True` gives text instead of raw bytes. `timeout=timeout` stops waiting after that time. `check=False` stops `subprocess` from raising an error by itself; this function does its own error handling.

```python
    except subprocess.TimeoutExpired as expired:
        stdout = expired.stdout.decode() if isinstance(expired.stdout, bytes) else (expired.stdout or "")
        result = CommandResult(tuple(args), 124, stdout, f"timed out after {timeout}s")
        raise CommandError(result) from expired
```

- `except subprocess.TimeoutExpired as expired:` runs if the program took longer than the timeout. The caught error is named `expired`.
- `expired.stdout` holds whatever the program printed before it was stopped. It may be raw bytes, text or nothing; the next line converts it to text: `decode()` turns bytes into text; `isinstance(x, bytes)` asks "is x bytes?"; `(expired.stdout or "")` means "the value, or empty text if there is none".
- A timeout is turned into a normal `CommandResult` with exit code `124` (the number the Unix `timeout` command uses) and the message `timed out after …s`, and then raised as a `CommandError`. `raise … from expired` keeps the original error attached as the cause.

```python
    result = CommandResult(tuple(args), completed.returncode, completed.stdout, completed.stderr)
    if check and result.returncode != 0:
        raise CommandError(result)
    return result
```

- If nothing went wrong, build a `CommandResult` from what `subprocess.run` returned (`completed.returncode`, `.stdout`, `.stderr`).
- `if check and result.returncode != 0:` means "if the caller wants errors and the exit code is not 0", then raise `CommandError`. Otherwise `return result` hands the result back.

#### `tests/support/waiting.py`: wait until something becomes true

A cluster does things in its own time. A test cannot say "do it, then check at once"; it must **wait** until the condition holds, but not forever. This function waits with a limit, and its clock and sleep can be replaced, so a test of the waiting itself needs no real waiting.

```python
"""Poll until a condition holds, with the clock and the sleep injected so the logic is testable."""

from __future__ import annotations

import time
from collections.abc import Callable

from tests.support.shell import CommandError


class WaitTimeout(AssertionError):
    """The condition did not hold within the time allowed."""

```

- The docstring says what the module does. `import time` loads the time functions. `from collections.abc import Callable` imports the hint for "something you can call like a function". `from tests.support.shell import CommandError` imports the error defined above.
- `class WaitTimeout(AssertionError)` is a new error for "waited too long". It inherits from `AssertionError`, the error a failed `assert` raises, so a test runner reports it as a test failure.

```python
def wait_until[T](
    description: str,
    probe: Callable[[], T | None | bool],
    *,
    timeout: float,
    interval: float = 2.0,
    clock: Callable[[], float] = time.monotonic,
    sleep: Callable[[float], None] = time.sleep,
) -> T:
    """Call ``probe`` until it returns something truthy and return that value.

    A probe may raise CommandError (for example ``kubectl get`` on an object that does not exist yet);
    that counts as "not yet". Any other exception is a bug in the test and propagates.
    """
```

- `def wait_until[T](` uses Python 3.12 **generic** syntax. `[T]` declares a placeholder type: whatever type the probe returns is the type this function returns. A generic function works for many types while staying checkable.
- `description: str` names what we wait for. `probe: Callable[[], T | None | bool]` is a function that takes no arguments and returns a value, nothing or a bool. `*` makes the rest keyword-only. `timeout: float` is the limit in seconds; `interval: float = 2.0` the pause between tries.
- `clock: Callable[[], float] = time.monotonic` and `sleep: Callable[[float], None] = time.sleep` are the **replaceable parts**. `time.monotonic` is a clock that only moves forward and cannot jump (unlike the wall clock). `time.sleep` pauses. A test passes fakes here.
- The docstring explains the rule for errors: a `CommandError` inside the probe (for example `kubectl get` for an object that does not exist yet) counts as "not yet"; any other error is a bug in the test and goes up.

```python
    deadline = clock() + timeout
    last_problem = "the probe returned a falsy value"
    while True:
        try:
            value = probe()
            if value:
                return value  # type: ignore[return-value]
            last_problem = f"the probe returned {value!r}"
        except CommandError as error:
            last_problem = str(error).splitlines()[0]
        if clock() >= deadline:
            raise WaitTimeout(f"timed out after {timeout:g}s waiting for {description}: {last_problem}")
        sleep(interval)
```

- `deadline = clock() + timeout` fixes the time at which to give up. `last_problem` remembers why the last try failed, for the final message.
- `while True:` loops forever until `return` or `raise` leaves it.
- Inside `try:`, `value = probe()` calls the probe. `if value:` is true for any "truthy" value (not `None`, `False`, `0`, empty); then `return value` ends the function and returns it. The comment `# type: ignore[return-value]` tells the type checker to skip this one line, because it cannot prove that a truthy `T | None | bool` is a `T`.
- If the value was falsy, remember that (`last_problem = f"the probe returned {value!r}"`).
- `except CommandError as error:` treats a failing command as "not yet" and remembers the first line of its message (`str(error).splitlines()[0]`).
- After each try, `if clock() >= deadline:` raises `WaitTimeout` with a message such as `timed out after 60s waiting for the app: …` (`{timeout:g}` prints the number without extra zeros). Otherwise `sleep(interval)` pauses before the next try.

#### `tests/support/kube.py`: read the cluster through `kubectl`

`kubectl` prints Kubernetes objects as **JSON**, a text format for structured data: `{"name": "web", "ports": [80, 443]}` is an object (curly braces, named values) containing a list (square brackets). Python turns that text into dictionaries and lists with `json.loads`. This file wraps the commands tests need.

```python
"""A small read-mostly view of the cluster and of Argo CD's Application, through kubectl."""

from __future__ import annotations

import json
from collections.abc import Callable, Sequence
from dataclasses import dataclass
from typing import Any

from tests.support.shell import CommandResult, run

```

- The docstring says what it is. The imports: `json` (read and write JSON), `Callable` and `Sequence` (type hints), `dataclass`, `Any` (a hint that means "any kind of value"), and the `CommandResult` class and `run` function from `shell.py`.

```python
@dataclass(frozen=True)
class ApplicationState:
    """What the controller reports about one Application."""

    sync_status: str
    health_status: str
    revision: str
    operation_phase: str
    operation_message: str
    history_revisions: tuple[str, ...]
    self_heal: bool
    prune: bool

```

- A frozen dataclass `ApplicationState` holds what Argo CD reports about one Application. Each line is a field with its type. `history_revisions: tuple[str, ...]` is the list of commit hashes Argo CD has deployed, kept as a read-only tuple. `self_heal` and `prune` are the two switches of the sync policy as True/False.

```python
class Kube:
    """kubectl pinned to one context, so a test can never touch another cluster."""

    def __init__(
        self,
        context: str,
        runner: Callable[..., CommandResult] = run,
    ) -> None:
        """Remember the kubectl context (for kind ``kind-<cluster>``); ``runner`` is replaceable in tests."""
        self.context = context
        self._runner = runner
```

- `class Kube` is `kubectl` pinned to one cluster, "so a test can never touch another cluster".
- `__init__` takes `context` (the `kubectl` context name) and `runner`, the function used to run commands. Its default is `run` from `shell.py`. **Passing the function in as a parameter** is called **dependency injection**: the unit tests pass a fake, so they can test this class with no cluster. `Callable[..., CommandResult]` means "any function that returns a `CommandResult`". The leading underscore in `self._runner` is a convention for "internal".

```python
    def kubectl(self, *args: str, check: bool = True) -> CommandResult:
        """Run kubectl against this context."""
        command: Sequence[str] = ["kubectl", "--context", self.context, *args]
        return self._runner(command, check=check, timeout=120)
```

- `kubectl(self, *args, check=True)` runs `kubectl` against the pinned context. `*args: str` collects any number of text arguments into a tuple. `["kubectl", "--context", self.context, *args]` builds the command list; the `*args` inside the list spreads the tuple into it. `timeout=120` limits each call to two minutes.

```python
    def get(self, kind: str, name: str, namespace: str | None = None) -> dict[str, Any]:
        """Return one object as parsed JSON; raises CommandError when it does not exist."""
        scope = ["-n", namespace] if namespace else []
        parsed: dict[str, Any] = json.loads(self.kubectl("get", kind, name, *scope, "-o", "json").stdout)
        return parsed
```

- `get` fetches one object. `scope = ["-n", namespace] if namespace else []` adds the namespace flag only when a namespace was given. `self.kubectl("get", kind, name, *scope, "-o", "json")` asks for the object as JSON; `.stdout` is its output; `json.loads` turns the text into a dictionary. The variable `parsed` carries a type hint so the checker knows the shape. If the object does not exist `kubectl` fails and `CommandError` is raised.

```python
    def exists(self, kind: str, name: str, namespace: str | None = None) -> bool:
        """True when the object exists."""
        scope = ["-n", namespace] if namespace else []
        return self.kubectl("get", kind, name, *scope, check=False).returncode == 0
```

- `exists` runs the same `get` with `check=False`, so a missing object does not raise; it returns True when the exit code is 0.

```python
    def application(self, name: str) -> ApplicationState:
        """The controller's view of an Application in the ``argocd`` namespace."""
        application = self.get("application", name, "argocd")
        status = application.get("status", {})
        automated = application["spec"].get("syncPolicy", {}).get("automated", {})
        operation = status.get("operationState", {})
        return ApplicationState(
            sync_status=status.get("sync", {}).get("status", ""),
            health_status=status.get("health", {}).get("status", ""),
            revision=status.get("sync", {}).get("revision", ""),
            operation_phase=operation.get("phase", ""),
            operation_message=operation.get("message", ""),
            history_revisions=tuple(entry["revision"] for entry in status.get("history", [])),
            self_heal=bool(automated.get("selfHeal", False)),
            prune=bool(automated.get("prune", False)),
        )
```

- `application` reads the Argo CD Application in the `argocd` namespace and turns it into an `ApplicationState`. `application.get("status", {})` reads the key `status`, or an empty dictionary if it is not there yet (a new Application has no status). The next lines walk down nested dictionaries with `.get(…, {})` so that a missing level gives an empty value, not a crash: `status.get("sync", {}).get("status", "")` means "status → sync → status, or empty text".
- `tuple(entry["revision"] for entry in status.get("history", []))` is a **generator expression** inside `tuple(...)`: it builds a tuple of the commit hash of every history entry.
- `bool(automated.get("selfHeal", False))` converts to True/False, with False if the key is absent.

```python
    def deployment_replicas(self, namespace: str, name: str) -> int:
        """The replica count the Deployment currently asks for."""
        return int(self.get("deployment", name, namespace)["spec"]["replicas"])

    def deployment_image(self, namespace: str, name: str) -> str:
        """The image of the Deployment's first container."""
        return str(self.get("deployment", name, namespace)["spec"]["template"]["spec"]["containers"][0]["image"])
```

- `deployment_replicas` returns the replica count as a whole number. `deployment_image` returns the image of the first container: `["containers"][0]` is the first item of the list. `int(…)` and `str(…)` make the type exact.

```python
    def configmap_value(self, namespace: str, name: str, key: str) -> str:
        """One key of a ConfigMap."""
        return str(self.get("configmap", name, namespace)["data"][key])
```

- `configmap_value` reads one key of the ConfigMap's `data`.

```python
    def field_managers(self, kind: str, name: str, namespace: str) -> set[str]:
        """The names recorded in managedFields: who has written to this object."""
        managed = self.get(kind, name, namespace)["metadata"].get("managedFields", [])
        return {entry["manager"] for entry in managed}
```

- Kubernetes records who wrote each field in `metadata.managedFields`. This method returns the set of **manager names** (`{entry["manager"] for entry in managed}` is a **set comprehension**: a set holds each value once). A test uses it to show that the Deployment was written by Argo CD's controller and not by `kubectl`.

```python
    def get_through_service(self, namespace: str, service: str, path: str = "/") -> str:
        """GET a path of a Service through the API server's proxy (no port-forward needed)."""
        endpoint = f"/api/v1/namespaces/{namespace}/services/{service}:80/proxy{path}"
        return self.kubectl("get", "--raw", endpoint).stdout.strip()
```

- `get_through_service` fetches a web page of a Service **through the Kubernetes API server's proxy**, so no port forwarding is needed. The path `/api/v1/namespaces/<ns>/services/<service>:80/proxy<path>` is the API's address for that. `kubectl get --raw <path>` sends a raw request; `.stdout.strip()` removes the trailing line break.
<!-- full-walkthrough:end -->

## 6. Try it yourself

1. `.venv/bin/python -c "from tests.support.shell import run; print(run(['echo','hi']).stdout)"` : `hi`.
2. `.venv/bin/python -c "from tests.support.waiting import wait_until; print(wait_until('x', lambda: 7, timeout=1))"` : `7`.
3. `.venv/bin/pytest tests/unit -q` : the unit tests, no cluster needed.
4. `.venv/bin/python -c "from tests.support.shell import run; run(['false'])"` : a `CommandError` naming the command and exit code 1.
5. `.venv/bin/mypy` : strict type check of `tests/` passes.

## 7. Mistakes people make

- Installing packages into the system Python; use a virtual environment (see pip and venv).
- Mutable default arguments (`def f(x=[])`).
- Assuming type hints are checked at run time.
- Building a shell command as one string with user data inside; here the commands are lists.

## 8. Check yourself

1. Does Python check type hints when the program runs?
   *Answer:* No. A separate tool such as mypy checks them.
2. What does `frozen=True` do on a dataclass?
   *Answer:* It makes the instances read-only.
3. Why pass a list to `subprocess.run`?
   *Answer:* Each item is one argument, so no shell splitting or quoting is involved.
4. What is a module and what is a package?
   *Answer:* A module is one `.py` file; a package is a folder of modules.
5. What does `from __future__ import annotations` do?
   *Answer:* It keeps type hints as text, so they can name things defined later.

## 9. Further reading

- Python 3.13 documentation (this repository requires 3.12 or newer): <https://docs.python.org/3.13/>.
