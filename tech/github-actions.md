# GitHub Actions

## 1. What it is

GitHub Actions runs a **workflow** (a YAML file under `.github/workflows/`) on GitHub's machines whenever something happens, such as a push. A workflow has **jobs**; a job runs **steps** on a **runner** (a fresh virtual machine).

## 2. Why this repository uses it

The same checks run on every push, on a clean machine, so a passing local run is also a passing CI run.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `.github/workflows/ci.yml` | three jobs: `lint`, `offline`, `cluster` |
| `scripts/ci-install-tools.sh` | installs kubeconform on the runner |

## 4. How it works underneath

- `on: [push, pull_request]` is the trigger. Each job starts on a clean machine, so each one checks out the code and installs its tools.
- `uses: actions/checkout@v4` runs a published action (a reusable step). `run:` runs a shell command. `with:` passes inputs.
- A step that exits non-zero fails its job and the check on the commit turns red.
- `echo "NAME=value" >> "${GITHUB_ENV}"` sets an environment variable for the later steps.
- Nothing runs here until the repository is pushed to GitHub; locally the same checks are `make lint` and `make test-offline`.

## 5. Walkthrough of this repository's use

```yaml
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - name: Install the tools
        run: ./scripts/ci-install-tools.sh
      - run: make lint
```
`runs-on: ubuntu-latest` picks the runner image. `checkout` fetches the code; `setup-python` installs Python 3.12; the install script adds kubeconform; `make lint` is the same command as locally.

The `offline` job runs `make test-offline` and `make audit`. The `cluster` job uses `helm/kind-action@v1` with `install_only: true` (install the `kind` program but create no cluster), appends `CLUSTER_PROVIDER=kind` to `${GITHUB_ENV}` (kind is the conventional choice on a runner), then `make up` and `make test-cluster`. These jobs have not run on GitHub; the repository has not been pushed.

<!-- full-walkthrough:begin -->
### 5.A Full walkthrough: the whole `ci.yml`

**Words you need first.** GitHub can run a **workflow** (a YAML file in `.github/workflows/`) on its own machines whenever something happens, such as someone pushing a commit. A workflow has **jobs**; each job runs on a fresh virtual machine called a **runner** and has **steps**. A step either runs a shell command (`run:`) or uses a ready-made **action** (`uses:`).

```yaml
---
name: ci

on: [push, pull_request]

```

- `---` begins the YAML; `name: ci` is the workflow's name; `on: [push, pull_request]` runs it for every push and for every pull request.

```yaml
jobs:
  lint:
    name: yamllint, kubeconform, shellcheck, ruff, mypy
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Install the tools
        run: ./scripts/ci-install-tools.sh
      - run: make lint

```

- Job `lint` (named for what it runs) on `ubuntu-latest`. Steps: `actions/checkout@v4` fetches the repository; `actions/setup-python@v5` installs Python 3.12 (`with:` passes the input); the step named "Install the tools" runs `./scripts/ci-install-tools.sh` (kubeconform); `make lint` runs the linters. These are the same commands you run locally.

```yaml
  offline:
    name: Unit tests and manifest checks with coverage
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - name: Install the tools
        run: ./scripts/ci-install-tools.sh
      - run: make test-offline
      - run: make audit
```

- Job `offline`: the same set-up, then `make test-offline` and `make audit`.

```yaml
  cluster:
    name: kind cluster, Argo CD and the scripted runbook
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with:
          python-version: "3.12"
      - uses: helm/kind-action@v1
        with:
          install_only: true
      - name: Use kind on the runner
        run: echo "CLUSTER_PROVIDER=kind" >> "${GITHUB_ENV}"
      - name: Install the tools
        run: ./scripts/ci-install-tools.sh
      - run: make up
      - run: make test-cluster
```

- Job `cluster`: checkout and Python as before, then `helm/kind-action@v1` with `install_only: true` installs the `kind` program without creating a cluster; the step "Use kind on the runner" appends `CLUSTER_PROVIDER=kind` to the file named by `${GITHUB_ENV}`, which makes it an environment variable in later steps; then the tools, `make up` and `make test-cluster`. The repository has not been pushed, so this workflow has not run on GitHub yet.
<!-- full-walkthrough:end -->

## 6. Try it yourself

1. `grep -n 'make ' .github/workflows/ci.yml` : the three `make` targets CI runs.
2. `make lint && make test-offline` : the first two jobs, locally.
3. `.venv/bin/yamllint -s .github/workflows/ci.yml` : the workflow passes the same linter.
4. `python3 -c "import yaml; print(list(yaml.safe_load(open('.github/workflows/ci.yml'))['jobs']))"` : `['lint', 'offline', 'cluster']`.
5. After pushing to GitHub, the Actions tab shows the three jobs.

## 7. Mistakes people make

- A workflow that differs from what you run locally. This one calls the same `make` targets.
- Unpinned third-party actions; major-version tags are used here and should be pinned by hash for production.
- Putting secrets in the file; none are needed.

## 8. Check yourself

1. What starts a workflow?
   *Answer:* The events listed under `on:`.
2. Why does every job check out the code again?
   *Answer:* Each job runs on its own fresh machine.
3. What does `uses:` do?
   *Answer:* Runs a published, reusable action.
4. What turns a check red?
   *Answer:* A step that exits with a non-zero status.
5. How does this workflow stay in step with local work?
   *Answer:* It runs the same `make` targets.

## 9. Further reading

- Workflow syntax: <https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions>.
