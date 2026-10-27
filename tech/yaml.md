# YAML

## 1. What it is

YAML is a plain-text format for structured data: lists, key-value maps and values. Most tools of this repository (Kubernetes, Kustomize, Argo CD, GitHub Actions, yamllint) read their configuration from YAML files.

## 2. Why this repository uses it

Every desired-state file the controller reads is YAML, so a beginner must read YAML fluently.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `manifests/**/*.yaml` | the application and the controller objects Git holds |
| `platform/**/*.yaml` | Argo CD, Flux and the Git server install files |
| `.github/workflows/ci.yml, .yamllint.yaml` | workflow and linter configuration |

## 4. How it works underneath

- **Indentation is structure.** Two spaces deeper means "inside". Tabs are not allowed.
- A **map** is `key: value`. A **list** item starts with `- `. They nest: a list of maps is very common.
- Scalars (single values) are strings, numbers, `true`/`false` and `null`. `"1"` in quotes is a string; `1` is a number. Kubernetes cares: `replicas: "many"` is refused because replicas must be a number.
- `---` starts a new **document** inside one file; Kubernetes files can hold several objects separated by it.
- `|` starts a **block scalar**: the following indented lines are one multi-line string. `{}` is an empty map; `["ALL"]` is a one-line list.
- `# text` is a comment.
- YAML 1.1 reads bare `yes`, `no`, `on`, `off` as booleans. That surprise is called "the Norway problem" (`no` is Norway's country code). Quote them.

## 5. Walkthrough of this repository's use

Take the Deployment in `manifests/apps/web/base/deployment.yaml`:

```yaml
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web
spec:
  replicas: 2
  template:
    spec:
      containers:
        - name: web
          image: plainround/web:1.0.0
          ports:
            - name: http
              containerPort: 8080
          securityContext:
            capabilities:
              drop: ["ALL"]
      volumes:
        - name: tmp
          emptyDir: {}
```

* `---` starts a document; the repository requires it at the top of every file (`document-start` in `.yamllint.yaml`).
* `apiVersion`, `kind`, `metadata` and `spec` are the four top-level keys of every Kubernetes object.
* `replicas: 2` is a **number**. `plainround.dev/config-revision: "1"` is quoted because annotation values must be **strings**.
* `containers:` is a **list**; each item starts with `- `. The item is a map with `name`, `image`, `ports`.
* `drop: ["ALL"]` is a one-line list; `emptyDir: {}` is an empty map (an empty temporary volume).
* Comments (`# ...`) explain *why*: for example, why `progressDeadlineSeconds` is 60.

The mistake the lesson stages (`06-bad-manifest.sh`) is a type error: `replicas: "many"` (a string where a number belongs). YAML accepts it; the Kubernetes schema refuses it.

`.github/workflows/ci.yml` shows YAML with **nested lists of maps** (`jobs` -> `steps` -> `- uses:` / `- run:`), and `|` is used in `platform/argocd/kustomization.yaml` (`patch: |-`) to hold a small YAML document as a text block; `|-` also strips the final newline.

## 6. Try it yourself

1. `python3 -c "import yaml,sys; print(yaml.safe_load(open('manifests/apps/web/base/deployment.yaml'))['spec']['replicas'])"` (use `.venv/bin/python`) : prints `2` as a number.
2. `.venv/bin/yamllint -s manifests/` : no output means the style is right.
3. Change `replicas: 2` to `replicas: "many"` in a copy, run `scripts/validate.sh <tree>` : kubeconform refuses it.
4. Remove two spaces of indentation from one line and run yamllint : an error names the line.
5. `kubectl kustomize manifests/apps/web/overlays/local | head -30` : the same objects as YAML after the build.

## 7. Mistakes people make

- Wrong indentation moves a key to a different parent without any error.
- Unquoted values that look like something else: `1.10` becomes the number 1.1, `on` becomes true.
- Duplicate keys: the last one silently wins in some parsers. `yamllint` catches it.
- Mixing tabs and spaces. This repository's `.editorconfig` and `yamllint` forbid tabs.

## 8. Check yourself

1. How does YAML show that one key is inside another?
   *Answer:* By deeper indentation with spaces.
2. What is the difference between `1` and `"1"`?
   *Answer:* A number and a string. Kubernetes fields have fixed types.
3. What does `---` do?
   *Answer:* It starts a new document in the same file.
4. What does `|` start?
   *Answer:* A block scalar: the indented lines below are one multi-line string.
5. Why quote `no` or `on`?
   *Answer:* YAML 1.1 parsers read them as booleans.

## 9. Further reading

- YAML 1.2.2 specification: <https://yaml.org/spec/1.2.2/>. Kubernetes reads YAML 1.1-style booleans in some paths, so quote ambiguous words.
