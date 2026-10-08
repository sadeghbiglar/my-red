---
name: laravel-patterns
description: "Laravel pitfalls: model events, cache batching, factories."
version: 1.0.0
author: Hermes
license: MIT
metadata:
  hermes:
    tags: [laravel, php, pitfalls, model-events, cache, testing]
    category: software-development
---

# Laravel Patterns & Pitfalls

## When to Use

Use this skill when working on any Laravel project — implementing model observers, designing cache invalidation, writing tests with factories, managing event listeners, or debugging FK constraint violations.

Procedures and hard-won rules for Laravel development — model events, cache invalidation, testing with factories, database constraints. Standalone rules; the project's AGENTS.md provides domain-specific context.

## Model Events

### `saved` event fires twice during `update()`

In Laravel 13, `Model::saved()` can fire multiple times per `update()` call — once before changes are committed (changes array empty, originals not yet reset) and once after. Use `getChanges()` to detect what actually changed, not `isDirty()`.

**Rule:** In `saved` callbacks, detect attribute changes via `$model->getChanges()` (returns only attributes persisted in the last save), not `isDirty()` (compares against original loaded state, unreliable mid-event).

For detecting "was this a create or update", use `$model->wasRecentlyCreated` — but note it stays `true` on subsequent saves of the same in-memory instance. Reload from DB if you need a clean state.

### `deleted` event has no dirty attributes

`isDirty()` and `getChanges()` are both empty in `deleted` events. Handle delete-specific logic separately from saved/update logic.

## Cache Invalidation Batching

### Batch mode needs a separate flag, not an empty-array check

When implementing request-scoped batch buffering for cache increments, use a dedicated `bool $batching` flag — NOT `!empty($this->pending)`. An empty pending array at batch start means `empty()` returns true, bypassing the buffer entirely.

```php
// WRONG — empty array bypasses buffer on first increment
if (! empty($this->pending)) { ... }

// CORRECT — separate flag tracks batch scope
private bool $batching = false;
public function batch(Closure $callback): mixed {
    $this->batching = true;
    $this->pending = [];
    try {
        $result = $callback();
    } finally {
        $this->flushPending();
        $this->batching = false;
    }
    return $result;
}
```

Always use `try/finally` in `batch()` to guarantee `flushPending()` runs even on exception.

## Testing with Factories & Cache

### Set cache AFTER factory setup, not before

Model factories trigger `saved` events that increment cache versions. If you `Cache::put('x_version', 0)` before `User::factory()->create()`, the factory's internal model creation will bump the version back up. Always set cache assertions AFTER all factory/model creation is complete.

```php
// WRONG
Cache::put('gis_version', 0);
$user = User::factory()->create(); // creates Person -> bumps gis to 1
// gis_version is now 1, not 0

// CORRECT
$user = User::factory()->create();
Cache::put('gis_version', 0); // reset AFTER factory side effects
$person->update([...]);
$this->assertEquals(0, Cache::get('gis_version'));
```

### User factory creates Person in `afterMaking`

If `UserFactory` creates a backing `Person` via `afterMaking()`, the Person's `saved` event fires during factory setup. Factor in these cascading cache invalidations when testing cache behavior on User or related models.

## Query Pitfalls

### A format regex on a date field does not validate the date

`['regex:/^\d{4}\/\d{2}\/\d{2}$/']` accepts any well-shaped string, including
month 13, day 32, and the 30th of a non-leap Jalali year. The value then reaches
the calendar library, which either throws an uncaught exception or silently rolls
it over — `Jalalian::fromFormat('Y/m/d', '1400/12/30')` becomes `1401/01/01`, so a
wrong date is **stored** rather than rejected.

**Rule:** shape is not validity. Write a `ValidationRule` that range-checks the
calendar fields and then round-trips the result:

