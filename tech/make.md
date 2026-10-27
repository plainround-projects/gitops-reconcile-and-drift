# GNU Make

## 1. What it is

Make is a command-line tool that runs named recipes from a file called `Makefile`. Each recipe is a **target**. A target can list other targets or files it **depends on**, and Make runs those first. People use it as a short front door to a project: `make test` instead of remembering a long command.

## 2. Why this repository uses it

A beginner should not need to learn twenty script names. `make up`, `make run`, `make test`, `make lint` and `make down` are the whole interface, and CI calls the same targets.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `Makefile` | all targets, the virtual-environment stamp, the `help` listing |

## 4. How it works underneath

- A rule looks like `target: dependency` followed by lines that start with a **tab** character. Those lines are the recipe; Make hands each line to the shell.
- When a target is a *file name*, Make compares file times: if a dependency is newer than the target, the recipe runs again; if not, Make skips it. This is how a virtual environment is built only when its lock file changes.
- A target that is not a file (`up`, `test`) is declared `.PHONY` so Make never mistakes it for a file called `up`.
- `$(NAME)` reads a variable. `?=` sets it only if the caller did not. `:=` evaluates immediately. `$$` writes a single `$` for the shell. `$@` is the target's own name.
- A line starting with `@` is not echoed. A recipe line that fails stops the whole target.
- `## text` after a target is just a comment this repository's `help` target reads back with `grep`.

## 5. Walkthrough of this repository's use

```make
PYTHON ?= $(shell command -v python3.13 || command -v python3.12 || command -v python3)
VENV := .venv
PY := $(VENV)/bin/python
STAMP := $(VENV)/.installed
SCRIPTS := $(wildcard scripts/*.sh scripts/runbook/*.sh scripts/compare/*.sh docker/git-server/entrypoint.sh)
```
`?=` takes the caller's `PYTHON` if given, otherwise the newest Python 3.13/3.12/3 found by `command -v`. `:=` fixes the other values now. `$(wildcard ...)` expands to the list of script files that exist, which `make lint` hands to ShellCheck.

```make
.PHONY: help install up run status test ... down clean
```
Names that are commands, not files.

```make
help: ## list the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort
```
`@` hides the command line. `$(MAKEFILE_LIST)` is the file itself. `grep` picks the lines that have `## `, `sed` swaps the `:...## ` for a tab, `sort` orders them. That is the self-documenting `make help`.

```make
$(STAMP): requirements-dev.lock pyproject.toml
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install -q --require-hashes -r requirements-dev.lock
	touch $@
```
A **file target**: `.venv/.installed` depends on the lock and `pyproject.toml`. When either is newer than the stamp, Make re-runs the recipe: create the venv, install hash-checked packages, `touch $@` (`$@` = the target) to renew the stamp. `make lint` and `make test-offline` list `$(STAMP)` as a dependency, so the tools exist before they run.

```make
.env:
	cp .env.example .env
up: .env ## create the kind cluster, install Argo CD ...
	./scripts/up.sh
```
`up` depends on the file `.env`; if it is missing, Make copies the example. Then it runs the script.

```make
lint: $(STAMP)
	$(VENV)/bin/yamllint -s .
	./scripts/validate.sh
	shellcheck $(SCRIPTS)
	$(VENV)/bin/ruff check .
	$(VENV)/bin/ruff format --check .
	$(VENV)/bin/mypy
```
Six checks in order; the first failure stops `make lint`.

```make
test-offline: $(STAMP)
	$(PY) -m pytest -m "not cluster and not compare" --cov --cov-report=term-missing
compare: $(STAMP)
	./scripts/compare/flux-up.sh
	$(PY) -m pytest -m compare; status=$$?; ./scripts/compare/flux-down.sh; exit $$status
```
`compare` must delete the Flux cluster even when the tests fail, so it saves pytest's exit code in `status` (`$$?` is `$?`, the last exit code), runs `flux-down.sh`, and exits with the saved code. These three commands are on one recipe line group joined by `;` so they share one shell.

`audit` installs `pip-audit` and checks the locked packages against known-vulnerability data. `down` runs `scripts/down.sh`. `clean` removes the venv and caches with `rm -rf`.

## 6. Try it yourself

1. `make help` : a sorted list of targets with one-line descriptions.
2. `make -n lint` : `-n` prints what *would* run without running it.
3. `make install` twice : the second run prints `make: Nothing to be done` (the stamp is up to date).
4. `touch requirements-dev.lock && make -n install` : shows the environment would be rebuilt.
5. `make -p | grep '^SCRIPTS'` : shows the expanded script list.

## 7. Mistakes people make

- **Spaces instead of a tab** in a recipe: Make says `missing separator`. The `.editorconfig` forces tabs in the Makefile.
- **Forgetting `.PHONY`**, so a file named like the target silently disables it.
- **Each recipe line runs in its own shell**, so `cd dir` on one line does not affect the next. Join lines with `&&` or `;`.
- **Putting logic in the Makefile.** Here the logic lives in scripts, which can be run, tested and shell-checked without Make.

## 8. Check yourself

1. Why must a recipe line start with a tab?
   *Answer:* That is how Make tells a recipe from a rule; spaces give a `missing separator` error.
2. What does `.PHONY` do?
   *Answer:* It marks targets that are commands, not files, so Make always runs them.
3. When does Make skip a file target?
   *Answer:* When the file exists and no dependency is newer than it.
4. What does `$$status` in a recipe become?
   *Answer:* `$status` in the shell, because Make turns `$$` into one `$`.
5. Why does a failing line stop the target?
   *Answer:* Make treats a non-zero exit from a recipe line as an error, unless the line starts with `-`.

## 9. Further reading

- GNU Make manual: <https://www.gnu.org/software/make/manual/make.html>. The Mac that built this uses GNU Make 3.81 from the system; CI uses GNU Make 4.3. The Makefile uses only features both have.
