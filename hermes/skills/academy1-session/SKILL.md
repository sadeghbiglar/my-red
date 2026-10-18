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

Repo: `/home/runner/academy1`. Origin: `sadeghbiglar/academy1`.
Only remote is `origin` — **never add, rename, or delete remotes.**

## 0. Branch model — main is the release branch (set 2026-10-17)
- **`main`** — release branch. Carries everything already approved. GitHub default
  branch. **Protected**: 1 approving review required, enforce_admins on, no force-push,
  no deletions, conversation resolution required. A plain `git push origin main` will
  be REJECTED — that is intended, it is the mechanism that makes approval real.
- **`academy`** — the working branch. All new work happens here and is pushed here.
  `academy` tracks `origin/academy` (it used to track `origin/beta`, which meant a bare
  `git push` from this branch would have written to `beta`).
- **`beta`** — historical, left alone at `660e1c6`.

Promotion flow: commit to `academy` -> user approves -> open a PR `academy` -> `main`
-> the user merges. Do NOT push straight to `main`, and do not merge `academy` into
`main` locally to "deliver" work — that is what the PR is for.

The ephemeral-runner workflow builds the working tree with `git checkout -B academy
origin/main` (it used to be `origin/beta`, which silently discarded every `academy`
commit since the previous runner rebuild).

Stack: Laravel 13.35 / PHP 8.5.11 / Livewire 4 / mary UI / morilog-jalali.
DB: MySQL 8 `academy1` (11 tables). Tests run on in-memory **sqlite**.

## 1. Never
- Do not clone a second copy of the repo.
- Do not switch branches unless asked.
- Do not push to `main` (protected; promotion is a PR the user merges).
- Do not commit the lockfiles that are dirty on arrival (`composer.json`,
  `composer.lock`, `package-lock.json`) unless the change is intentional — they are
  pre-existing drift from the runner rebuild, not your work.

## 2. Session start sequence
```bash
cd /home/runner/academy1
git branch --show-current
git status --short
bash /home/runner/.hermes/skills/academy1-report/scripts/report.sh
```
There is **no** `scripts/academy1-status.sh` in this repo — do not try to run it. The
report script prints branch, commits, dirty files, unpushed, the `:8000` listener,
tool availability, and (via `roadmap.sh`) open-issue counts per milestone.

## 3. Server
**No systemd unit supervises it** — verified 2026-10-17: `academy1-serve.service` does
NOT exist, and `systemctl --user list-units | grep hermes` is empty. The server is an
unsupervised background process serving `0.0.0.0:8000` (`/`, `/students`, `/teachers`);
manage it by PID, never by service name.

**Never `pkill -f 'artisan serve'`** — it can match the very shell running the
command and kill the tool call (this actually happened once; the call died of
SIGTERM). Resolve one PID, and take it by PID fields rather than by substring:
```bash
OLD=$(ps -eo pid,cmd | awk '$2=="php" && $3=="artisan" && $4=="serve" {print $1}' | head -1)
[ -n "$OLD" ] && kill "$OLD"
```

## 3a. Roadmap, date layer, and the autopilot

### REQUIREMENTS.md is the source of truth It lists 15 domains
(a private academy needs: students, teachers, subjects, courses, enrolment,
scheduling, attendance, grades, fees/invoices/payments, expenses, reports,
dashboard, auth, settings) and 9 non-negotiable rules R1-R9.

R1-R3 are the ones that bite: **everything shamsi in the UI, one shared date
picker component, invoice/transcript/receipt must exist and be printable.** Never
add a field that shows or accepts a gregorian date.

GitHub: repo `sadeghbiglar/academy1`, milestones `M0 بنیاد و زیرساخت` … `M8 اتمام
و سخت‌سازی`. Issues #2-#27 are older/smaller; #28-#64 are the decomposed plan.
`scripts/roadmap.sh` (run by report.sh) prints open counts per milestone.

### Where the date/number layer lives
`app/Support/helpers.php` is the ONLY conversion layer. Never call
`Jalalian::fromDateTime` in a view directly.
- display: `jalali_date($date)` — DB stays gregorian so ordering and `whereBetween` work
- input: `miladi_date('۱۴۰۳/۰۵/۱۲')` → `'2024-08-02'`; throws
  `InvalidArgumentException` on impossible dates instead of rolling over
- numbers: `parse_number()` returns **null** for empty, not 0 — an empty tuition
  field is not a zero tuition field. Parse BEFORE validating, never validate raw.
- digits: `to_english_digits()` / `to_persian_digits()` (display only)

**Two traps already hit and fixed here — read before touching this file:**
1. Do not normalise date separators by DELETING them; `1403 05 12` becomes
   `14030512`. Map them to a slash.
2. `Jalalian::fromTimestamp()` and `Jalalian::fromDateTime('@'.$ts)` parse as UTC
   and shift the shamsi day by one under Asia/Tehran. Go through
   `Carbon::createFromTimestamp($ts, date_default_timezone_get())`.

