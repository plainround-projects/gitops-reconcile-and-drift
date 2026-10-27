# grep, sed, awk, perl, curl and other command-line tools

## 1. What it is

Unix tools are small programs that each do one text or network job and are joined with pipes. Shell scripts depend on them. This note covers the ones this repository calls: `grep`, `sed`, `awk`, `cut`, `tr`, `head`, `sort`, `perl`, `curl`, `date`, `sleep`, `mkdir`, `touch`, `cp`, `rm`, `chmod`, `printf`, `wget`.

## 2. Why this repository uses it

The scripts edit manifests, read fields and wait for a Git server. Using standard tools keeps them readable without extra installs.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `scripts/runbook/*.sh, scripts/compare/*.sh` | `perl -pi -e` and `perl -0pi -e` edit the manifest files in place; `grep`, `awk` and `sed` read values |
| `scripts/install-git-server.sh, seed-repo.sh` | `curl -fsS` checks that the Git server answers |
| `scripts/install-argocd.sh` | `grep -oE`, `head`, `tr`, `sed` pull the version out of the Kustomize file |
| `Makefile` | `grep` and `sed` build `make help` |
| `docker/web/Dockerfile` | `wget` in the container health check |

## 4. How it works underneath

- A **pipe** (`a | b`) connects `a`'s output to `b`'s input.
- `grep PATTERN` prints lines that match. `-E` allows extended regular expressions, `-o` prints only the matching part, `-q` prints nothing and only sets the exit code, `-x` requires the whole line to match.
- `sed 's/old/new/'` replaces text. `awk '{print $2}'` prints the second whitespace-separated field. `cut -c1-7` keeps characters 1 to 7. `tr -d '/'` deletes characters.
- `perl -pi -e 'CODE' file`: `-e` runs the code, `-p` runs it for each line and prints the line, `-i` writes back to the same file. `-0` reads the whole file as one string, so a pattern can span lines.
- `curl -fsS URL`: `-f` fail on an HTTP error status, `-s` silent, `-S` still show errors.

## 5. Walkthrough of this repository's use

```bash
perl -pi -e 's/^  replicas: 2$/  replicas: 3/' "${deployment}"
```
For each line, if it is exactly two spaces then `replicas: 2` (`^` start, `$` end), replace it with `replicas: 3`. The anchors stop it from touching other lines.

```bash
perl -pi -e 's/(plainround.dev\/config-revision: )"1"/$1"2"/' "${deployment}"
```
`( ... )` captures the text before `"1"`; `$1` puts it back. The `/` inside the pattern is escaped as `\/`.

```bash
perl -0pi -e 's#(readinessProbe:\s+httpGet:\s+path: )/healthz#$1/definitely-missing#' deployment.yaml
```
`-0` reads the file as a single string; `\s+` matches any whitespace including newlines; `#` is used as the delimiter so `/` needs no escaping. It changes only the path under `readinessProbe`, not the liveness probe.

```bash
perl -ni -e 'print unless /^  - configmap.yaml$/' kustomization.yaml
```
`-n` runs per line but prints nothing automatically; the code prints every line **except** the one that lists the ConfigMap file.

```bash
git_replicas() { grep -E '^  replicas:' deployment.yaml | awk '{print $2}'; }
```
Find the `replicas:` line and print its second field, the number.

```bash
pinned="$(grep -oE 'argo-cd/v[0-9.]+/' kustomization.yaml | head -1 | tr -d '/' | sed 's/argo-cd//')"
```
Cut `argo-cd/v3.5.6/` out of the file (`-o`), take the first (`head -1`), delete slashes, then delete `argo-cd`, leaving `v3.5.6`.

```bash
wait_for "the Git server on ${GIT_HOST_URL}" 60 curl -fsS "${GIT_HOST_URL}/info/refs?service=git-upload-pack"
```
Polls the Git smart-HTTP endpoint until it answers with success.

`wget -q -O /dev/null http://127.0.0.1:8080/healthz` is the container health check (busybox `wget`, available in Alpine).

## 6. Try it yourself

1. `echo "  replicas: 2" | perl -pe 's/^  replicas: 2$/  replicas: 3/'` : prints `  replicas: 3`.
2. `grep -E '^  replicas:' manifests/apps/web/base/deployment.yaml | awk '{print $2}'` : `2`.
3. `grep -oE 'argo-cd/v[0-9.]+/' platform/argocd/kustomization.yaml` : `argo-cd/v3.5.6/`.
4. `curl -fsS -o /dev/null -w '%{http_code}\n' http://127.0.0.1:30418/gitops-demo.git/info/refs?service=git-upload-pack` : `200` when the cluster is up.
5. `printf '%s\n' a b | tr a-z A-Z` : `A` and `B`.

## 7. Mistakes people make

- Editing YAML with `sed` on a pattern that matches more than one line; anchors (`^`, `$`) and exact text prevent that here.
- Forgetting `-i` and expecting the file to change.
- `grep` returning exit code 1 when nothing matches, which stops a `set -e` script; scripts use `|| true` where "no match" is fine.
- Differences between GNU and BSD `sed`: the scripts use `perl` for in-place edits because it behaves the same on macOS and Linux.

## 8. Check yourself

1. What does `-q` do in `grep -q`?
   *Answer:* No output; only the exit code says whether it matched.
2. What does `perl -pi -e` do?
   *Answer:* Runs code on every line and writes the result back to the same file.
3. What does `-0` change in perl?
   *Answer:* The whole file is read as one string, so patterns can cross lines.
4. What does `curl -f` do?
   *Answer:* Makes curl fail (non-zero exit) on an HTTP error status.
5. Why use perl instead of `sed -i`?
   *Answer:* `sed -i` differs between macOS and Linux; perl behaves the same.

## 9. Further reading

- GNU grep: <https://www.gnu.org/software/grep/manual/grep.html>. perlrun (the `-p -i -e -0 -n` flags): <https://perldoc.perl.org/perlrun>. curl man page: <https://curl.se/docs/manpage.html>. Not version-specific: these are stable options.
