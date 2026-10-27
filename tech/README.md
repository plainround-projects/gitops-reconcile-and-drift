# Technology notes for gitops-reconcile-and-drift

These notes teach every technology this repository uses, from zero, through this repository's own files. Each file has the same nine parts: what it is, why it is here, where it appears, how it works underneath, a line-by-line walkthrough of this repository's use, commands to try, common mistakes, five questions, and official reading.

## Reading order

| # | File | Role in this repository |
| --- | --- | --- |
| 1 | [Bash](bash.md) | the scripts that start, run and stop everything |
| 2 | [GNU Make](make.md) | one-word commands (`make up`, `make test`) that wrap the scripts |
| 3 | [Git](git.md) | the source of truth the controller reads, and the tool for every change and rollback |
| 4 | [YAML](yaml.md) | the file format of every manifest and workflow |
| 5 | [Docker and the Dockerfile](docker.md) | builds the images and runs the containers the cluster uses |
| 6 | [nginx](nginx.md) | serves the demo page and fronts the Git server |
| 7 | [Kubernetes](kubernetes.md) | the platform that runs the application and the controllers |
| 8 | [Kustomize](kustomize.md) | builds the final manifests from a base and small overlays |
| 9 | [kubectl](kubectl.md) | the command-line client every script uses to talk to the cluster |
| 10 | [k3d and kind (local clusters)](k3d-kind.md) | creates the Kubernetes cluster on your machine inside Docker |
| 11 | [Argo CD](argo-cd.md) | the GitOps controller: it keeps the cluster equal to the Git repository |
| 12 | [Flux](flux.md) | the second GitOps controller used for the comparison |
| 13 | [kubeconform](kubeconform.md) | validates manifests against the Kubernetes and Argo CD schemas |
| 14 | [grep, sed, awk, perl, curl and other command-line tools](unix-tools.md) | the small programs the scripts call |
| 15 | [Python](python.md) | the language of the tests and a few helper scripts |
| 16 | [pip, venv and the lock files](pip-venv.md) | installs the exact test tools into a private folder |
| 17 | [TOML (pyproject.toml)](toml.md) | the one configuration file for the Python tools |
| 18 | [PyYAML](pyyaml.md) | reads the manifests in the offline tests |
| 19 | [pytest](pytest.md) | runs the offline tests and the cluster tests |
| 20 | [ruff](ruff.md) | lints and formats the Python |
| 21 | [mypy](mypy.md) | checks the type hints |
| 22 | [yamllint](yamllint.md) | checks the YAML files for style and mistakes |
| 23 | [ShellCheck](shellcheck.md) | finds mistakes in the shell scripts |
| 24 | [EditorConfig](editorconfig.md) | makes every editor use the same whitespace rules |
| 25 | [GitHub Actions](github-actions.md) | the CI workflow that repeats the checks on every push |

## Ten minutes? Read these three

- [Git](git.md): the whole idea: a commit is a deployment and a revert is a rollback.
- [Argo CD](argo-cd.md): the controller itself and the three behaviors the lesson measures.
- [Kubernetes](kubernetes.md): the objects the controller creates and compares.