```php
public function validate(string $attribute, mixed $value, Closure $fail): void
{
    if (! is_string($value) || ! preg_match('/^(\d{4})\/(\d{2})\/(\d{2})$/', $value, $m)) {
        $fail('فرمت تاریخ باید به شکل 1400/05/12 باشد.');
        return;
    }

    [, $year, $month, $day] = $m;

    if ($month < 1 || $month > 12 || $day < 1 || $day > 31) {
        $fail('تاریخ شمسی معتبر نیست.');
        return;
    }

    try {
        $jalali = Jalalian::fromFormat('Y/m/d', $value);
    } catch (\Throwable) {
        $fail('تاریخ شمسی معتبر نیست.');
        return;
    }

    // fromFormat() silently rolls 1400/12/30 into 1401/01/01 — catch it here.
    if ($jalali->format('Y/m/d') !== $value) {
        $fail('تاریخ شمسی معتبر نیست.');
    }
}
```

The round-trip comparison is the load-bearing line: without it a rollover passes
validation and the wrong date reaches the column. The `try/catch` is equally
required because the library throws on a malformed string rather than returning
null.

Drive it from a `#[DataProvider]` table so the impossible-but-well-shaped cases
are named in the test file — `1380/13/01`, `1400/12/30`, `1380-05-12` (wrong
separator), Persian digits — rather than left to whoever next edits the rule.
Assert the rejection reaches the database guard too (`assertDatabaseCount(..., 0)`),
or a rule that fails to fire is indistinguishable from one that never ran.

### `ORDER BY` + `LIMIT` returns the OLDEST N, not the newest

`orderBy('day')->limit(30)` after a `groupBy('day')` returns the 30 *oldest* buckets, because ORDER BY is applied before LIMIT. Any "last N days/weeks" chart or list built this way silently shows the oldest window once the table holds more than N distinct periods.

**Rule:** take the newest N in a subquery, then re-sort for display in the outer query. Flipping only the existing `orderBy` to `desc` returns the right rows in reversed axis order — it is not a fix.

```php
// WRONG — oldest 30 days
Ticket::whereIn('unit_id', $ids)
    ->selectRaw('date(created_at) as day, count(*) as count')
    ->groupBy('day')->orderBy('day')->limit(30)->get();

// RIGHT — newest 30 days, displayed oldest → newest
$daily = DB::table('tickets')->whereIn('unit_id', $ids)
    ->selectRaw('date(created_at) as day, count(*) as count')
    ->groupBy('day')->orderByDesc('day')->limit(30);

DB::query()->fromSub($daily, 'daily')->orderBy('day')->get();
```

The resulting axis is **sparse** — the N most recent periods *that have rows*, not N consecutive periods. A test that asserts "N consecutive days" fails against correct code; assert the real contract instead (≤ N buckets, strictly ascending, newest bucket reaches the newest data).

### `paginate()` without a deterministic `orderBy` repeats and skips rows

MySQL is free to return rows in any order without `ORDER BY`, so `LIMIT/OFFSET`
pagination can repeat a row on page 2 and drop another entirely — and it looks fine on a
table small enough to fit one page. Add `->orderByDesc('id')` (or the intended sort) to
every paginated query.

### An empty search string still injects a `LIKE '%%'` clause

Wrapping the filter in `where(function ($q) { ... orWhere(...) })` without guarding on
the term being empty adds a redundant `LIKE '%%'` to every request and — with certain
index mixes — can defeat index use on the whole table. Guard it:

```php
->when($this->search !== '', fn ($query) => $query->where(function ($q) {
    $q->where('first_name', 'like', '%'.$this->search.'%')
      ->orWhere('last_name', 'like', '%'.$this->search.'%');
}))
```

### A model without `HasFactory` has no `::factory()`, whatever factories exist

A `XyzFactory` file on disk does not mean `Xyz::factory()` resolves — that requires `use HasFactory;` on the model. Without it you get `BadMethodCallException: Call to undefined method`, which reads like a broken factory definition but is a missing trait on the model.

**Rule:** before reaching for `Model::factory()`, confirm the model actually declares `HasFactory` (`search_files` for `HasFactory` in the model, or read the model). If it doesn't, build the row with `Model::create([...])` and populate foreign keys explicitly. A factory file with no `HasFactory` consumer is dead code — do not add the trait just to make a test terse.

### Back-dating a row: `created_at` is usually not fillable

