---
name: git-workflow
description: "Git pitfalls: nested repos, staging, identity."
version: 1.0.0
author: Sydney
license: MIT
metadata:
  hermes:
    tags: [git, workflow, pitfalls, staging, nested-repos, commit]
    category: software-development
---

# Git Workflow

Pitfalls and procedures for everyday git operations that fall outside standard
`gh` CLI workflows (for gh-specific flows see the `github` skill).

## Standing Rules

- Always check `git status` and `git remote -v` before staging or pushing.
- Configure per-repo identity before first commit if global config is absent.
- Never assume a branch name — read it from `git branch --show-current`.
- Inspect `git status --short` and the relevant diff at startup. Treat pre-existing changes as user-owned: do not stage, discard, or claim them as task work.
- Verify the current branch's upstream is the remote branch with the **same name**. A status line such as `branch...origin/beta` proves synchronization with the wrong branch, not delivery of the current branch.

## Dirty Startup and Tracking Checks

```bash
branch=$(git branch --show-current)
git status --short
git branch -vv
git config --get "branch.$branch.remote"
git config --get "branch.$branch.merge"
```

If the checkout was seeded with tracking from another branch, push explicitly first and then repair only the local tracking config:

```bash
remote=$(git config --get "branch.$branch.remote")
git push "$remote" "HEAD:refs/heads/$branch"
git config --local "branch.$branch.remote" "$remote"
git config --local "branch.$branch.merge" "refs/heads/$branch"
```

Do not change remote URLs merely to alter branch synchronization. Verify delivery with both hashes:

```bash
git rev-parse HEAD
git rev-parse "refs/remotes/$remote/$branch"
```

## Isolating a Change Onto Its Own Branch

