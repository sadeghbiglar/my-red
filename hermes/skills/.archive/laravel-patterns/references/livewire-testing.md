# Debugging a Livewire component that silently does nothing

A Livewire component whose action "runs" but changes nothing — empty error bag, no
exception, no log entry — is almost always an environment or route problem, not a
component-code problem. Work down this list; stop at the first one that explains it.

## 0. Run a CONTROL component first — it decides which half of the library to debug

Before reading any project code, register a trivial control component in the same test file
and give it the SAME shape as the suspect (protected `rules()`, one action that increments a
static counter):

```php
class ProbeComponent extends Component {
    public static $counter = 0;
    public string $name = '';
    protected function rules(): array { return ['name' => ['required', 'string', 'min:2']]; }
    public function doThing(): void { $this->validate(); self::$counter++; $this->name = 'done'; }
    public function render() { return '<div>{{ $name }}</div>'; }
}

// reset both statics before the probe, or a previous test's value reads as success
ProbeComponent::$counter = 0;
Livewire::test(ProbeComponent::class)->set('name', 'x')->call('doThing');
fwrite(STDERR, 'control counter: '.ProbeComponent::$counter."\n");   // 1 = harness fine
```

**Rule:** the control is a binary discriminator, so run it FIRST.

- control counter stays `0` → the harness/environment is broken and NO amount of component
  code editing will help. Go to step 1 and read the raw update response.
- control counter increments → the harness works, so the fault IS in the suspect component.
  Skip to step 3.

This is worth one extra test class because it converts a guessing loop into a branch. Without
it you keep re-reading the component, the model, and the validation rules looking for a bug
that is not there, while the real cause sits in a compiled route cache. Note that the control
failing too is the strongest possible proof the bug is not yours to fix in that file.

## 1. Is the update endpoint reachable?

Write one throwaway test and read the RAW update response. `Testable::__call` forwards to
the response but always returns `$this`, so `$c->status()` / `$c->content()` are useless —
reflect the protected state instead, or just assert the status:

```php
$c = Livewire::test('pages::students.index');
$c->assertStatus(200);                 // initial render

try {
    $c->set('search', 'a')->assertStatus(200);
} catch (\Throwable $e) {
    fwrite(STDERR, 'set FAILED: '.$e->getMessage()."\n");
}

$ref  = new \ReflectionObject($c);
$prop = $ref->getProperty('lastState');
$prop->setAccessible(true);
$state = $prop->getValue($c);

fwrite(STDERR, 'status: '.$state->getResponse()->status()."\n");
fwrite(STDERR, 'body:   '.substr($state->getResponse()->getContent(), 0, 2000)."\n");
```

A `404` with a Laravel error page body is the signature of a route-registration problem.
Continue to step 2.

**Fastest confirmation without any test:** `curl` the endpoint the routes list names.

```bash
php artisan route:list | grep -i update
curl -s -o /dev/null -w '%{http_code}\n' -X POST http://127.0.0.1:8000/livewire-<hash>/update
```

`419` (CSRF) means the route EXISTS and is fine. `404` means it does not resolve. If the
hash in `route:list` differs from the one baked into cached routes, the cache is stale.

## 2. Clear the route/config caches

```bash
php artisan optimize:clear
```

Mandatory after `key:generate` — Livewire's update URI is keyed on the app key, so a route
cache compiled with an empty `APP_KEY` routes every update to a URI that no longer exists.

## 3. Does the component class even contain the method?

```bash
php -r '$c = json_decode(file_get_contents("vendor/composer/autoload_classmap.php"), true);'
grep -n 'public function saveStudent' storage/framework/views/livewire/classes/*.php
```

Single-file / `⚡`-prefixed components compile to an anonymous class cached under
`storage/framework/views/livewire/classes/`. If the generated file lacks the method, the
PHP above `?>` failed to parse or the class was never registered.

## 4. Is the method callable at all?

```php
method_exists($c->instance(), 'saveStudent')
```

`$c->instance()` returns `null` after a FAILED update (the state was replaced by an error
response) — that null is itself the signal, not a bug in your test.

## 5. Now suspect the component

Only once 1–4 pass is component code the answer — and step 0 already told you which side of
the fence you are on, so at this point it is confirmed rather than suspected.

## Test-API notes (Livewire 4.4)

- `viewData($key)` requires an argument; `viewData()` with none throws
  "Too few arguments". A `#[Computed]` method is NOT in view data — call it directly:
  `$c->instance()->students()`.
- `Testable::all()` / `viewData()` are the wrong tool for a computed paginator. Assert
  through the rendered output (`assertSee` / `assertDontSee`) or query the model directly
  with the same `paginate()` call.
- The *value* of a set property comes from `$c->get('name')`, not from the fluent return.
- `assertDatabaseHas` on a DATE column: MySQL returns `2001-08-03 00:00:00` when compared
  as a raw string, so match the date column separately via
  `Model::where(...)->value('date_col')?->format('Y-m-d')`.
- `laravel/pao` (a dev dependency) wraps PHPUnit stdout in a JSON envelope. It does not
  suppress errors, but it hides your `fwrite(STDERR, ...)` debug output unless you read the
  raw stream. Don't mistake its compact JSON summary for PHPUnit's own output.