`$fillable` governs mass assignment, and timestamps are typically excluded. Passing `created_at` to `create()` is silently dropped (or throws under strict mode), so the row lands at "now" and any test about time windows passes for the wrong reason.

**Rule:** create the row, then set the timestamp and persist:

```php
$row = Ticket::create([...]);
$row->forceFill(['created_at' => $day, 'updated_at' => $day])->save();
```

Give time-window fixtures a **midday** timestamp. The app timezone and the database session timezone often differ, and `date(column)` buckets in the *session* zone — a midnight value can fall in the previous day and shift the whole window.

## Blade Views & Livewire Pages

### `{-- --}` is not a Blade comment — it renders as literal page text

A Blade comment is `{{-- --}}` with **two** braces. The single-brace form `{-- --}`
is not compiled away: it survives into the rendered HTML as visible text, so an
implementation note written above a label shows up in the interface.

**Rule:** in any view, use `{{-- --}}`. In a Livewire page component (a view whose
filename carries the `⚡` prefix and which opens with a `new class extends
Component` block) the risk is higher, because the file is executed as PHP before
Blade ever sees the markup, and a reviewer copying the file's existing comment style
will copy it correctly only if the existing ones are right.

Guard it cheaply — the assertion costs nothing and catches the whole class:

```php
$html = Livewire::test('pages::students.index')->html();
$this->assertStringNotContainsString('{--', $html);
$this->assertStringNotContainsString('Some implementation note', $html);
```

Prove the guard bites by reintroducing the bad syntax and watching it go red;
a leak test that has never failed proves nothing.

## Seeders & Seed Data

### A seeder that silently skips a record hides a broken key, not a missing row

A seeder looking a row up by an application-level key (national code, external id, slug) that
is absent from the parent data file produces NO error — it just does not insert. The run reports
`DONE`, the exit code is 0, and the gap only shows up as a missing feature's history later.
A skip counter in the output is the ONLY evidence, so read the seeder's own informational lines
(`tail` the full output, not just the last `DONE` line) before calling a seed successful.

**Rule:** when a seed reports skipped/missing entries, do not accept "device not seeded, skip
silently" — resolve each skipped key against the table the parent seeder writes and fix the
DATA FILE, not the seeder's skip branch. Grep the offending key across the whole repo: if it
appears in exactly one file and nowhere else, that file is the bug.

Cross-file key agreement is worth asserting wholesale, not per-case: extract every key from the
child data file with its human-readable label, join against the parent's table, and list the
mismatches. Per-case hunting is O(failures); the join is one pass and also catches keys that
resolve to the WRONG row (same count, silently wrong history attached to a different device).

```php
// one pass: label in the comment above the key vs. the parent's pc_name
foreach ($lines as $line) {
    if (preg_match('~//\s*──\s*([A-Z0-9-]+)~u', $line, $m)) { $label = $m[1]; continue; }
    if ($label !== null && preg_match("~^\\s*'(\d{10})'\s*=>~", $line, $m)) {
        $hw = DB::table('hardwares')->where('n_code', $m[1])->first();
        echo ($hw && $hw->pc_name === $label) ? 'ok' : "MISMATCH: {$label} -> ".($hw->pc_name ?? 'MISSING');
        $label = null;
    }
}
```

Label + key pairs in a data file make a self-checking fixture: the comment names the device, the
key resolves to it, so drift in either is visible without opening the parent data file.

**Rule:** after fixing seed data, prove the fix two ways — re-run the seeder and confirm the
skip is gone, then re-run it AGAIN and confirm `0 new` (idempotency guard still works, so the
change did not weaken the duplicate protection), and read back the affected rows to confirm the
history actually attached to the intended record.

### `migrate:fresh --seed` needs a dump before it runs, and its output hides the interesting part

`--fresh` drops every table. On PostgreSQL take a `pg_dump -Fc` first and snapshot
per-table counts to diff afterwards — see `references/postgres-seed-verification.md` for
the exact queries. Put dump files somewhere gitignored, or they show up as untracked noise
on the next `git status`.

