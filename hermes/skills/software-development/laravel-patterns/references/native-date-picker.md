# Building a date picker in Blade with zero JavaScript

For a Livewire app that already has a server-side calendar library (Jalali/Shamsi,
`morilog/jalali`, `Carbon`), a full month picker needs no npm dependency and no
custom element. Everything renders server-side; the browser only clicks buttons.

## Shape

- `app/Support/JalaliCalendar.php` — arithmetic: month lengths, leap years, month
  and weekday names, stepping day/month/year. Pure, no UI.
- `app/Support/MonthGrid.php` — one month laid out as whole Saturday-first weeks.
  Returns `cells()` as a flat list where a `null` is a blank leading/trailing
  cell. The view never does date maths.
- `resources/views/components/<name>-datepicker.blade.php` — renders the grid and
  calls back into the Livewire component.
- The Livewire component holds `$pickerField`, `$pickerOpen`, `$pickerYear`,
  `$pickerMonth` and the actions `openPicker`, `closePicker`, `stepMonth`,
  `pickDay`, `clearDate`.

The list day count becomes the fast verification signal: count
`button[wire:click^="pickDay"]` in the DOM and compare against
`daysInMonth(year, month)`.

## Verify the calendar facts before writing assertions

Do not assert from memory which years are leap or what weekday a date falls on —
probe the library, then write the table from what it says:

```bash
php -r 'require "vendor/autoload.php";
foreach ([1399,1400,1401,1402,1403] as $y)
  echo $y, " leap=", var_export(Morilog\Jalali\Jalalian::fromFormat("Y/m/d","$y/01/01")->isLeapYear(), true), PHP_EOL;
for ($y=1400;$y<=1410;$y++)
  echo $y, " => ", Morilog\Jalali\Jalalian::fromFormat("Y/m/d","$y/01/01")->toCarbon()->format("l"), PHP_EOL;'
```

Guessing wrong here is the main source of wasted cycles: an expectation that 1403
is not a leap year, or that 1 Farvardin 1400 is a Saturday, sends you debugging
correct code. The month/year whose first day really is Saturday is the one to use
for a "no leading padding" case.

## Library API: check the signature, do not assume

`morilog/jalali` exposes `getMonthDays()` and `isLeapYear()` as **instance**
methods on a resolved date — there is no static `Jalalian::getDaysInMonth($m, $y)`
to call. Build a real date first, then ask it.

### `addDay()` / `subDay()` return a NEW instance

The most damaging one, because it compiles and throws nothing:

```php
// WRONG — $jalali is unchanged, the calendar can never advance
$jalali = $this->toJalalian();
$jalali->addDay();
return new self($jalali->getYear(), $jalali->getMonth(), $jalali->getDay());

// RIGHT
$jalali = $this->toJalalian()->addDay();
```

Symptom: a unit test that asserts the *computed* month length passes, while every
click in the browser appears to do nothing, because navigation is wired to the
discarded value. PHP-side state assertions do not catch it if they assert the
helper's return rather than the mutation.

## `<select>` bound to a typed int property

`wire:change="pickerYear = $event.target.value"` delivers a **string**. Implicit
coercion left the dropdown with no matching option, and the browser silently fell
back to the first one — month navigation drifted by years. Use explicit action
methods that cast and clamp:

```php
public function setPickerYear($year): void
{
    $this->pickerYear = max(self::MIN_YEAR, min(self::MAX_YEAR, (int) $year));
}
```

```html
<select wire:change="setPickerYear($event.target.value)">
```

The year list must span the **full** supported range, not a window around the
current year. A window centred on `pickerYear` moves when `pickerYear` moves, so
the newly selected year can fall outside its own option list — the same silent
first-option fallback. `range(self::MIN_YEAR, self::MAX_YEAR)` is the fix, and the
regression test is that the current year is always among the options.

## A PHP test suite cannot see any of the three bugs above

All three passed `php artisan test` and failed in the browser. Unit-test the
arithmetic, then drive the real page for the interaction:

- click a day → assert the input's value and that the panel closed;
- step months repeatedly → assert the year does not drift;
- set the year dropdown to a leap year and to a common year → assert the day
  count differs by one.

## Comment syntax

Implementation notes in the view must use `{{-- --}}`. The single-brace `{-- --}`
survives compilation and renders as visible page text.