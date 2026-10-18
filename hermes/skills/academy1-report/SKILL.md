---
name: academy1-report
description: "Use every session start to report latest academy1 changes."
version: 2.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [academy1, laravel, livewire, git, session-start, report]
    category: software-development
---

# academy1 Session Report

## When to Use
Every session. Run the report in §1 first, before any repo work — a feature, a bug
fix, a test run, or a plain question about the code. It is cheap and it is the
thing that tells you what state the repo is actually in.

Renamed from an older session skill when this repo became the only one on disk.
**Nothing here refers to any other repo** — do not reintroduce a dead repo's name,
branches, upstream, or database name.

Companion skill: `academy1-session` holds the deep Laravel/Livewire gotchas. Read it
when the work touches code; this skill covers the *start-of-session report*.

## 1. Report on every run — this is mandatory

At the start of every session, before answering anything repo-related, produce a
short report of the latest academy1 changes. Never skip it silently; if the repo is
missing or git fails, say so explicitly instead of reporting nothing.

```bash
cd /home/runner/academy1
bash /home/runner/.hermes/skills/academy1-report/scripts/report.sh
```

The script prints branch, last 8 commits, dirty files, diffstat, unpushed commits,
last commit date, whether `:8000` is listening, and tool availability. Summarise it in
5-10 lines: what moved, what is uncommitted, whether the dev server is up. No tables.

Do not trust a snapshot — `scripts/report.sh` re-derives all of it every run, so quote
its output rather than this list.

## 1a. This machine is an ephemeral runner — read this before touching ~/.hermes
The skills, memories, config and cron under `~/.hermes` are **restored from
`sadeghbiglar/my-red` → `hermes/` at every boot and pushed back at shutdown**.
A local `rm` here does not survive; edit `my-red/hermes/` and push, or the next boot
reverts it. `academy1` itself has no workflow — the machine is built by
`my-red` → `.github/workflows/ssh.yml`.

Full reference (Tailscale naming, the `academy-1` incident, the concurrency guard,
how to edit the workflow without a local clone): `references/ephemeral-runner.md`.

Corollary: when the user asks to delete a skill, memory, cron job or config key, ask
or check `my-red/hermes/` — editing only the local copy is a temporary fix.

## 1b. The three services on this machine
- `:8000` — Laravel academy1, started by the workflow via `nohup php artisan serve`.
  Unsupervised: manage it by PID, never `pkill -f 'artisan serve'`.
- `:20128` — 9router, also `nohup` from the workflow.
- `:8080` — `reserve`, the hall-booking system. The ONLY one under systemd
  (`reserve.service`, enabled, `Restart=always`). `report.sh` reports it and starts it
  if it is down; it restarts only when HTTP != 200. Install, health endpoint, and the
  backup/restore wiring: `references/reserve-service.md`.

## 1c. Finish the job — do not hand back a command the user could have run
When the user asks for an install, fix, or cleanup here, they are asking for it to be
**done**, not for a recipe. This skill exists because an earlier pass ended with "run
this yourself" for a step that was entirely within reach.

- Run every step you can reach. Push the commit, restart the service, set the secret,
  disable the workflow, restart the gateway — do not stop one step short and present it
  as a next action.
- Hand off a manual step ONLY when it genuinely requires something you cannot
  possess: a web-console login you must not type credentials into, a physical device,
  a billing decision. Then say so in one line, name exactly why, and state whether the
  task is already correct without it.
- Keep going past the hand-off. The un-doable step is not a reason to stop the other
  nine steps, and it is never a reason to leave the deliverable incomplete.
- A partial fix reported as complete is worse than a blocked step reported honestly:
  state which parts are verified, which are unverified, and what would close the gap.

## 1d. Branch model — main releases, academy carries the work
`main` is the release branch (GitHub default, protected). `academy` is the working
branch and tracks `origin/academy`. New work: commit on `academy`, push to
`academy`. Promotion: open a PR `academy` -> `main`, the user reviews and merges.
Never merge locally to "deliver" work to `main`, and never force-push either branch.

**Check the tracking config before any bare `git push`.** A working branch whose
`branch.<name>.merge` points at a differently-named remote branch sends the push to
the WRONG branch and every exit code is still 0:
```bash
git config --get branch.academy.merge     # must be refs/heads/academy
```
Repair with `git branch --set-upstream-to=origin/academy academy` after pushing the
branch under its own name.

## 1e. Never hand back a "should I continue?" — a turn ending is not a pause
The user has authorised continuous work on this project, explicitly and twice
("keep going without waiting for my go-ahead", "why did you stop?"). Turns end
by design; that is a mechanical boundary, never a reason to stop or to ask.

- When work is authorised and remains, **end the turn with the next unit done or
  started, never with a question.** `Should I continue?`, `Bگوید ادامه بدهم؟` and
  `برای قدم بعدی چه کنم؟` are failures when the answer is already known.
- Choose the smallest unit that survives the turn boundary: one issue, one commit.
  A chunk that can be finished and reported is always better than an open-ended
  "and now I will also..." that gets truncated.
