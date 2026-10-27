# make up | run | test | lint | down      (make help lists everything)
PYTHON ?= $(shell command -v python3.13 || command -v python3.12 || command -v python3)
VENV := .venv
PY := $(VENV)/bin/python
STAMP := $(VENV)/.installed
SCRIPTS := $(wildcard scripts/*.sh scripts/runbook/*.sh scripts/compare/*.sh docker/git-server/entrypoint.sh)

.PHONY: help install up run status test test-offline test-cluster compare lint format audit validate down clean

help: ## list the targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | sed -E 's/:.*## /\t/' | sort

$(STAMP): requirements-dev.lock pyproject.toml
	$(PYTHON) -m venv $(VENV)
	$(VENV)/bin/pip install -q --require-hashes -r requirements-dev.lock
	touch $@

install: $(STAMP) ## create .venv from the lock file

.env:
	cp .env.example .env

up: .env ## create the kind cluster, install Argo CD and the Git server, seed the repository
	./scripts/up.sh

run: ## the whole lesson as one scripted run (needs make up)
	./scripts/run.sh

status: ## what the controller reports and what the cluster holds
	./scripts/status.sh

validate: ## kubeconform over the rendered overlays and the Argo CD objects
	./scripts/validate.sh

lint: $(STAMP) ## yamllint, kubeconform, shellcheck, ruff and mypy
	$(VENV)/bin/yamllint -s .
	./scripts/validate.sh
	shellcheck $(SCRIPTS)
	$(VENV)/bin/ruff check .
	$(VENV)/bin/ruff format --check .
	$(VENV)/bin/mypy

format: $(STAMP) ## format the Python
	$(VENV)/bin/ruff format .
	$(VENV)/bin/ruff check --fix .

test-offline: $(STAMP) ## unit tests and manifest checks; no cluster needed
	$(PY) -m pytest -m "not cluster and not compare" --cov --cov-report=term-missing

test-cluster: $(STAMP) ## prove drift, pruning, rollback and the refused manifest on the cluster (needs make up)
	$(PY) -m pytest -m cluster

compare: $(STAMP) ## step 6: install Flux in a second cluster, run the same three behaviors, delete it
	./scripts/compare/flux-up.sh
	$(PY) -m pytest -m compare; status=$$?; ./scripts/compare/flux-down.sh; exit $$status

test: $(STAMP) ## everything: the offline tests, then the cluster tests (needs make up)
	$(PY) -m pytest -m "not cluster and not compare" --cov --cov-report=term-missing
	$(PY) -m pytest -m cluster

audit: $(STAMP) ## known-vulnerability check of the locked Python dependencies
	$(VENV)/bin/pip install -q pip-audit==2.9.0
	$(VENV)/bin/pip-audit --require-hashes -r requirements-dev.lock

down: ## delete the cluster and the working clone
	./scripts/down.sh

clean: ## remove the virtual environment and caches
	rm -rf $(VENV) .pytest_cache .mypy_cache .ruff_cache .coverage htmlcov
