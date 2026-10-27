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