**Rule:** a seed run is verified when every seeder reports DONE and the post-seed counts
match the pre-seed snapshot. Anything else is a partial success that reads exactly like a
full one.

### A seeder tree needs two things: wiring, and idempotency

Two failure modes hide behind a green first run:

1. **The child seeder is never called.** `DatabaseSeeder` that only creates a User looks
   complete; the 20-row `StudentSeeder` sitting next to it is dead code. Every seed run
   reports success and the table stays empty. Verify the seeded row count in the database,
   not just the exit code.
2. **A fixed-value factory `create()` is not re-runnable.** `User::factory()->create(['email' => 'test@example.com'])`
   throws `UniqueConstraintViolationException` on the second run, so seeding is a one-shot
   and CI/`db:seed --force` loops break. Key on the unique column with `firstOrCreate`.

```php
User::firstOrCreate(
    ['email' => 'test@example.com'],
    ['name' => 'Test User', 'password' => bcrypt('password')],
);

$this->call(StudentSeeder::class);
```

For count-based demo data, seed the DELTA rather than the target, so the seeder is
idempotent without silently resurrecting rows a user deleted:

```php
$existing = Student::count();
if ($existing >= self::COUNT) { $this->command?->info("skipping ({$existing} rows)"); return; }
Student::factory()->count(self::COUNT - $existing)->create();
```

Print the final count through `$this->command?->info(...)` — a silent early return reads
exactly like a successful seed in the output.

### A deterministic back-dated seeder must key on a value that exists

Seeder fixtures that back-date rows need a fixed base date (so re-runs are byte-identical) and a
key that resolves. When both halves come from a human-edited data file they drift apart silently.
Keep the base date a class property, not a literal spread across entries, and keep every key in
the data file cross-checked against the table the parent seeder writes.

## Feature Parity Across Egress Paths

### A new column must reach every path a user reads or re-enters data through

Adding a field to a model is one line; the places that can silently drop it are the ones
that matter. When a field lands, check all of them and open the gaps as their own work:

