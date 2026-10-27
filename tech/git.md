# Git

## 1. What it is

Git is a version-control system: it stores the history of a folder as a chain of **commits**, each a snapshot with a message and a parent. A **repository** is that history. A **remote** is another copy (here a small server inside the cluster). `push` sends commits to a remote; `clone` copies one.

## 2. Why this repository uses it

Git is the whole subject: the desired state lives in a Git repository, a change is a commit, a rollback is a `git revert`. The scripts keep a **working clone** of a demo repository and push it to a Git server inside the cluster.

## 3. Where it appears

| File | What it does with this technology |
| --- | --- |
| `scripts/seed-repo.sh` | creates the working clone, installs the pre-push hook, makes the first commit and pushes |
| `scripts/lib.sh (`work_git`, `commit_and_push`, `work_head`)` | every Git action of the runbook |
| `scripts/runbook/*.sh` | commits, `git revert`, `git push --no-verify` |
| `docker/git-server/` | the smart-HTTP server |
| `.gitignore` | keeps `.work/`, `.env`, `.venv/` and caches out of this repository |

## 4. How it works underneath

- A commit is identified by a 40-character hash of its content and parent. Changing anything changes the hash, so a hash names exactly one state.
- A **branch** is a movable name for a commit (`main`). `HEAD` is "where I am now".
- `git revert <commit>` makes a *new* commit that undoes an earlier one. History is kept, which is why GitOps uses it for rollback instead of rewriting history.
- A **hook** is a script Git runs at a moment such as `pre-push`; if it exits non-zero, the push is refused. `--no-verify` skips it.
- **Smart HTTP**: the server answers `GET .../info/refs?service=git-upload-pack` to list branches and `POST .../git-receive-pack` to accept a push. Anything that speaks that can be a Git server.

## 5. Walkthrough of this repository's use

```bash
git -C "${WORK_CLONE}" init --quiet --initial-branch=main
git -C "${WORK_CLONE}" config user.name "Runbook"
git -C "${WORK_CLONE}" config user.email "runbook@example.invalid"
git -C "${WORK_CLONE}" config commit.gpgsign false
```
`-C dir` runs Git as if started in that folder. The demo repository is created fresh in `.work/gitops-demo`, with a fixed author so commits work without a global Git identity, and signing off so a global signing setting cannot block the script.

```bash
cat > "${WORK_CLONE}/.git/hooks/pre-push" <<HOOK
#!/usr/bin/env bash
exec "${ROOT}/scripts/validate.sh" "${WORK_CLONE}"
HOOK
chmod +x "${WORK_CLONE}/.git/hooks/pre-push"
```
A here-document writes the hook; `exec` replaces the shell with the validator, so its exit code becomes the hook's. A failing validation refuses the push.

```bash
work_git remote add origin "${GIT_HOST_URL}"
work_git push --quiet --force origin main
```
`origin` is the in-cluster Git server reached through the published port. `--force` is only for the first push after a reset, so it replaces whatever an earlier run left.

In the runbook: `git revert --no-edit <sha>` creates the undoing commit without opening an editor; `git rm --quiet file` removes a tracked file; `git push --no-verify` skips the hook to show the second line of defense; `git log -1 --format='%h %s'` prints the short hash and subject; `git rev-parse HEAD` prints the full hash that `status.sync.revision` is compared with.

The repository itself (the one you cloned) holds the code of the lesson. The *demo* repository under `.work/` is what Argo CD watches. The two must not be confused.

## 6. Try it yourself

1. `git -C .work/gitops-demo log --oneline` : the demo repository's history after `make up`.
2. `git ls-remote http://127.0.0.1:30418/gitops-demo.git` : the server's branch hashes (cluster up).
3. `scripts/runbook/05-break-and-rollback.sh bad` then `git -C .work/gitops-demo log --oneline` : a new commit; `... rollback` adds a revert commit.
4. `cat .work/gitops-demo/.git/hooks/pre-push` : the hook.
5. `git status --short` in this repository : clean (`.work/` is ignored).

## 7. Mistakes people make

- Rewriting shared history (`push --force`) so other copies disagree. The runbook uses `revert`, and `--force` only on the demo repository when it is reset.
- Committing generated files or secrets. `.gitignore` lists what must not be tracked.
- Assuming a hook cannot be skipped. A hook is a convenience; the real gate is a check on the server or in CI.

## 8. Check yourself

1. What does a commit hash identify?
   *Answer:* Exactly one snapshot and its history.
2. Why use `git revert` instead of deleting a commit?
   *Answer:* It adds a new commit that undoes the old one and keeps the history intact.
3. What is a pre-push hook?
   *Answer:* A script that runs before a push and can refuse it by failing.
4. How can a hook be skipped?
   *Answer:* With `git push --no-verify`.
5. What is `main`?
   *Answer:* A branch name: a pointer to the newest commit of the main line.

## 9. Further reading

- Pro Git book: <https://git-scm.com/book/en/v2>. Git reference: <https://git-scm.com/docs>.