Shamsi facts worth not re-deriving: months 1-6 have 31 days, 7-11 have 30, esfand
29 (30 only in a leap year). **1403 and 1399 ARE leap; 1404 is NOT.**

### Tests are class-based PHPUnit, NOT Pest
`test()` and `->throws()` do not exist here — every suite is a `class ... extends
Tests\TestCase` with `test_snake_case` methods. Writing Pest syntax fails with
"Call to undefined function test()".

### The autopilot runs itself — never wait to be told, never park
The user authorised continuous development, twice and explicitly: no "go" needed,
in this session or any future one. A turn ending is mechanical, not a pause.
**Never end a turn asking whether to continue** — finish one issue-sized unit,
report it, and go straight into the next.

Mechanism:
- `.academy/queue.json` (in the repo) is the queue: ordered issues with a `why`,
  a `done` list, and `in_progress` so a half-finished issue RESUMES instead of
  restarting. This file IS the memory across sessions — the conversation is not.
- `scripts/academy-autopilot.sh` runs at boot (workflow step 14b): syncs to
  origin/academy, reads the queue, drives ONE issue, gates on the full suite +
  pint, commits and pushes to `academy`. `continue-on-error: true` so it never
  takes down the three services.
- `report.sh` prints an `== AUTOPILOT ==` block: what is done, queued, in
  progress, and the tail of the last run (`/tmp/autopilot.log`).

**On every session start, read `.academy/queue.json` and work `next[0]` (or
`in_progress` if set).** After finishing: move the issue to `done`, drop it from
`next`, update `updated`. A partial attempt stays `in_progress` — unfinished is
better than lost.

## 3b. Livewire components that write to a shared value
When a component mirrors a parent property (`#[Modelable]`), the invariant is:
**invalid input must never reach the stored value.** Set an error and leave the
value untouched, so a bad keystroke cannot corrupt a record that is already saved.
Test it by setting a good value FIRST, then pushing invalid input, and asserting the
good value survived.

A view referencing a value that is not a passed variable or a computed property
fails at render with "Undefined variable" — in Blade, read computed state as
`$this->propertyName`, not a bare `$propertyName` you never defined.

When the picker must sync in both directions, `updatedValue()` (parent -> child) and
`updatedDisplay()` (child -> parent) are both required; without the first, opening an
existing record for edit shows an empty date.

## 4. Verify tooling, never assume
```bash
php -m | grep pdo_sqlite                  # required; install: sudo apt-get install -y php8.5-sqlite3
codegraph status .                        # then `codegraph sync` if stale
php artisan boost:mcp                     # Boost MCP server (also in ~/.hermes config)
```

The PHP version is 8.5, so the package is `php8.5-sqlite3`. If the module is absent,
install it and re-run `php artisan test` rather than reporting the suite as
unrunnable — the whole suite depends on it.

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

## 8a. MissingAppKeyException — the empty-.env trap
`Illuminate\Encryption\MissingAppKeyException: No application encryption key has been
specified` means `.env` has `APP_KEY=` **empty**. It reappears every time the repo is
re-cloned or `.env` is regenerated from `.env.example` / `.env.example.mysql`, because
all three ship `APP_KEY=` blank — Laravel never auto-generates it outside `composer
create-project`.

Check and fix:
```bash
cd /home/runner/academy1
grep '^APP_KEY=' .env | cut -d= -f2 | wc -c          # must be >= 32
php artisan key:generate --force
```
Never commit `.env` (it is gitignored) and never put a real key in `.env.example`.
`report.sh` now auto-generates a missing key on every session run, so the error cannot
survive into a new session. The boot workflow runs `key:generate --force` right after
copying `.env.example.mysql`, which is the template that ships `APP_KEY=` blank.

## 8b. PCRE2 has no `\u{...}` — use `\x{...}`
`preg_replace('/[\s\-\u{200C}]/u', ...)` fails at COMPILE time with "PCRE2 does not
support \F, \L, \l, \N{name}, \U, or \u". Match the code point as `\x{200C}`. The
warning is emitted per call and the pattern silently matches nothing, so a
"validated" field quietly accepts everything — check the rule actually rejects a
bad value, do not just assert it passes a good one.

## 9. Test gotchas
- The suite is class-based PHPUnit, not Pest: `class FooTest extends Tests\TestCase`
  with `test_snake_case` methods and `->throws()` via `$this->expectException()`.
- Test counts grow with the roadmap; do not treat a specific total as fixed.
- `RefreshDatabase` on in-memory sqlite; `phpunit.xml` pins `DB_CONNECTION=sqlite`,
  `DB_DATABASE=:memory:`.
- Livewire component test names are the file-derived names `pages::students.index`
  and `pages::teachers.index`, not class names.
- The students component is a single-file Livewire component in
  `resources/views/pages/students/⚡index.blade.php` (34 KB). The `rules()` method is
  `protected`, so validation rules are invisible from the test's perspective.
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