- form create/edit **and** the edit-fill and reset lists (a property absent from the reset
  array leaks the previous record's value into the next form);
- import mapping **and** the importer's change-detection field list **and** the user-facing
  header hint rendered next to the upload control;
- export column definitions;
- the index table's column list.

**Rule:** search the new field name across the whole app (`search_files` on content) and
treat every hit that is a *definition* (migration, model) as the start, not the end — each
consumer that should read it and does not is a data-loss path. An export that omits a column
the form collects is silent loss: the user types a value, sees it saved, and it never leaves
the system.

When an export or import's contract was specified before the field existed, the drift is in
the spec, not the code — say so explicitly rather than blaming the implementation, and check
whether the spec is the artifact to update.

## External Integrations

### Rate-limiting a public route behind a proxy needs a trusted forwarded-for header

`ThrottleRequests::resolveRequestSignature()` keys anonymous requests on
`$request->ip()`, and `getClientIps()` only reads `X-Forwarded-For` when that header is among
the trusted proxy headers. Configurations that deliberately trust only
`X-Forwarded-Host/Proto/Port/Prefix` — the standard hardening against IP spoofing — fall back
to `REMOTE_ADDR`, which behind a load balancer is the proxy itself.

**Rule:** a `throttle:` on a route with no authenticated user is a per-bucket limit on
whatever the signature resolves to. Behind a proxy that is one shared bucket, so the limit
becomes a global budget for all visitors and everyone past it gets 429 — while a path that
looks unthrottled in testing is throttled in production. Before shipping one, confirm which
header the signature actually resolves to behind the real topology, and give the route a
signature that does not depend on the client IP if the answer is "the proxy".

### Turning a transport failure into a value: apply it at every caller, or record why not

The useful part of a typed-result adapter is that a connection failure stops being an
exception travelling through call sites that have to guess. It only buys that where it is
used, so a scheduled job that still calls the raw service keeps its old failure path.

**Rule:** when introducing a failure-as-value abstraction, enumerate every caller of the
underlying service — HTTP controllers, queued jobs, scheduled commands — and either convert
all of them or write down in the abstraction's docblock why the converted call sites are the
complete set. A job whose failure is routed through the queue's failure handler is a
legitimate reason to stay unconverted; an unexamined third caller is not.

## Operational Data

### An append-only table written by a high-frequency job needs a retention owner

A run-record table fed by a job on a short schedule grows linearly with no natural ceiling:
a five-minute job is ~105k rows a year. A timestamp index keeps the *reads* cheap, so nothing
looks wrong for months — the cost is storage, plus an ever-growing backup.

**Rule:** before shipping a per-run record table, find the project's existing retention
command and check whether it actually covers the new table — a maintenance command that
handles one model is not retention for the next one. If nothing covers it, either extend the
existing command or add a prune with a `--keep-days` flag. Grep for the table name across
the console commands to prove which side of that line you are on; do not infer coverage from
the existence of a retention command.

### A duration shared by a writer and a reader belongs in one constant

When a writer stores data with a TTL and a reader decides "is this fresh" by comparing against
a time window, the two numbers encode one policy and must move together. A literal in each
place compiles, passes tests, and diverges the first time someone changes the TTL — the reader
then reports the data as stale while the writer is still refreshing it.

**Rule:** express the duration once (a class constant, or the reader reading the same TTL
config the writer used) so changing it is a one-line change. Also remember a timezone
mismatch bites here: comparing an app-timezone wall clock against `time()` is only correct
because the app sets the default timezone at bootstrap; reading a stored timestamp through a
raw query facade returns a string, not a cast instance, and loses that guarantee.

## End-to-End Tests

### A failing E2E test may be the test that is wrong

Browser-level tests assert against a *rendering*, and the rendering is often sparse, paginated, or deduped in ways the test author did not model. When an E2E test fails but the feature-level test for the same behavior passes, suspect the E2E assertion before the application code — then prove it: read the actual rendered payload and compare it to what the code is contracted to produce.

**Rule:** before changing production code to satisfy a browser test, confirm which side encodes the wrong assumption, and state the finding out loud. An E2E test that demands "N consecutive rows" fails legitimately against a chart or list that is defined as "the N most recent rows that have data" — assert the real invariant (count bounded, order monotonic, newest record present) instead of a shape the feature never promised.

Read the payload the app already exposes to the browser rather than inferring it from pixels. When a charting library holds the data, the rendered instance is the source of truth:

```ts
const chart = (window as any).Highcharts.charts.find((c: any) => c?.renderTo === container);
const categories = chart.xAxis[0].categories;
```

Verify the date/label conversion in both languages instead of hand-rolling calendar arithmetic on one side. Format dates with the platform's own calendar implementation (e.g. `Intl.DateTimeFormat` with the `persian` calendar) and resolve labels back to real dates by a **round-trip** — a label is a match only if formatting the candidate date reproduces the label. Hand-written month-offset approximations drift across year boundaries and silently assert against the wrong date.

### A browser-reachable feature may need no JavaScript at all

A date picker in a Livewire app does not require an npm widget, a web component,
or a JS bridge. When the server already carries a calendar library, month-stepping
and day-click are ordinary `wire:click` actions: the picker renders entirely in
Blade, the project gains **no** bundle bytes, and an entire class of failures
(two-way binding, tree-shaking, morph re-wiring) simply does not exist.

**Rule:** price the no-dependency option first for any widget in a Blade/Livewire
app. A JS library is justified by an interaction Blade cannot express — drag
canvas, virtualised list, signature capture — not by the fact that the calendar
grid takes work to lay out. If the user rejects an installed library as unwelcome,
remove it and build the native version rather than defending the choice.

See `references/native-date-picker.md` for the file shape, the `morilog/jalali`
API traps, and the three bugs that pass a PHP suite and fail only in a browser.

## Static Analysis

### A regenerated baseline is evidence, not a formality

Baselines that record an occurrence **count** per file go stale when your change removes one of those call sites, and the analyzer then reports "expected to occur N times, but occurred only M" — a non-ignorable error that blocks the build even though the code improved.

**Rule:** when an edit removes a baselined call, regenerate and read the diff. A count decreasing is correct. Any *added* entry means a real new error just got suppressed — investigate it instead of accepting the regeneration. Never hand-edit a count to silence the mismatch; regenerate so the file stays reproducible.

## Test Environment Safety

### A test harness that swaps config must restore it on every exit path

A run that backs up `.env` and substitutes a test config leaves the wrong file in
place when it fails, because a failure skips the restore step. The next task then
runs against the test database and the damage is invisible until something is
overwritten.

**Rule:** make the restore unconditional (`trap`/cleanup block) rather than the
last line of a success path, and prove it by checking the restored file's
identity after the run — not by assuming the script reached the end.

```bash
# Verify identity, not just existence
grep -E '^DB_DATABASE=' .env     # must name the dev DB, not the test DB
```

Service credentials are covered by the `git-workflow` skill's masked-secret rule
— never mutate one from a masked or inferred value.

Models with `SoftDeletes` only set `deleted_at` — the row stays, and FK constraints still block related deletes. Use `forceDelete()` when you need to actually remove the row for FK-sensitive cleanup in tests.

```php
// WRONG — soft-deletes, FK still blocks person delete
$user->delete();
$person->delete(); // FK violation!

// CORRECT
$user->forceDelete(); // actually removes the row
$person->delete();
```

## Build & Route Caches

### A route cache built before `key:generate` 404s the Livewire update endpoint

Livewire 4 derives a hash from the app key inside its update URI
(`POST /livewire-<hash>/update`). A `bootstrap/cache/routes-v7.php` compiled while
`APP_KEY` was empty still holds the OLD hash, so after `key:generate` the route the
test/browser resolves no longer matches the cached one and every component update
returns **404**. `route:clear`/`optimize:clear` fixes it; nothing else does.

**Rule:** run `php artisan optimize:clear` immediately after `key:generate` (and after
any `.env` change that feeds route/container compilation), before debugging anything
else. Treat "component interactions do nothing, no error, no exception" as a
route-registration symptom first, not a component-code symptom.

The symptom is silent in three places at once, which is what makes it expensive:
- in a browser, modals never open and live search never filters;
- in a Livewire test, `->set()` / `->call()` appear to run but change nothing — the
  component instance comes back `null` and the errors bag is empty;
- the log stays empty.

See `references/livewire-testing.md` for how to surface the raw update response
instead of guessing at component code.

### A `sideEffects: false` web component can be tree-shaken out of the bundle while every PHP test passes

A custom element whose only job is the side effect of
`customElements.define('my-element', ...)` still ships `"sideEffects": false`.
Rollup drops the import, so the tag is never registered and the widget is inert
in the browser — while `php artisan test` stays green, because no test loads the
real browser bundle.

**Rule: for any feature that depends on a JS library shipping in the build,
verify the registration in the built artifact.** Bundle size is the fast
discriminator — a 57 KB dependency that vanished leaves a 1 KB stub.

```bash
npm run build
ls -la public/build/assets/            # a 1 KB app bundle is the smell
grep -c "customElements.define" public/build/assets/app-*.js   # must be >= 1
```

Fix with a Vite `transform` plugin returning `moduleSideEffects: 'no-treeshake'`
for that package. `build.rollupOptions.treeshake.moduleSideEffects`, `void SomeExport`,
and `customElements.whenDefined(...)` in your own module all leave the import
dropped — do not burn a cycle on them.

### `wire:model` does not bind to a custom element — check `observedAttributes`

Livewire's binding reads and writes real form controls. A web component keeps its
value in a JS **property**, so `wire:model` on the tag is inert even though the
attribute is visibly in your markup and validation rules still read a plausible
empty string.

**Rule:** before designing the integration, check whether `value` appears in the
element's `observedAttributes`. If it does not, attribute binding cannot work;
bridge the element to a hidden input Livewire owns and drive `getValue()` /
`setValue()`. Keep the hidden input as the server-side source of truth so
validation and the model write are unchanged.

See `references/livewire-web-components.md` for the full bridge and the build check.

**But first ask whether you need the component at all.** If the server already
carries the calendar library (Jalali dates, working days, money), a Livewire page
can render the whole picker in Blade with zero JavaScript — see
`references/native-date-picker.md`. Reach for an npm widget only when the
interaction is genuinely impossible in Blade (a drag canvas, a virtualised list),
not merely because building it takes an afternoon.

### Stale event cache after removing listeners

`bootstrap/cache/events.php` caches event-to-listener mappings. After deleting a listener class and removing it from `EventServiceProvider::$listen`, run `php artisan event:clear` — otherwise the Dispatcher tries to `include()` the deleted file and crashes.

```bash
php artisan event:clear
```

This is separate from `config:clear` and `route:clear`.

## Bringing an App Up

### A Blade file that fails to parse — check for a stray non-ASCII character, then check it is even referenced

A zero-width or combining character dropped inside a `<?php` block (a Persian/Arabic
combining mark, a bidi control) makes the file a parse error with a misleading column.
Dump codepoints around the reported line instead of reformatting by eye:

```bash
python3 -c "d=open('f.blade.php',encoding='utf-8').read(); i=d.find('́'); print(repr(d[i-40:i+20])); print([hex(ord(c)) for c in d[i-3:i+3]])"
```

**Rule:** before fixing the parse error, confirm the file is actually reachable —
`search_files` the component/route name. Livewire page components often ship alongside
a leftover hand-rolled component with the same title. A parse-broken duplicate that
nothing routes to is dead code: delete it rather than repair it. Same for a controller
with no route and a view no component renders.

### Moving a package between `require` and `require-dev` needs `composer require`, not `--lock`

Moving an entry invalidates `composer.lock`'s content hash, so `composer validate` reports
`Required (in require-dev) package "x" is not present in the lock file`. That message is not
about the hash — the package is genuinely absent from both `packages` and `packages-dev`.

**Rule:** fix it with `composer require`, which resolves the tree AND places the package in the
right section:

```bash
composer require --dev <pkg>:^<version> --no-scripts --no-interaction
```

**Do not reach for `composer update --lock`.** It only rewrites the content hash; it does not
add the missing package, so `validate` still fails afterwards and you have burned a cycle
believing you fixed it. `composer update <pkg> --lock` is separately rejected outright
("cannot update only a selection and regenerate the lock metadata").

Verify by asserting the section, not by reading `validate`'s exit code alone:

```bash
python3 -c "
import json; l=json.load(open('composer.lock'))
for sec in ('packages','packages-dev'):
    print(sec, '-> pkg:', '<pkg>' in [p['name'] for p in l[sec]])
"
```

A correct move also pulls the package's transitive dependencies into the lock (a Laravel dev
tool can add four or five packages). That size jump is expected, not a mistake — but it does
mean re-running the test suite afterwards, since the installed tree changed.

