# Verifying a Laravel app actually runs, end to end

`php artisan serve` returning 200 is NOT verification. A Laravel app can serve every route
while every interactive control is dead. Drive the real UI.

## Order that works

1. **Build assets** — `@vite` throws if `public/build/manifest.json` is missing:
   ```bash
   npm run build
   ```
2. **Clear caches** — `php artisan optimize:clear` (mandatory after `key:generate`).
3. **Start a SCRATCH server on a non-default port** so it never collides with the user's own:
   ```bash
   php artisan serve --host=127.0.0.1 --port=8123
   ```
   Poll `curl` in a loop for readiness instead of a blind `sleep`.

   Do NOT clear port 8000 (or whatever the user already uses) to make room for this. When the
   scratch phase ends, kill only the PID you started — never `pkill -f 'artisan serve'`, which
   matches the user's long-running server too. Restoring the user's own URL, binding it so their
   device can reach it, and giving it a supervisor that outlives the session are all separate
   steps: see the `dev-server-lifecycle` skill.
4. **Browser check** — read the RENDERED DOM (`page_info()`, `js()`), not `curl` output.
   `curl` sees the server-rendered shell; `wire:model` behaviour only exists after JS runs.
5. **Full CRUD in the browser** — create, verify, edit, delete, each confirmed in the DB.
6. **Read the log at the end** — `storage/logs/laravel.log` must have zero ERRORs.

## Proving a search works — pick a value from a field the search actually covers

The obvious way to verify a list's search is to type a word you can see in the table
(a job title, a category, a status). If the query filters on a narrower set of columns,
that returns zero rows and reads as "search is broken" when the code is correct.

**Rule:** before typing a verification term, confirm it belongs to a searched column.
Either read the search clause out of the component, or pick the value from the column the
query actually matches on — a national code, a phone number, a slug.

```bash
grep -n 'where\|orWhere' 'resources/views/pages/teachers/⚡index.blade.php'
```

An empty result from a term that is merely *visible in the table* proves nothing about
the search. State the scope instead: "search covers name/mobile/national code, and this
national code narrows to one row" is a real claim; "I searched for economics and got
nothing" is an unverified assumption.

Related trap: the search box keeps its previous value across checks. Clear it before
typing the next verification term, or the new term is appended to the old one and the
empty result looks like a broken filter.

## Triggering Livewire from `js()` does not work

`js("el.click()")` on a `wire:click` button is a synthetic click that Livewire's delegated
listener does not pick up in every harness — the DOM click lands, nothing happens, and you
chase a ghost bug. Use a real mouse click at computed coordinates:

```python
out = js("""(() => {
  const b = [...document.querySelectorAll('button')].find(x=>x.innerText.includes('دانش‌آموز جدید'));
  if(!b) return 'NOT FOUND';
  b.scrollIntoView({block:'center'});
  const r = b.getBoundingClientRect();
  return JSON.stringify({x:Math.round(r.x+r.width/2), y:Math.round(r.y+r.height/2)});
})()""")
c = json.loads(out)
click_at_xy(c["x"], c["y"])
```

Always `scrollIntoView({block:'center'})` first — `getBoundingClientRect()` on an
off-screen element returns coordinates outside the viewport and the click lands on nothing.

## Setting form values

Setting `.value` alone does not notify Livewire. Use the native setter and dispatch
BOTH events, or the model never updates:

```javascript
const setter = Object.getOwnPropertyDescriptor(el.constructor.prototype, 'value').set;
setter.call(el, 'some value');
el.dispatchEvent(new Event('input',  {bubbles:true}));
el.dispatchEvent(new Event('change', {bubbles:true}));
```

For `<select>`, assigning `.value` plus one `change` event is enough.

## Selectors for RTL Persian UI

Never guess placeholder text — a near-miss selector returns "NOT FOUND" with no clue.
Enumerate first, then act on the exact string:

```python
js("[...document.querySelectorAll('input')].map(i=>i.placeholder).join('|')")
```

Modals are hidden, not absent. Check computed visibility, never `.length`:
```python
js("[...document.querySelectorAll('.modal')].filter(x=>getComputedStyle(x).visibility!=='hidden').length")
```

## Confirming a write landed

A success toast is NOT proof the row persisted — and the row may be on a later page
because the list has no deterministic order. After each mutation, query the DB directly:

```bash
DBP=$(grep -E '^DB_PASSWORD=' .env | cut -d= -f2-)
mysql -h 127.0.0.1 -u academy1 -p"$DBP" academy1 \
  -e "SELECT id, first_name, city, updated_at FROM students WHERE national_code='9876543210';"
```

Search the list for the new record to confirm it renders too — that covers both the write
and the read path in one step.

## Report what was actually exercised

State which operations ran in the real browser vs. which are covered only by tests, and
quote the DB row IDs / values that prove each one. An unexercised CRUD path is not
"working", it is "untested".

## Screenshot helpers are pre-imported, not top-level tools

The harness prints its available tool names when you call one that does not exist. Screenshot
is available as the pre-imported helper `capture_screenshot()`, which RETURNS the saved path —
it is not a callable tool name. Don't burn calls discovering this:

```python
print(capture_screenshot())   # -> '/…/shot.png', then pass that path to vision_analyze
```

Prefer `js()` over a screenshot anyway: it is cheaper, exact, and diffable. Reach for a
screenshot only to answer a genuinely visual question (layout, overlap, colors) that the DOM
text cannot settle.

## Text-first, and read the DOM you actually mutated

You cannot see images yourself, so the workflow is DOM-first by construction. Two habits keep
it honest:

- After driving a mutation, read the specific thing you changed (`js` for the table row, a
  DB query for the persisted row) rather than re-screenshotting the whole page.
- When a click "does nothing", do not conclude the feature is broken. First check whether a
  higher-level cause explains every interaction at once — a dead Livewire update endpoint
  disables modals, live search and buttons together, and no amount of click-technique tuning
  fixes that. See `references/livewire-testing.md`.