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
