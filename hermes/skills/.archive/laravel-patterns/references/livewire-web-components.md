# Wiring a JS web component into Livewire, and keeping it in the bundle

Two independent failure modes bite when a Livewire page uses a third-party custom
element (Jalali date pickers, rich pickers, signature pads). Both pass a PHP test
suite while the feature is dead in the browser.

## 1. `wire:model` does NOT bind to a custom element

Livewire's model binding reads and writes **real form controls**. A web component
stores its value in a JS **property**, so `wire:model` on the tag is inert — even
though the attribute is visibly in your markup and the component's validation
rules still read a plausible-looking empty string.

Tell-tale: `value` is absent from the element's `observedAttributes`.

```js
// Check before designing around it — this decides the whole integration shape.
grep -o 'static get observedAttributes[^]]*]' node_modules/<pkg>/dist/*.esm.js
```

If `value` is not listed, attribute-based binding cannot work and only the
property API (`getValue()` / `setValue()`) is available. Bridge it through a
hidden input that Livewire *does* own:

```html
<input type="hidden" wire:model.live="birth_date" id="birth_date-picker-target" value="{{ $birth_date }}" />
<persian-datepicker-element data-datepicker="birth_date-picker-target" format="YYYY/MM/DD" rtl></persian-datepicker-element>
```

```js
function bind(picker) {
    if (picker.dataset.datepickerBound === '1') return;   // morph re-runs this
    picker.dataset.datepickerBound = '1';

    const input = document.getElementById(picker.getAttribute('data-datepicker'));
    if (!input) return;

    // picker -> Livewire
    picker.addEventListener('change', (event) => {
        if (event.detail?.isRange) return;               // no single field value
        const v = picker.getValue();
        input.value = Array.isArray(v) ? v.join('/') : '';
        input.dispatchEvent(new Event('input', { bubbles: true }));
    });

    // Livewire -> picker
    const push = () => {
        const v = input.value.trim();
        const cur = picker.getValue();
        const curV = Array.isArray(cur) ? cur.join('/') : '';
        if (!v || v === curV) return;
        const [y, m, d] = v.split('/').map(Number);
        if (y && m && d) picker.setValue(y, m, d);
    };
    picker._push = push;
    push();                                               // seed server-rendered value
}
```

Bind inside Livewire's `morph` hook so elements added by a morph get wired, and
re-run `push()` on `morphed` — otherwise a modal that prefills a stored date
shows an empty calendar while the hidden input holds the right value.

**Rule:** the hidden input stays the single source of truth for the server side.
Validation rules, `assertSet`, and the model write keep working unchanged, so the
JS bridge never leaks into PHP.

## 2. `"sideEffects": false` gets a self-registering component tree-shaken away

A component whose entire purpose is the side effect of
`customElements.define('my-element', ...)` still ships `"sideEffects": false`.
Rollup trusts it and drops the import: the bundle builds clean, every PHP test
passes, and the tag is inert in the browser because nothing ever defined it.

This is invisible to `php artisan test` — no test loads the real browser bundle.

**Rule: verify the registration in the built artifact, not in the test suite.**

```bash
npm run build
ls -la public/build/assets/app-*.js          # a 1 KB app bundle is the smell
grep -c "customElements.define" public/build/assets/app-*.js   # must be >= 1
```

Bundle size is the fast discriminator: dropping a 57 KB component leaves an
obvious 1 KB stub.

Keep it alive with a `transform` plugin that re-declares the module side-effectful:

```js
const keepComponent = {
    name: 'keep-my-element',
    enforce: 'pre',
    transform(code, id) {
        if (id.includes('my-element')) {
            return { code, moduleSideEffects: 'no-treeshake' };
        }
        return null;
    },
};
```

A `build.rollupOptions.treeshake.moduleSideEffects` callback is **not** sufficient
for this — it left the import dropped. The `transform` hook works. Don't spend a
cycle on the rollupOptions route.

`void SomeExport` and `customElements.whenDefined(...)` in your own module do not
work either: neither creates a reference Rollup keeps.

Import the class by its real exported name — verify it rather than assuming
casing (`PersianDatePickerElement`, not `PersianDatepickerElement`):

```bash
grep -o 'export{[^}]*}' node_modules/<pkg>/dist/*.esm.js
```

## 3. Picking the library — or not picking one

**Check first whether you need a library at all.** A Jalali date picker in a
Livewire app needs no npm dependency at all: the server already carries a calendar
library, the interaction is month-stepping plus a day click, and all of it renders
in Blade. See `references/native-date-picker.md`.

A npm widget buys you ~57 KB, a JS bridge with its own failure modes (sections 1
and 2 above), and a maintenance tail — in exchange for markup the project can
render itself. If the user pushes back on a picker you installed, take the push-back
as the answer and remove it rather than defending the choice.

When a library genuinely is the answer (drag interactions, virtualised lists,
signature capture — things Blade cannot express), vet it:

```bash
npm view <pkg> version time.modified license dependencies
```

- `time.modified` years in the past → unmaintained, and its calendar math may
  drift from the server's.
- a `react`/`vue`/`jquery` dependency in a plain-HTML app → you inherit a
  framework you do not have.
- `sideEffects: false` on a self-registering web component → see above.

Prefer a framework-free web component or plain module in a Livewire/Blade app;
a framework wrapper needs a framework you are not running.

## Verification

A green PHP suite proves the server contract, not the feature. Before reporting
a UI wired to a JS library as done, drive the real page and confirm the element
registered, the calendar opens, and picking a date lands in the hidden input —
see `references/browser-verification.md`.