When a work branch carries unrelated commits (dependency bumps, doc plans, another issue's work) and the user wants a PR containing only the fix, do not open the PR from that branch — every unrelated commit rides along.

**Rule:** branch from the upstream default, then cherry-pick just the fix, so the PR diff is provably scoped.

```bash
git fetch https://github.com/<upstream>/<repo>.git <default>:refs/remotes/canonical/<default>
git checkout -b <issue-slug> canonical/<default>
git cherry-pick <fix-sha>
git diff canonical/<default>..HEAD --stat   # proves scope
```

`git diff <base>..HEAD --stat` is the scope check — read it before pushing, and confirm no unrelated file appears. A fetch by URL into a private ref keeps remote configuration untouched, which matters when the remotes are managed for you. Re-run the targeted tests on the isolated branch; a cherry-pick can conflict with a different base.

## Divergent Remote Branch (non-fast-forward push)

`git push` rejected with `! [rejected] ... (non-fast-forward)` means the **remote branch of the same name has commits your local branch does not** — typically a parallel session pushed to the shared branch. Before anything destructive, find out what those commits are:

```bash
git fetch origin <branch>
git log --oneline HEAD..origin/<branch>   # remote-only
git log --oneline origin/<branch>..HEAD   # local-only
git diff --stat HEAD origin/<branch>      # do the trees actually differ?
```

Three responses, in order of preference:

1. **Branch fresh and cherry-pick** (see *Isolating a Change Onto Its Own Branch*). Safest: leaves the other session's remote commits intact and produces a provably scoped PR. Confirm the local original still holds your commit afterwards: `git rev-parse <old-branch>`.
2. **Merge the remote branch in** — only when the divergence is small and the content is genuinely disjoint.
3. **Force-push** — last resort. It deletes the other session's commits from the remote. Get explicit user confirmation naming what will be lost.

**Do not `git rebase` onto the divergent remote to "fix" a non-fast-forward.** If the local branch carries many upstream commits, the rebase replays all of them and conflicts on whichever doc or lockfile those commits touched. `git rebase --abort` restores state exactly; the branch you started from is still there.

## Making A Branch Exactly Match A Canonical Branch

The request is "make my local branch identical to upstream X, delete any extra files". Do it as a
four-step audit, not a blind reset — a blind `reset --hard` discards committed work the user may
still want, and a blind `clean -fd` deletes the toolchain the working tree depends on.

```bash
git fetch https://github.com/<owner>/<repo>.git <canonical>:refs/remotes/canonical/<canonical>
git rev-parse refs/remotes/canonical/<canonical>   # target SHA
git diff --stat refs/remotes/canonical/<canonical> # tracked drift: local edits + missing files
git ls-files --others --exclude-standard           # untracked extras to delete (count first)
```

Restore drifted tracked files from the canonical ref without touching history — this keeps local
commits and only reverts the working-tree difference:

```bash
git checkout refs/remotes/canonical/<canonical> -- <path>
```

Then decide whether force is even needed. Users ask for force because they assume divergence:

```bash
git merge-base --is-ancestor <remote-branch-sha> refs/remotes/canonical/<canonical> \
  && echo "fast-forward: no force needed" || echo "diverged: force required"
```

Push with an **explicit** lease. Plain `--force-with-lease` derives its expectation from the
upstream tracking config, which on a managed branch may point at a different branch and then
silently degenerates to an unconditional force:

```bash
git push --force-with-lease=refs/heads/<branch>:<expected-remote-sha> \
  origin HEAD:refs/heads/<branch>
```

Verify by comparing **tree** hashes, not commit SHAs and not a human-read diff — tree equality is
the actual claim "these are identical files":

```bash
git rev-parse refs/remotes/<fork>/<branch>^{tree} refs/remotes/canonical/<canonical>^{tree}
git ls-remote --heads <fork> <branch>          # what the remote really holds now
```

Pitfalls:

- **Ignored files are not extra files.** `vendor/`, `node_modules/`, `.env`, build caches and
  tool databases are untracked *by design* and regenerable only at real cost. Delete untracked
  extras the user actually named; report ignored leftovers, never `clean -xfd` them.
- **Lockfile drift is normal, not a stray edit.** Package managers rewrite `package-lock.json`
  (or its equivalent) on any install, so the working tree drifts from the branch after routine
  commands. That drift is exactly what this audit is for — restore it and say so. Before
  discarding it, confirm the canonical branch does not also change that file
  (`git diff --name-only HEAD..FETCH_HEAD | grep <lockfile>`); upstream touching it makes the
  drift a real conflict to merge, not noise to `git checkout --`.
- **`git fetch <remote> <branch>` does not create a remote-tracking ref** for a branch that remote
  has never tracked locally; it writes `FETCH_HEAD`, so a later `refs/remotes/<remote>/<branch>`
  lookup fails as an ambiguous argument. Use a bare `git fetch <remote>` to populate tracking refs,
  or compare `FETCH_HEAD` directly.
- **A fast-forward result means no rewrite happened.** When the ancestor check says fast-forward,
  say so explicitly — reporting "force pushed" when the push advanced the ref by one commit
  misleads the user about whether history was rewritten.

## Keeping A Fork's Base Branch Synced With A Canonical Upstream

When the workflow is "am I behind the canonical `X`? mirror it into my fork, push my branch",
a fetch of the fork's own `X` cannot answer the first question — the fork's `X` lags
independently, so both refs are stale together and compare clean. Fetch the canonical branch
by URL so no remote has to be added, renamed, or reconfigured:

```bash
git fetch https://github.com/<owner>/<repo>.git <canonical>     # lands in FETCH_HEAD
git fetch <fork> --prune
git rev-list --left-right --count FETCH_HEAD...HEAD              # <behind> <ahead>
```

Order of operations:

1. Discard registry noise (lockfile bullet above) so the merge is not blocked by an
   unrelated dirty file.
2. Mirror canonical into the fork — `git push <fork> FETCH_HEAD:refs/heads/<canonical>`. Creates
   the fork's branch when absent, fast-forwards it when present. Never force; if it is not a
   fast-forward, that is real divergence to merge and resolve, not to overwrite.
3. Bring the working branch up — `git merge --ff-only <fork>/<canonical>`. Non-fast-forward means
   local commits on top: merge (never rebase published work).
4. Push the working branch with an explicit refspec — `git push <fork> HEAD:refs/heads/<branch>` —
   because `branch.<name>.merge` may point at the canonical branch and a bare `git push` then
   writes your work to the wrong ref.
5. Verify by SHA *and* tree hash across all three refs (canonical, fork base, fork work branch),
   never by `git status` — a tracking config pointing at the base branch makes status read as
   permanently ahead/behind while saying nothing about the remote work branch. The verification
   block and the decision table live in `references/upstream-sync.md`.

When the count is already `0 0` and the tree is clean, do nothing and report "already in sync" —
an empty merge or a no-op push described as an update misleads the user about what changed. In a
shared fork, other agents' branches are not yours to touch: sync only the base branch and your own
branch, and list the untouched ones so the user can see they were left alone.

## Is A Commit Actually On The Base Branch?

`git log <base>` showing a commit, or a commit sitting in your branch's history, does **not** mean the base branch contains it. A commit can reach your branch through a merge from a fork while the base took a different route.

```bash
git merge-base --is-ancestor <sha> <base> && echo YES || echo NO
git log --oneline <base> -- <file>     # what the base really has for this file
```

This is the check that explains "why is this file in my PR". A dependency bump sitting in your branch's history but absent from the base makes the lockfile show up in the PR diff even though you never touched it. When that happens, it is a **decision for the maintainer** — is the bump supposed to be on the base, or did the base deliberately hold the older version? Ask; do not silently "fix" it by reverting your copy or force-pushing.

## The PR Base May Be Ahead Of Your Local Ref

GitHub computes the PR diff against the base branch's **current** SHA. If you fetched a while ago, your local `git diff <base>..HEAD` can name two files while the PR shows three, or vice versa — and neither is wrong.

```bash
gh api repos/<owner>/<repo>/pulls/<n> --jq '.base.sha, .head.sha'
git rev-parse <base>                     # compare against your local ref
git fetch origin <base>:<remote-tracking-ref>   # explicit, updates the tracking ref
gh pr diff <n> --repo <owner>/<repo> --name-only   # what GitHub actually shows
```

Trust the remote's answer over yours when they disagree, and re-check after the next push. Note that `--list` style flags differ by tool: a PR-diff command naming three files right after a push that cleared two is usually this staleness, not a stray edit — fetch and re-read before changing anything.

## Responding To CHANGES_REQUESTED

Verify each criticism against the code before accepting or defending it. Reviewers check cited claims, and agreeing reflexively bakes a wrong fix into the docs; push back with evidence when they are wrong.

```bash
gh pr view <n> --repo <owner>/<repo> --json reviewDecision,reviews
```

**An empty inline-comment list is not an empty review.** Review comments attached to
specific lines and block-level review bodies are separate endpoints, and the request
usually lives in the bodies. Query both before concluding there is no feedback:

```bash
gh api repos/<owner>/<repo>/pulls/<n>/comments   # inline, per-line
gh api repos/<owner>/<repo>/pulls/<n>/reviews    # block-level, carries the verdict
```

Read the `state` field (`CHANGES_REQUESTED` / `APPROVED` / `COMMENTED`) — it tells you
whether anything blocks a merge.

For a docs/claims review, every accepted finding should be re-derived from the source, not patched from the reviewer's wording — and state in the reply which claims you confirmed. If a finding's stated *cause* is wrong but its *symptom* is real, fix the symptom and report the real cause separately rather than adopting the wrong explanation.

### Removing an unrelated file from an open PR

When the complaint is "this file does not belong in this PR" — a planning doc, a
generated artifact, another issue's work — cut it on the same branch rather than
cherry-picking onto a topic branch. Cherry-pick is the right move only when the branch
is free to be replaced; if the branch is published and long-lived, a fresh topic branch
contradicts the project's one-branch-per-server rule and loses nothing by not doing it.

```bash
cp <file> ~/some-backup-dir/          # preserve content outside the tree FIRST
git rm <file>
git diff --stat <base>..HEAD           # scope check: only the intended change left
git commit -m "docs: drop <file> from the branch"
git push origin HEAD:refs/heads/<branch>
```

The `cp` comes first — after `git rm` the content is only in git history, and the point
of removing it is that you do not want it in history either. Use the explicit
`HEAD:refs/heads/<branch>` refspec so a branch whose tracking config points at another
branch still delivers (see *Dirty Startup and Tracking Checks*).

Then verify the PR diff is exactly the change you claim:

```bash
git diff --stat <base>..HEAD
gh pr diff <n> --repo <owner>/<repo> --name-only
```

Reply in the PR thread and stop. Merging is always a separate, explicit request.

### Posting the reply

A PR conversation is an issue conversation: the write endpoint is
`issues/<n>/comments` and it takes `issue_number`, even when the target is a PR.
Handing `pull_number` to an issue-comment call is rejected on argument validation —
that is an endpoint mix-up, not a permissions problem. `pulls/<n>/comments` is the
READ side and stays read-only; never write a reply there.

```bash
gh api repos/<owner>/<repo>/issues/<n>/comments -f body="$(cat /tmp/reply.md)"
```

Write long replies to a file and pass `body="$(cat ...)"` — inline `-f body='...'`
breaks on backticks, quotes, and newlines inside shell quoting, and the mangled text
lands in a thread a human will read.

MCP GitHub tools and the `gh` CLI use different tokens, so an MCP call can fail
authentication while `gh` is still authenticated. Fall back to `gh api` for the
write, confirm it returned a comment `html_url`, and report that URL — a bare exit 0
from the CLI does not prove the comment posted.

## Separating your changes from pre-existing drift before committing

"Commit the work you did" is a scoping instruction, not "commit everything modified". A working
tree that was already dirty when you started contains changes you did not make and must not
sweep into your commit. Identify them by MTIME, which is the only reliable discriminator —
`git status` cannot tell who touched what:

```bash
# files predating your session belong to someone else; keep them out
stat -c '%y  %n' package-lock.json composer.json tests/Feature/MyNewTest.php
git checkout -- package-lock.json          # restore only the confirmed-foreign ones
git add -A -- . ':!package-lock.json'      # then stage everything else
```

**Rule:** before staging, check the MTIME of each modified file against when your session
started. A lockfile older than your first command is pre-existing drift — leave it out and say
so in the report rather than quietly absorbing it. Use a pathspec exclusion
(`git add -A -- . ':!<file>'`) so the exclusion is explicit and reviewable, and never
`git stash`/`reset` a file you did not create.

Report the excluded file by name with its diffstat so the user can decide separately whether to
commit it. A skipped file they never knew about becomes their surprise later.

## Committing a long fix: explain the root cause in the body, not just the symptoms

When a commit bundles a fix whose root cause was environmental (a stale cache, a missing
extinction, a config value), the diff alone does not show it — a reviewer sees only the code
changes and cannot tell why they were necessary. State the cause in the commit body, including
when it was NOT a code change:

```
Note: a stale bootstrap/cache/routes-v7.php built before APP_KEY existed made the
Livewire update endpoint 404, which broke every interactive element. Fixed by
clearing the caches; not a code change.
```

**Rule:** for each hunk, give the mechanism ("this breaks because X"), not the restatement
("fixed Y"). Cover the deletions too — a removed controller or view needs its reason recorded,
or the next reader re-adds it. Verify the scope you claim: `git diff --cached --stat` before
committing, and grep the staged diff for hardcoded secrets
(`git diff --cached | grep -iE '^\+.*(password|secret|token)\s*=\s*["\x27][^"\x27]{6,}'`).

## Reporting a commit honestly when you did not push

State plainly which of these happened: committed, pushed, or committed-and-ahead. `git status -sb`
showing `[ahead 1]` after a commit means the work is LOCAL ONLY — say so and offer to push
rather than describing a local commit as "delivered".

## Pitfalls

### Nested `.git` directories when copying content

When `cp -r` (or similar) a directory that contains its own `.git` into another repo,
`git add` detects the nested `.git` and stages only a submodule reference (mode 160000),
not the actual files. Clones of the outer repo will not contain the copied content.

**Fix — remove nested `.git` before staging:**

```bash
cp -r /source/dir target/inside/repo
rm -rf target/inside/repo/.git
git add target/inside/repo/
```

If already staged as submodule:

```bash
git rm -r --cached target/inside/repo/
rm -rf target/inside/repo/.git
git add target/inside/repo/
git commit -m "Add dir contents (fix nested repo)"
```

### Never guess or mutate a secret you only saw masked

A redacted/masked value in a config file or terminal output means you do **not** have the credential — you have a placeholder. Never run a credential-mutating statement (`ALTER USER ... PASSWORD`, `redis CONFIG SET`, key rotation) with a value you inferred, guessed, or copied from documentation: it silently replaces a working secret with a wrong one and locks out every service using it, and the original is unrecoverable from the masked view.

**Rule:** if you must change a credential, read the real value from a file programmatically without printing it, and verify connectivity immediately afterwards. If you have already broken it, restore from the same file and re-verify with a real connection probe (`db:show`, a ping, a test run) — not by re-reading the masked output.

```bash
PW=$(grep -E '^DB_PASSWORD=' .env | head -1 | cut -d= -f2-)
printf "ALTER USER u WITH PASSWORD '%s';\n" "$PW" | docker exec -i pg psql -U u -d postgres -q
php artisan db:show     # proof it works again
```

A one-off "let me just set it to something I remember" is how a working dev environment becomes a five-minute outage with no undo.

New clones may lack both global and per-repo `user.name`/`user.email`.
Commits fail with `empty ident name`.

**Fix — set per-repo config before first commit:**

```bash
git config user.email "user@users.noreply.github.com"
git config user.name "username"
```

Detect from `gh auth status` or set manually.

## Verification

- `git status` shows no unexpected submodule entries.
- `git diff --cached --stat` shows actual file additions, not just mode changes.
- Commit and push succeed without warnings about embedded repos.
