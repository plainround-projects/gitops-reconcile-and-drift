# kubeconform

## 1. What it is

kubeconform checks Kubernetes YAML against the official JSON Schemas of each kind and version, without a cluster. It catches a wrong type, a misspelled field or a missing required field before the API server would.

## 2. Why this repository uses it

A manifest the schema refuses should be stopped on the laptop, not by the cluster. The lesson's bad manifest (`replicas: "many"`) is refused here first, in the pre-push hook.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `scripts/validate.sh` | the whole gate |
| `scripts/seed-repo.sh` | installs it as the working clone's pre-push hook |
| `scripts/ci-install-tools.sh` | installs v0.8.0 on the CI runner |
| `tests/unit/test_validate_script.py` | proves the gate refuses a string for a number, an unknown field and a misspelled Application field |
| `versions.env` | `KUBECONFORM_KUBERNETES_VERSION=1.35.0` |

## 4. How it works underneath

- Every Kubernetes kind has a published JSON Schema. kubeconform fetches the right one by `apiVersion` and `kind` and compares the object.
- `-strict` rejects fields the schema does not know and requires the full set. `-kubernetes-version 1.35.0` picks the schema release. `-summary` prints counts.
- Custom resources (Argo CD, Flux, sops-aware kinds) are not in the core schemas; `-schema-location` adds a community catalog, with a URL template that fills in group, kind and version.
- `-cache` stores downloaded schemas so later runs work faster.
- `-` as the file name reads from standard input, which is how `kubectl kustomize ... | kubeconform -` checks the built output.

## 5. Walkthrough of this repository's use

```bash
cache="${XDG_CACHE_HOME:-${HOME}/.cache}/plainround-kubeconform"
common=(-strict -summary -kubernetes-version "${KUBECONFORM_KUBERNETES_VERSION}" -cache "${cache}")
crds='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
```
A cache folder, a Bash array of options reused twice, and a URL **template**: kubeconform fills `{{.Group}}`, `{{.ResourceKind}}` and `{{.ResourceAPIVersion}}` to find the schema of a custom resource such as `argoproj.io` `Application`.

```bash
for overlay in "${tree}"/apps/*/overlays/*; do
  [ -d "${overlay}" ] || continue
  kubectl kustomize "${overlay}" | kubeconform "${common[@]}" - || status=1
done
```
Each overlay is **built first**, then validated from standard input (`-`). `|| status=1` records a failure without stopping the loop, so every overlay is checked and the script exits non-zero at the end.

```bash
kubeconform "${common[@]}" -schema-location default -schema-location "${crds}" "${tree}/clusters" || status=1
```
The `clusters/` folder holds Argo CD objects. `-schema-location default` keeps the built-in Kubernetes schemas; the second location adds the community catalog. The same script runs in the pre-push hook of the working clone with `validate.sh "${WORK_CLONE}"`.

## 6. Try it yourself

1. `scripts/validate.sh` : `Summary: ... Valid: N, Invalid: 0`.
2. `kubectl kustomize manifests/apps/web/overlays/local | kubeconform -strict -summary -kubernetes-version 1.35.0 -` : the build checked alone.
3. Put `replicas: "many"` in a copy of the tree and run `scripts/validate.sh <copy>` : `Invalid`, with the path of the field.
4. Add an unknown field and rerun : `-strict` refuses it.
5. `kubeconform -v` : `v0.8.0`.

## 7. Mistakes people make

- Validating the source files instead of the built output; a Kustomize overlay is only complete after the build.
- Skipping unknown kinds silently. The scripts here name the schema locations so custom kinds are checked.

## 8. Check yourself

1. Does kubeconform need a cluster?
   *Answer:* No. It uses published schemas.
2. What does `-strict` do?
   *Answer:* Rejects unknown fields and requires the complete shape.
3. Why can core schemas not check an Argo CD Application?
   *Answer:* It is a custom resource; its schema comes from a separate catalog.
4. What does `-` mean as the input?
   *Answer:* Read the YAML from standard input.
5. Why pin `-kubernetes-version`?
   *Answer:* So the result does not change when a newer Kubernetes ships.

## 9. Further reading

- kubeconform: <https://github.com/yannh/kubeconform> (pinned v0.8.0 in CI). The CRD catalog it uses: <https://github.com/datreeio/CRDs-catalog>.