## Verification

- Before declaring an app "running": drive the real UI, not `curl` — see `references/browser-verification.md`. A served route does not prove interactive controls work.
- When a Livewire action silently does nothing: work `references/livewire-testing.md` top-down (control component → route reachability → caches → generated class → component code) before editing the component. The control component is step 0 because it splits the search in half.
- A green PHP suite does NOT verify a JS-library feature. The server contract and the browser bundle are separate proofs — `grep "customElements.define"` the built asset, then drive the real page (`references/livewire-web-components.md`).
- Tests passing is NOT the finish line for a CRUD feature. A full round trip through the actual UI (create → read back from the DB → edit → confirm `updated_at` moved → delete → confirm the row is gone) is what "works" means; automated tests and a 200 on `/` can both be green while every button is dead.

### Run Pint through the PHP binary when the shell wrapper is refused

`vendor/bin/pint` ships as a compiled PHAR. Terminal gateways that scan every executed script
before running it can refuse the wrapper because the binary exceeds the scan size cap — the
refusal names the file, not the real problem, so it reads like Pint is broken.

**Rule:** when a tool's launcher wrapper is rejected as unscannable, invoke the same tool
through its interpreter rather than working around it or skipping the check:
`php vendor/bin/pint --test` runs the identical binary and returns its result. Never report
formatting as "could not run" without trying the interpreter form first — CI enforces Pint, so
an unverified format is an unverifiable commit.