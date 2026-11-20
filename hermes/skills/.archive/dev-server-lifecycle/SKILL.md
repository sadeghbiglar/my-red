---
name: dev-server-lifecycle
description: "Start, restart, relocate a web dev server safely."
version: 1.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [dev-server, ports, process-management, systemd, tailscale, verification]
    category: software-development
---

# Dev server lifecycle: ownership, reachability, survival

Covers any long-lived web server an agent starts — `php artisan serve`, `next dev`,
`vite preview`, `rails s`, `uvicorn`, `python -m http.server`. Not framework-specific.

## When to Use

Starting, restarting, moving, or debugging the reachability of a server that a user is
expected to keep visiting at a URL. Also when a URL the user says "does not open anymore"
resolves to nothing locally.

## 1. Establish ownership before touching a port

Before starting or restarting anything, find out **what already listens and whether it
predates you**. A server answering on the port is the user's, not yours to replace.

```bash
scripts/port-owner.sh 8000            # or: ss -ltnp | grep ':8000'
pgrep -af 'artisan serve'
```

**Rule:** never clear a port you did not fill. If something already serves it, reuse it or
say plainly that you are replacing it and why. Starting on a fresh non-default port is the
cheaper answer than evicting a working server.

## 2. `pkill -f` on a bare command name is an outage waiting to happen

The pattern `pkill -f 'artisan serve'` matches **every** instance — the user's long-running
server and any child worker alike. It reads as "restart my dev server" and is in fact
"delete every server matching this string on the machine".

```bash
# WRONG — kills the user's server too, and anything else matching
pkill -f 'artisan serve'

# RIGHT — resolve to one PID, or use the supervisor's own restart
kill "$(pgrep -f 'artisan serve --port=8000' | head -1)"
systemctl --user restart webapp.service
```

**Rule:** scope the pattern to the exact command line *including its port*, take the PID,
and kill that PID. When the server is supervised, prefer the supervisor's `restart` over
any signal — it is a single audited action and it re-reads the unit file.

### The tell that you have already caused an outage

`pkill -f 'artisan serve'` does not return an error when it matches nothing — it just kills
what it finds and exits 0, so nothing in the tool output marks the damage. You find out one
turn later, when the user says the link is dead.

**Rule:** after any kill or restart you issue, re-probe the user's URL before reporting
anything. If it no longer answers and you did not stop it on purpose, suspect your own
command first:

```bash
ss -ltn | grep ':8000' || echo "nothing listening"   # confirm the gap
pgrep -af 'artisan serve'                             # did anything survive?
```

Treat "the user's URL stopped working immediately after a command I ran" as
self-inflicted until proven otherwise. Say so in the FIRST line of the reply — name the
command, confirm it was yours, and confirm what you replaced. Do not present it as a
mystery outage; the user has already lost time on it.

### Replacing an ad-hoc server with a supervised one

Migrating to a supervisor unit means the two must not both hold the port. Stop the ad-hoc
process by its exact PID first, confirm the port is free, then start the unit:

```bash
HPID=$(pgrep -f 'artisan serve --host=0.0.0.0 --port=8000' | head -1)
[ -n "$HPID" ] && kill "$HPID"
ss -ltn | grep ':8000' || echo "free"     # must print "free" before starting
systemctl --user start webapp.service
```

Then prove the unit survives a restart (`systemctl --user restart`, poll readiness) — a unit
that starts once but dies on the next crash is not the durability you claimed.

## 3. Bind for the audience, not for yourself

`--host=127.0.0.1` is reachable only from the machine. A URL the user types into their own
browser is coming from another device.

**Rule:** if the user gives a hostname (VPN/tailscale/mDNS/DNS) rather than `localhost`,
bind `0.0.0.0`. Confirm which interface that hostname resolves to before assuming:

```bash
getent hosts <hostname>            # 100.x / tailscale / LAN => remote client
```

Then verify from the user's exact URL — not from loopback. A server bound to loopback can
answer `127.0.0.1` while being unreachable from the device that matters.

### Diagnosing "their URL does not open"

Work outward in this order, and stop at the first layer that explains it — each step
distinguishes a different owner of the fault:

```bash
ss -ltnp | grep ':<port>'                   # 1. is ANYTHING listening locally?
getent hosts <hostname>                     # 2. does their hostname resolve, and to what?
curl -s -o /dev/null -w '%{http_code}\n' --max-time 5 http://<hostname>:<port>/
```

- nothing listening → the server is down; go to §4 and give it a supervisor
- listening but bound to `127.0.0.1` only → it exists but the user's device cannot reach it;
  rebind to `0.0.0.0` per §3
- hostname resolves to a `100.x`/tailnet IP that IS this machine → the app is fine; the
  user needs the tunnel up on their side, and the fix is not in this repo

