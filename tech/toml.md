# TOML (pyproject.toml)

## 1. What it is

TOML is a simple configuration file format of `[tables]` and `key = value` lines. `pyproject.toml` is the standard file Python tools read for the project's name, dependencies and each tool's settings.

## 2. Why this repository uses it

One file configures pytest, coverage, ruff and mypy and lists the pinned Python packages.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `pyproject.toml` | project metadata, dependencies and the tool tables |

## 4. How it works underneath

- `[project]` names the project and lists `dependencies`; `[project.optional-dependencies]` groups extras such as `dev`.
- `[tool.<name>]` tables hold the settings of pytest, coverage, ruff and mypy; each tool finds its own table.
- Values are strings in quotes, numbers, booleans (`true`), and arrays (`["a", "b"]`).
- Versions written `==x.y.z` are exact.

## 5. Walkthrough of this repository's use

```toml
[project]
name = "gitops-reconcile-and-drift-tests"
requires-python = ">=3.12"
dependencies = ["pyyaml==6.0.3"]

[project.optional-dependencies]
dev = ["pytest==9.0.2", "pytest-cov==7.0.0", "ruff==0.14.10", "mypy==1.19.1", "yamllint==1.38.0", "types-PyYAML==6.0.12.20250915"]
```
The test code is a Python project (so the tools find their settings), and `requires-python` refuses older Python. `dependencies` is what runs; the `dev` list is the extra tooling. Every version is exact (`==`). The `[tool.pytest.ini_options]`, `[tool.coverage.run]`, `[tool.coverage.report]`, `[tool.ruff]`, `[tool.ruff.lint]`, `[tool.ruff.lint.per-file-ignores]` and `[tool.mypy]` tables are explained in the notes for each tool.

<!-- full-walkthrough:begin -->
### 5.A Full walkthrough: the whole `pyproject.toml`

```toml
[project]
name = "gitops-reconcile-and-drift-tests"
version = "0.1.0"
description = "Cluster and offline tests for the reconcile-and-drift GitOps project"
requires-python = ">=3.12"
dependencies = ["pyyaml==6.0.3"]

[project.optional-dependencies]
dev = ["pytest==9.0.2", "pytest-cov==7.0.0", "ruff==0.14.10", "mypy==1.19.1", "yamllint==1.38.0", "types-PyYAML==6.0.12.20250915"]

[tool.pytest.ini_options]
testpaths = ["tests"]
pythonpath = ["."]
addopts = "-ra --strict-markers"
markers = [
  "cluster: needs the kind cluster from `make up` and runs the scripted runbook against it",
  "compare: needs the Flux cluster from `make compare-up` (step 6, the other controller)",
]

[tool.coverage.run]
source = ["tests/support"]
branch = true

[tool.coverage.report]
show_missing = true
fail_under = 90

[tool.ruff]
line-length = 120
target-version = "py312"

[tool.ruff.lint]
select = ["E", "F", "I", "B", "UP", "SIM", "D", "ANN", "S", "PT", "RUF"]
ignore = ["D203", "D213"]

[tool.ruff.lint.per-file-ignores]
"tests/**" = ["S101", "S603", "S607", "D"]
"tests/support/**" = ["S101", "S603", "S607"]

[tool.mypy]
python_version = "3.12"
strict = true
files = ["tests"]
```

- **TOML** files are made of **tables**: a heading in square brackets (`[project]`) followed by `key = value` lines. A dotted heading (`[tool.pytest.ini_options]`) is a table inside a table. Values are text in quotes, numbers, `true`/`false`, or lists in square brackets.
- `[project]`: `name` and `version` identify the test package; `description` is a sentence; `requires-python = ">=3.12"` refuses older Python; `dependencies = ["pyyaml==6.0.3"]` lists the one library the code needs, at exactly that version (`==`).
- `[project.optional-dependencies]` with `dev = [...]` lists the tools used only for development: the test runner, its coverage plug-in, the linter and formatter, the type checker, the YAML checker and type information for PyYAML, each at an exact version.
- `[tool.pytest.ini_options]`: `testpaths = ["tests"]` where to look for tests; `pythonpath = ["."]` adds the repository folder to Python's search path so `tests.support…` can be imported; `addopts = "-ra --strict-markers"` options always added (`-ra` print a short reason for every non-passing test; `--strict-markers` makes an unknown marker an error); `markers = [...]` registers the two labels `cluster` and `compare` with descriptions.
- `[tool.coverage.run]`: `source = ["tests/support"]` measures only the helper code; `branch = true` also measures the two ways of every `if`. `[tool.coverage.report]`: `show_missing = true` prints the missing lines; `fail_under = 90` fails the run below 90 percent.
- `[tool.ruff]`: `line-length = 120` and `target-version = "py312"`. `[tool.ruff.lint]`: `select = [...]` turns on groups of rules by letter: E and F (errors), I (import order), B (likely bugs), UP (old syntax), SIM (simplifications), D (docstrings), ANN (missing type hints), S (security), PT (pytest style), RUF (extras). `ignore = ["D203", "D213"]` turns off two docstring rules that contradict others.
- `[tool.ruff.lint.per-file-ignores]` switches rules off for some paths: tests may use `assert` (S101) and may start programs (S603, S607), and the tests need no docstrings (D).
- `[tool.mypy]`: `python_version = "3.12"`, `strict = true` (every function must have hints) and `files = ["tests"]`.
<!-- full-walkthrough:end -->

## 6. Try it yourself

1. `python3 -c "import tomllib; print(tomllib.load(open('pyproject.toml','rb'))['project']['dependencies'])"` : `['pyyaml==6.0.3']`.
2. `grep -n '^\[' pyproject.toml` : every table header.
3. Change `fail_under` to 99 and run `make test-offline` : the coverage gate fails.
4. `.venv/bin/ruff check --show-settings . | head` : ruff's view of the settings it read.
5. `.venv/bin/pytest --help | grep -n markers` : pytest reads the markers table.

## 7. Mistakes people make

- Unquoted strings, or YAML-style `key: value`.
- Putting a setting in the wrong `[tool.*]` table, where the tool never reads it.

## 8. Check yourself

1. What is a TOML table?
   *Answer:* A `[name]` heading that groups the keys below it.
2. Where do tool settings go in `pyproject.toml`?
   *Answer:* Under `[tool.<toolname>]`.
3. What does `==6.0.3` mean?
   *Answer:* Exactly that version.
4. How is a list written?
   *Answer:* In square brackets with quoted items.
5. Which file lists the project's dependencies?
   *Answer:* `pyproject.toml`, under `[project]`.

## 9. Further reading

- TOML 1.0: <https://toml.io/en/v1.0.0>. pyproject.toml guide: <https://packaging.python.org/en/latest/guides/writing-pyproject-toml/>.
