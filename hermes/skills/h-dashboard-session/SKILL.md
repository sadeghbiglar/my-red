---
name: h-dashboard-session
description: "Use when working in h-dashboard repo."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux, macos]
metadata:
  hermes:
    tags: [h-dashboard, laravel, bootstrap, codegraph, git, session-start]
---

# h-dashboard Session Bootstrap

## When to Use
Any session touching `/home/runner/h-dashboard`: new feature, bug fix, refactor, test run,
or a plain structural question about the code. Run sections 1-5 before real work.

Repo: `/home/runner/h-dashboard` (also the configured Hermes `terminal.cwd`).
Branch: `rebecca`. Canonical upstream: `asgarimehdi/h-dashboard`, branch `beta`.
Only remote is `origin` (this server's fork); **never add, rename, or delete remotes.**

## 1. Never
- Do not clone a second copy of the repo.
- Do not switch branches unless asked.
- Do not push dev work straight to `beta`.
- Do not hardcode a fork URL or branch name — read `git remote -v` / `git branch --show-current`.

## 2. Session start sequence
```bash
cd /home/runner/h-dashboard
git remote -v
git branch --show-current
git status
git fetch origin
git merge origin/beta     # resolve conflicts; never rebase published work
```
Push only after step 4 verification passes.

## 3. Read project rules first
Root `AGENTS.md` is authoritative — read before touching code and keep it in context.
It already documents CodeGraph, Boost/Context7/GitHub MCP, Pest, Playwright, conventions,
and the gotchas table. Do not re-derive them.

## 4. Verify tooling, never assume
```bash
codegraph status .        # must be up to date; else `codegraph sync`
hermes mcp list           # codegraph, laravel_boost, context7, github enabled
```
Fix anything broken before continuing. Never claim a tool was used when it wasn't.

## 5. CodeGraph first for structural questions
Before grep/glob/Read crawling to understand structure, call CodeGraph MCP
(`mcp__codegraph__codegraph_explore`) or the CLI:
```bash
codegraph explore "how does AccessService accessibleUnitIds resolve unit hierarchy"
codegraph query "HardwareAuditObserver" --limit 5
```

## 6. Before committing
```bash
git status
git diff
vendor/bin/pint --test
composer test        # pest
```
Clear commit message, then `git push origin <current-branch>`.

## 7. Pull requests
When the user says `pr`, open a PR from the current branch to `beta` of
`https://github.com/asgarimehdi/h-dashboard`. **Do not merge** unless asked.

Two tooling pitfalls, both verified 2026-10-06 (issue #818 / PR #822):

- **Use `gh pr create`, not the GitHub MCP `create_pull_request`.** The MCP tool
  silently drops the required `base` argument — the call fails twice with
  "missing required argument(s): base" no matter how the payload is built, and
  the body never reaches the server. `gh` works:
  ```bash
  gh pr create --repo asgarimehdi/h-dashboard --base beta \
    --head Shabakebehdasht:rebecca --title "..." --body-file /tmp/pr.md
  ```
  Write a long body to a scratch file and pass `--body-file`; inline
  `--body` mangles backticks and newlines.
- **No `--maintainer-can-modify` flag** on this machine's `gh` — it errors and
  prints usage. Omit it; the fork relationship already allows maintainer edits.
- Watch CI with `gh run watch <run-id> --repo asgarimehdi/h-dashboard --exit-status`
  (run id from `gh pr checks <pr> --repo asgarimehdi/h-dashboard`). `--repo` is
  required — without it the run id does not resolve from this fork's context.

### A Sanctum ability assertion is worthless unless the session is detached
`Laravel\Sanctum\Guard::__invoke()` checks the `web` guard **first**. If a session
still resolves, it returns a `TransientToken` whose `can()` is unconditionally
true and the stored `abilities` are **never read** — so asserting "this token
cannot POST /api/hardware" against a logged-in session yields **422 from
validation, not 403 from the gate**. The test proves nothing.

```php
$token = Livewire::actingAs($user)->test('some.component')->get('someToken');
$this->app['auth']->guard('web')->logout();
$this->app['auth']->forgetGuards();
// now the request authenticates from the Bearer token ALONE
```

This is the same artifact that made issue #840's own "token survives logout"
measurement unreproducible. It is also the real threat model when a plaintext
token sits in rendered HTML: whoever reads it uses it with no session of their own.

Table name is **`hardwares`**, not `hardware`, for `assertDatabaseMissing`.

### `#[Locked]` throws in tests; it does not return 419
`CannotUpdateLockedPropertyException::render()` maps to a 419 response **only when
`app.debug` is off**. The test env has debug on, so `$component->set($locked, …)`
surfaces the exception. Assert it with `expectException`, not `assertStatus(419)`.
`#[Locked]` is also only *defence in depth* — it stops a client swapping a
server-written property, it does **not** remove a plaintext that is already
rendered into the HTML.

### Never run two suites at once — they share `h_dashboard_test`
`composer test` in the background while an interactive `php artisan test` runs
interleaves `RefreshDatabase` on the **same** database. Symptoms are misleading:
`drop table … cascade` failures, and unrelated tests failing that pass in
isolation. Kill the background run (`process_manage action=kill`) and re-run
serially — the results you got before the collision mean nothing.

### A test helper's override keys are often NOT fillable
`TicketsInboxLivewireTest::createTicket()` reads `$overrides['unit']` /
`['user']` for its defaults but then `array_merge`s them into the create
array, where `Ticket`'s `$fillable` has only `unit_id` / `user_id`. Passing
`'unit' => $unit` therefore lands the ticket in `Unit::first()` **silently** and
the ticket appears to be out of the viewer's scope. Set the real columns.

Two more traps in the same family:
- `createUserWithUnit()` returns keys `user` / `unit` — destructuring
  `['creator' => …]` throws `Undefined array key`.
- `createUserOnUnit()` grants **no Spatie permission**, so a viewer built with
  it cannot open a permission-gated page and the component under test never
  runs. Also `accessibleUnitIds()` reads `session('current_unit_id')` first and
  only falls back to the pivot, so seed it or the scope is `[]`.

### `Todo::accessible()` / `Builder::accessible()` is a PHPStan error
The scope lives on `HasOrganizationalScope`, so neither the static nor the
`Builder` form resolves at level 6 (`undefined static method` /
`undefined method Builder::accessible()`). Use an explicit
`->whereIn('unit_id', app(AccessService::class)->accessibleUnitIds())` — which
is also the form that fails closed.

`$ticket->setRelation(...)` after `Ticket::query()->whereIn(...)->find(...)`
reports `Cannot call method setRelation() on stdClass` (the known `@mixin`
gotcha). Fix with `/** @var Ticket|null $ticket */` above the assignment — and
**do not** switch to `$ticket->task = …`: that routes through `setAttribute()`,
parking the model in `$attributes` where a later `save()` tries to write a
non-existent column.

### Editing a Livewire component shifts the line-keyed PHPStan baseline
Any edit inside `resources/views/livewire/tickets/⚡*.blade.php` moves line
numbers, so `phpstan-baseline.neon` entries stop matching and `composer phpstan`
reports ~27 `ignore.unmatched (non-ignorable)` errors that are pure line drift.
Fix the genuinely new errors first, then:
```bash
composer phpstan-baseline && composer phpstan   # must print "[OK] No errors"
```
Do not hand-edit the baseline, and do not assume every reported error is real —
separate your own from the line-shift noise first (`git stash` + rerun gives the
true pre-existing count).

To prove the regeneration added **nothing**, diff the baseline's `message:` lines
as a multiset before/after and normalise the anon-component line key
(`…blade\.php\:\d+\:\:` → `…blade\.php\:\:\:`). The count must be identical and
`Counter(new) - Counter(old)` must be empty — a plain `git diff` looks like 21
additions even though every one is just `:4::` → `:7::`.

## 8. Superpowers skills are mandatory
`superpowers` plugin installed at `~/.hermes/plugins/superpowers` (v6.4.2, 15 skills,
source `obra/superpowers`, installed with `--force` after manual entrypoint review on
2026-10-05). Load the process skill before acting:
brainstorming before plan mode, systematic-debugging for bugs, test-driven-development
before writing behavior, verification-before-completion before claiming done.
Invoke as `skill_view("superpowers:brainstorming")` etc.

The `using-superpowers` bootstrap is injected only on the **first turn** of a session
(`pre_llm_call` hook, `is_first_turn`). A session that compacted over its first turn
lost it — that is the known failure mode, not a broken install. `AGENTS.md` above
repeats the load-bearing rules so they survive compaction.

## 9. Docs and audit skills
- `read-the-damn-docs` (software-development/read-the-damn-docs) — read official/current
  docs before implementing against any third-party API or library. Context7 MCP for
  version-specific Laravel/PHP docs.
- `improve` — shadcn audit skill, audit-only, do NOT execute its findings unless asked.