**Rule:** a bare `curl` to loopback returning `000` proves nothing about a remote URL.
Establish which layer is broken before changing anything — the three failures look identical
from the user's side but need three different fixes, and guessing at the wrong layer wastes
a whole debugging cycle.

## 4. A background process started by an agent does not outlive the session

Processes launched as ad-hoc background jobs die with the agent lifecycle. A server the
user is meant to keep using needs an owner that outlives the session and restarts on crash.

```bash
cp templates/systemd-user-webapp.service ~/.config/systemd/user/webapp.service
systemctl --user daemon-reload && systemctl --user enable --now webapp.service
```

**Rule:** for a server the user depends on across turns, install it as a user-level
supervisor unit (`Restart=always`) rather than leaving it as a background job. `enable` it
so it also comes back after a reboot. Then prove it: `systemctl --user restart`, poll for
readiness, and confirm the status code from the user's URL.

## 5. Readiness is a polled check, not a sleep

```bash
for i in $(seq 1 15); do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "http://$HOST:$PORT/" 2>/dev/null)
  [ "$code" = "200" ] && { echo "ready after ${i}s"; break; }
  sleep 1
done
```

Poll a real route and require the expected status. A blind `sleep 5` either wastes time or
races the bind, and both read as flakiness later.

## 6. Report reachability as a table, from the user's URL

Verify every address the user might use, and name the ones that were checked. A single
`200` on loopback is not evidence the user's link works.

```
http://127.0.0.1:8000/       -> 200
http://<hostname>:8000/      -> 200
```

State which URL was proven and how (curl status, or a real browser interaction). If an
interactive control was exercised, say so; a served route does not prove a working UI.

## 7. A service's state is part of the service — verify the backup, not the copy

A server that restarts with an empty database looks like it crashed, not like data
loss. Before promising that state survives anything (rebuild, redeploy, new machine),
prove a **restore** works. Copying a file is not backing up state.

### Never copy a WAL-mode sqlite database by hand

In WAL mode the committed rows live in `<db>-wal` until a checkpoint. The main file can
be a few KB with **zero tables** while `-wal` holds hundreds of KB of real data:

```
app.db        4096 bytes   <- 0 tables, PRAGMA integrity_check says "ok"
app.db-wal  304912 bytes   <- every table and row is in here
```

`cp app.db backup.db` therefore produces a **valid-looking empty database**. It does
not error, it passes an integrity check, and it restores "successfully" — and all the
data is gone. Size the two files side by side before trusting any copy.

Produce a self-contained snapshot with a checkpoint plus `VACUUM INTO`:

```bash
node -e "
const {DatabaseSync} = require('node:sqlite');
const db = new DatabaseSync('/path/app.db');
db.exec('PRAGMA wal_checkpoint(TRUNCATE)');
db.exec(\"VACUUM INTO '/path/backup.db'\");
db.close();
" 2>/dev/null
```

(Use `sqlite3 app.db ".backup out.db"` when the `sqlite3` CLI is available.)

### Validate a restore by counting the schema, not by checking the file exists

`[ -f backup.db ]` proves nothing — an empty shell passes it. Open the candidate and
assert it has the expected objects before installing it over a live database:

```bash
node -e "
const {DatabaseSync} = require('node:sqlite');
const d = new DatabaseSync(process.argv[1], { readOnly: true });
console.log(d.prepare(\"SELECT count(*) c FROM sqlite_master WHERE type='table'\").get().c);
d.close();
" "$CANDIDATE"
```

Refuse anything below the expected table count and leave the running service alone.

### Kill the service before a restore, and delete the stale sidecars

Two rules that make a restore silently corrupt:

- **Stop the app first.** Copying files out from under a live writer captures a torn
  moment, not a consistent snapshot.
- **Delete `<db>-wal` and `<db>-shm` after overwriting the `.db`.** Sidecars from the
  previous generation get replayed over the restored file and undo it. Leftover `-wal`
  is how a correct restore still comes back empty.

### State on a disposable machine needs a commit step, and so does its repo

If the machine rebuilds (ephemeral CI runner, container, cloud instance), in-place
state is destroyed on every cycle. The backup must be written somewhere that survives —
committed to a repo, pushed to object storage — from a teardown step that actually
runs. Check that the teardown step is reachable: a step gated on `if: always()` does
**not** run when the job is killed at `timeout-minutes`, so leave real headroom between
a keep-alive loop and the job timeout, or the backup silently never happens.

Flag where that backup lands before pushing. A backup repo that is public, or a
snapshot containing credential hashes and live session tokens, is a disclosure even
when the data is only a test project — name the exposure in one or two sentences, then
respect the user's decision rather than re-litigating it.

### Before handing back a credential-creation step, look for a root cause that needs none

On a disposable machine, "the cleanup step needs an API token, so create this secret"
looks like the honest report — and it is often the wrong one. A leaked identity, a
duplicate registration, a name that keeps getting a numeric suffix: these are usually
*symptoms* of a step that never runs, and the missing credential only papers over it.

