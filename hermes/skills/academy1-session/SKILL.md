---
name: academy1-session
description: "Use when working in the academy1 repo."
version: 1.0.0
author: Hermes Agent
license: MIT
platforms: [linux]
metadata:
  hermes:
    tags: [academy1, laravel, livewire, bootstrap, session-start]
    category: software-development
---

# academy1 Session Bootstrap

## When to Use
Any session touching `/home/runner/academy1`: feature, bug fix, refactor, test run, or a
structural question about the code. Run §2 before real work.

Repo: `/home/runner/academy1`. Branch: `academy`. Origin: `sadeghbiglar/academy1`.
Only remote is `origin` — **never add, rename, or delete remotes.**

Stack: Laravel 13.35 / PHP 8.5.11 / Livewire 4 / mary UI / morilog-jalali.
DB: MySQL 8 `academy1` (11 tables). Tests run on in-memory **sqlite**.

## 1. Never
- Do not clone a second copy of the repo.
- Do not switch branches unless asked.
- Do not push straight to `academy` without asking.

## 2. Session start sequence
```bash
cd /home/runner/academy1
git branch --show-current
git status --short
bash scripts/academy1-status.sh        # git, server, routes, DB, tools, tests
```
The status script is the single best overview — it covers everything in §4 at once.
`SKIP_TESTS=1 bash scripts/academy1-status.sh` skips the suite for a fast check.

## 3. Server
Supervised by a **user-level systemd unit**, not an ad-hoc background job:
```bash
systemctl --user status academy1-serve.service
systemctl --user restart academy1-serve.service
```
Serves `0.0.0.0:8000` → `/`, `/students`, `/teachers`. Enabled, so it survives reboot.

**Never `pkill -f 'artisan serve'`** — it kills the supervised server *and* can match the
very shell running the command (this actually happened once; the tool call died of SIGTERM).
Resolve one PID, and take it by PID fields rather than by substring:
```bash
OLD=$(ps -eo pid,cmd | awk '$2=="php" && $3=="artisan" && $4=="serve" {print $1}' | head -1)
[ -n "$OLD" ] && kill "$OLD"
```

## 4. Verify tooling, never assume
```bash
php -m | grep pdo_sqlite                  # must be present
codegraph status .                        # then `codegraph sync` if stale
php artisan boost:mcp                     # Boost MCP server (also in ~/.hermes config)
```

## 5. THE stale-route-cache trap — the single most costly bug in this repo
A route cache built **before** a `composer require` / package-discovery run makes Livewire's
`POST /livewire/update` return **404**, while every full-page `GET` still returns 200.

Symptom shape that identifies it:
- `Livewire::test(...)` on a fresh mount works — HTML renders, props read fine.
- The **first `->set()` / `->call()` returns 404**, and then
  `->get('prop')` returns `null`, `->html()` returns `''`, `->errors()` returns `[]`,
  and no exception is raised anywhere.
- `assertHasNoErrors()` passes and `assertHasNoErrors`/`assertSet(..., false)` then fail
  because the component object is `null` — assertions on a null, not on behaviour.
- Reads from the DB show nothing was written, so it looks like the model or the
  validation is broken. Both are innocent.

Fix:
```bash
php artisan route:clear
php artisan route:cache
```
Cause: `bootstrap/cache/routes-v7.php` predates `packages.php`/`services.php`, so the
Livewire update endpoint is missing from the cached route table.

Prevention (already committed in `composer.json`): `post-autoload-dump` now runs
`@php artisan optimize:clear`, so any composer operation drops stale caches.

**Rule:** when Livewire test assertions fail with `null` where a value should be, and
the HTML is `''`, check the route cache *before* reading application code. Reach for
`route:clear` first.

## 6. Boost
- `boost.json` must contain a non-empty `agents` array (`["claude_code"]`) or
  `php artisan boost:update` **always** fails with "Please set up Boost with
  [php artisan boost:install] first." — that message does **not** mean Boost is absent,
  it means `Config::getAgents()` is empty. The explicit-flag install path
  (`--guidelines --skills --mcp`) never writes `agents`; only the interactive
  multiselect does. Add the key by hand once.
- Guidelines live in `CLAUDE.md`; `AGENTS.md` is kept as a **copy** of it. Re-copy after
  any `boost:update`: `cp CLAUDE.md AGENTS.md`.
- Skills land in `.claude/skills/` (6 skills). MCP config in `.mcp.json`.

## 7. Dependency placement
`laravel/boost` belongs in `require-dev`, not `require` — a prior session moved it into
`require` and shipped an agent tool into production deps. Verify placement with:
```bash
php -r '$l=json_decode(file_get_contents("composer.lock"),true);foreach(["packages","packages-dev"] as $k){foreach($l[$k] as $p){if($p["name"]==="laravel/boost")echo "$k\n";}}'
# must print: packages-dev
```
After editing composer.json: `composer update --lock --no-install` then re-check, since
`--lock` alone does not move a package between `packages` and `packages-dev`.

## 8. Before committing
```bash
git status
git diff
php vendor/laravel/pint/builds/pint --test    # vendor/bin/pint is blocked by the
php artisan test                               # lifecycle guard (>1 MiB binary)
composer validate --no-check-publish
```
Invoke pint through `php vendor/laravel/pint/builds/pint`; calling `vendor/bin/pint`
directly is refused by the gateway's script-size scanner.

## 9. Test gotchas
- 20 tests / 69 assertions, all green. `RefreshDatabase` on in-memory sqlite;
  `phpunit.xml` pins `DB_CONNECTION=sqlite`, `DB_DATABASE=:memory:`.
- **`vendor/bin/pint` is blocked** (see §8). `php vendor/.../builds/pint` works.
- Livewire component test names are the file-derived names `pages::students.index` and
  `pages::teachers.index`, not class names.
- The students component is a single-file Livewire component in
  `resources/views/pages/students/⚡index.blade.php` (34 KB). The `rules()` method is
  `protected`, so validation rules are invisible from the test's perspective.
- `miladi_date()` (shamsi → gregorian) and `jalali_date()` live in
  `app/Support/helpers.php`, autoloaded via composer `files`. A shamsi birth date is
  validated by `regex:/^[0-9]{4}\/[0-9]{2}\/[0-9]{2}$/` — slashed format only, so
  `1380-05-12` is *meant* to fail validation.
- Teachers list orders `orderByDesc('id')` deliberately: without a deterministic order
  MySQL may repeat or skip rows across pages.

## 10. Debugging technique that worked
Livewire's `SubsequentRender` **disables exception handling**, so a failing subsequent
render degrades silently into a 404 with a null component instead of a trace. To see
the truth, reach into the Testable:
```php
$r = new \ReflectionObject($c);            // $c is the Testable
$p = $r->getProperty('lastState'); $p->setAccessible(true);
$state = $p->getValue($c);
$state->getResponse()->status();           // <- the real HTTP status
$state->getResponse()->getContent();       // <- the real body
```
Note `$c->lastState` does **not** work — `Testable::__get()` proxies unknown
properties to the component, which raises "Property [$lastState] not found on component".