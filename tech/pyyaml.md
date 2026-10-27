# PyYAML

## 1. What it is

PyYAML is a Python library that turns YAML text into Python dictionaries and lists (`yaml.safe_load`) and back.

## 2. Why this repository uses it

The offline tests check the manifests (replica counts, probes, security settings) without a cluster. They need to read the YAML as data.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `tests/unit/test_manifests.py` | loads the rendered overlay and a few single files, and asserts on the structure |
| `pyproject.toml, requirements.lock` | pinned at 6.0.3 |

## 4. How it works underneath

- `yaml.safe_load(text)` returns the first document as nested dicts and lists. `safe_load_all` yields one object per `---` document.
- `safe_` means it builds only plain data. The non-safe `yaml.load` can create arbitrary Python objects from a tag, which is a security risk with untrusted files.
- Numbers come back as `int`, quoted values as `str`, `true` as `True`.

## 5. Walkthrough of this repository's use

```python
def render(root: Path, overlay: str = OVERLAY) -> dict[tuple[str, str], dict[str, Any]]:
    output = run(["kubectl", "kustomize", str(root / overlay)]).stdout
    documents = [doc for doc in yaml.safe_load_all(output) if doc]
    return {(doc["kind"], doc["metadata"]["name"]): doc for doc in documents}
```
`render` runs `kubectl kustomize` on the overlay (so the test sees exactly what Argo CD would apply), loads the output with `yaml.safe_load_all` (one document per object, `if doc` drops empty ones) and indexes the objects by `(kind, name)`. A module-scoped fixture builds this once. Tests then assert facts as ordinary Python: the overlay renders exactly four objects (Namespace, ConfigMap, Deployment, Service); two replicas and `GREETING: hello`; the container runs non-root with limits and probes; the Namespace enforces the restricted Pod Security level; the Application has an explicit `automated` block; the AppProject allows only this repository and namespace; every image is pinned. Two tests read single files with `yaml.safe_load`: the Argo CD tag in `platform/argocd/kustomization.yaml` must equal `ARGOCD_VERSION` in `versions.env`, and the Application and AppProject files are checked directly.

## 6. Try it yourself

1. `.venv/bin/python -c "import yaml; d=yaml.safe_load(open('manifests/clusters/local/application.yaml')); print(d['spec']['syncPolicy'])"` : `{'automated': {'prune': False, 'selfHeal': False}}`.
2. `.venv/bin/python -c "import yaml; print(list(yaml.safe_load_all(open('platform/git-server/git-server.yaml')))[1]['kind'])"` : `Deployment` (the file holds several documents).
3. `.venv/bin/pytest tests/unit/test_manifests.py -q` : the manifest tests pass.
4. `.venv/bin/python -c "import yaml; print(yaml.safe_load('a: no'))"` : `{'a': False}`, the YAML 1.1 surprise.
5. `.venv/bin/pip show pyyaml | head -3` : version 6.0.3.

## 7. Mistakes people make

- Using `yaml.load` on files you did not write.
- Forgetting that `safe_load` reads only the first document of a multi-document file.
- Expecting YAML 1.2 rules: PyYAML follows YAML 1.1.

## 8. Check yourself

1. What is the difference between `safe_load` and `safe_load_all`?
   *Answer:* One reads the first document; the other yields every document.
2. Why prefer `safe_load` over `load`?
   *Answer:* It cannot build arbitrary Python objects from a file.
3. What does `no` become in PyYAML?
   *Answer:* `False`.
4. What type is a quoted `"1"`?
   *Answer:* A string.
5. Why do tests load YAML as data?
   *Answer:* To assert on facts without a cluster.

## 9. Further reading

- PyYAML: <https://pyyaml.org/wiki/PyYAMLDocumentation> (6.0.3).