Sequence to follow before proposing any new secret, key, or token to the user:

1. Explain the failure with one level of mechanism: what registered, what claimed the
   name, what was supposed to release it.
2. Find the step whose absence causes it, and ask **why that step did not run** —
   gating condition, ordering, timeout, exit path.
3. Fix that. Most such "I need a token" situations disappear entirely.
4. Only if a genuinely external cause remains (a node deleted by someone else, a
   credential expired) offer the token — and then it is belt-and-braces, clearly
   labelled as such, not the fix.

**Rule:** never present a manual step as required while an uninvestigated root cause
remains. Say what you could not do yourself (a console login, a password prompt — never
type or request those), fix everything that does not need it, and label the rest
optional with the condition that would make it necessary. A hand-off also reads as
"stop here", which is a claim about your capability that is often wrong.

## Pinning an identity that a disposable machine claims repeatedly

A machine that rebuilds on a timer and registers a named identity (a VPN/tailnet node,
a device cert, a cloud instance name) accumulates stale registrations: a node that dies
before its cleanup step leaves its identity claimed, and the identity service resolves
the clash by appending a suffix. The user then sees `thing-1`, `thing-2` and concludes
their setup is broken.

Three layers, cheapest first, and expect layer 1 to be the actual fix:

1. **Guarantee the cleanup step runs.** A teardown gated on `if: always()` does NOT run
   when the job is killed at `timeout-minutes`, and a keep-alive loop whose length equals
   the job timeout guarantees the kill lands exactly as that loop ends. Keep-alive must
   sit below `timeout-minutes` with real headroom; then verify in the teardown that the
   identity is actually gone.
2. **Serialize the runs.** A concurrency group makes a second run queue instead of
   starting a parallel claimant. On a self-hosted CI or scheduler this is the equivalent
   of `flock` around the whole run — it also fixes the case where a manual trigger
   overlaps a scheduled one.
3. **Sweep stale registrations.** Only for leaks from outside the run (someone deleted
   the machine mid-cycle). This is the layer that needs an API credential, so it goes
   last, and it should match strictly — `name` and `name-<digits>`, never a loose prefix
   that also catches unrelated nodes. Test the matcher against a stubbed response before
   trusting it.

Make the run fail loudly rather than silently if the identity it got is not the one it
asked for: an assertion at join time turns a confusing `thing-7` into an immediate,
readable failure.

## Installing a service from someone else's install script

`curl -sSL <url> | sudo bash` hands the machine to a stranger with root and no
reviewable artifact. When the user hands you that command, do not run it piped —
download it, read it, then run the local copy:

```bash
curl -sSL -o /tmp/install.sh <url>
sha256sum /tmp/install.sh && wc -l /tmp/install.sh    # something quotable in the report
less /tmp/install.sh                                    # or read_file
sudo bash /tmp/install.sh --flags
```

Read for the things that decide whether it is safe to run with root:

- **What it writes and where** — install dir, systemd units, firewall rules, config.
- **What it deletes** — any `rm -rf`, especially on a path derived from a variable.
- **Where credentials go** — does it write a secret into a repo-tracked file, a
  world-readable mode, or a log line that gets echoed?
- **Whether it is idempotent** — re-running it later must not wipe state, because you
  will re-run it on the next rebuild.
- **Whether it overwrites data it did not create** — a script that clobbers an existing
  install is a different decision from one that only fills an empty dir.

Then verify the result instead of trusting the script's own success message: confirm
the service is active, probe a real route for the expected status, and locate the data
directory and its persistence story (§7). Report what the install actually wrote.

Note in your report any honest caveat the script itself printed (for example, running
without HTTPS means credentials travel unencrypted) so the user can decide whether it
matters for this deployment rather than discovering it in production.

## Admitting the cause when you caused it

If an outage traces to your own earlier command, say so in the first line and name the
command. The user's time is spent reading the fix; do not make them infer whose fault it
was from a list of symptoms.

## Pitfalls

- **`ss`/`lsof` need no privileges for your own processes** — use them rather than inferring
  from a failed request that nothing is listening.
- **A `419` on a POST to a framework endpoint is success**, not a failure: it means the
  route resolved and the request reached CSRF middleware.
- **Restarting "the server" after changing an env key or route-affecting config**: clear the
  framework's own caches too, or the process reloads stale compiled routes.
- **Do not report the server as restored until the user's own URL returns the expected
  status.** Fixing loopback and declaring victory is the failure this skill exists to prevent.

## Support files

- `scripts/port-owner.sh` — list listeners, flag dev-server processes, show whether each is
  supervised. Run it before starting or killing anything.
- `templates/systemd-user-webapp.service` — user-level unit that restarts on crash and
  survives logout; copy and edit `WorkingDirectory`, `ExecStart`, and the log path.