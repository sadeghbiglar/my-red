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