- If a chunk genuinely cannot finish, commit the partial work, leave it recorded
  as in-progress, and continue with the next unit — do not park the session.
- Report progress, not permission requests. The user reads reports; they did not
  ask to be a scheduler.

Only a genuine BLOCKER justifies stopping: something needing a decision only the
user can make, or a destructive/irreversible action. Then ask that one question,
having already done everything else.

## 1f. The roadmap lives in GitHub AND in a repo-side queue
`REQUIREMENTS.md` at the repo root is the requirement source of truth (domains +
the non-negotiable rules). It is decomposed into milestones and issues in
`sadeghbiglar/academy1`. `.academy/queue.json` in the repo is the *work order*:
ordered issues with a `why`, a `done` list, and `in_progress` so a half-finished
issue resumes instead of restarting. `scripts/roadmap.sh` and
`scripts/autopilot-status.sh` (both invoked by `report.sh`) print both — run them
before answering "what's next" so the answer comes from the tracker, not memory.

Because the runner is destroyed and rebuilt, the queue file in the repo IS the
cross-session memory. The conversation is not. Depth on the boot-time autopilot
(`scripts/academy-autopilot.sh`, workflow step 14b) is in `academy1-session` §3.

## 2. Never
- Do not clone a second copy of the repo.
- Do not switch branches unless asked.
- Do not add, rename, or delete git remotes.
- **Never push to `main`.** `main` is the release branch and is protected on the
  remote (1 approving review, `enforce_admins`, no force-push). New work is
  committed and pushed to `academy` freely — that is the working branch and it is
  expected to be dirty. Promotion to `main` happens only as a PR the user merges
  after approving. See §1d.

## 2a. When a repo moves or dies, sweep its path everywhere
Deleting a repo dir does **not** retire it: MCP servers, `terminal.cwd`, cron outputs,
and other skills all keep absolute paths to it, and a `cd <gone>` MCP server fails to
start while looking like a broken tool. After any move, grep the whole Hermes home and
fix every hit:

```bash
grep -rn '<old-path>' /home/runner/.hermes --include='*.yaml' --include='*.md' --include='*.json'
```

Rewriting the *skill* is not enough — rename it, because the skill name itself is what
shows up in the per-session skill list and drives false reports of a dead repo.
`~/.hermes/config.yaml` is locked to the user (`write_file`/`patch` refuse it); hand off
a single `sed -i` command, then re-read the file to confirm. See the `hermes-agent`
skill for the handoff format and the gateway-restart step MCP changes require.

## 3. Session start sequence
```bash
cd /home/runner/academy1
git branch --show-current
git status --short
git fetch origin
git log --oneline origin/academy..HEAD     # unpushed work
```

## 4. Read project rules first
Root `AGENTS.md` is authoritative — read before touching code and keep it in context.
Do not re-derive what it documents.

## 5. Verify tooling, never assume
```bash
php -m | grep pdo_sqlite        # required for the test suite
codegraph status .              # `codegraph sync` if stale
php artisan boost:mcp
```
Fix anything broken before continuing. Never claim a tool was used when it wasn't.

If `pdo_sqlite` is missing, install it and re-check rather than reporting the
suite as unrunnable:
```bash
sudo apt-get install -y php8.5-sqlite3 && php -m | grep pdo_sqlite
```
The module name tracks the PHP version — the runner carries PHP 8.5, so the
package is `php8.5-sqlite3`, not `php-sqlite3`.

## 6. Dev server
Nothing supervises it — find the PID and act on the PID:
```bash
ps -eo pid,cmd | awk '$2=="php8.5" {print}'
```
**Never `pkill -f 'artisan serve'`** — it can match the very shell running the command
and kill the tool call.

## 7. Before committing
```bash
git status
git diff
php vendor/laravel/pint/builds/pint --test   # vendor/bin/pint is blocked by the
php artisan test                              # gateway script-size scanner (>1 MiB)
composer validate --no-check-publish
```
Invoke pint through `php vendor/laravel/pint/builds/pint`.

## 8. Load-bearing gotchas (short list — full detail in `academy1-session`)
- Stale route cache → Livewire `->set()` returns 404 and `->html()` is `''`. Run
  `php artisan route:clear && php artisan route:cache` before reading app code.
- Livewire `SubsequentRender` disables exception handling; a failing subsequent
  render degrades to a 404 with a null component and no trace.
- Never run two suites at once — they share one database.
- Pint must be called as `php vendor/laravel/pint/builds/pint`.

## 9. Mandatory process skills
`superpowers` plugin at `~/.hermes/plugins/superpowers`. Load before acting:
brainstorming before plan mode, systematic-debugging for bugs,
test-driven-development before writing behavior, verification-before-completion
before claiming done. Invoke as `skill_view("superpowers:brainstorming")` etc.
The `using-superpowers` bootstrap is injected only on the **first turn**
(`pre_llm_call` hook, `is_first_turn`); a session that compacted past it lost it.