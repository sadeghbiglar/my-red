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

## 2. Never
- Do not clone a second copy of the repo.
- Do not switch branches unless asked.
- Do not push straight to `academy` without asking.
- Do not add, rename, or delete git remotes.

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
php -m | grep pdo_sqlite        # absent → sqlite suite cannot run
codegraph status .              # `codegraph sync` if stale
php artisan boost:mcp
```
Fix anything broken before continuing. Never claim a tool was used when it wasn't.

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