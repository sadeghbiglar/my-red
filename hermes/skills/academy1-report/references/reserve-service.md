# reserve (:8080) — hall-booking service

Third service on this machine, alongside Laravel (:8000) and 9router (:20128).

## What it is
`jackjons676-rebecca/reserve` — Persian hall-reservation system. **No npm dependencies
at all**: plain `node:http` + `node:sqlite` (built into Node), zero `package.json`
requirements in the repo. Deployed by the repo's own `deploy.sh` (Persian, idempotent).

- Install dir: `/opt/reserve` (code: `server.js`, `src/`, `public/`, `tools/`)
- Data dir: `/opt/reserve/data` — `reserve.db` (sqlite), `reserve.db-wal`,
  `reserve.db-shm`, and `backups/` next to it. `chmod 700`, owned by `runner`.
- systemd unit: `reserve.service` (`User=runner`, `Environment=PORT=8080 HOST=0.0.0.0`,
  `ReadWritePaths=/opt/reserve/data`, `Restart=always`). **Enabled** — survives reboot.
- Env override: `RESERVE_DB` changes the sqlite path; default `data/reserve.db`.
- Health: `curl http://127.0.0.1:8080/api/status` ->
  `{"needsSetup":true,"authenticated":false}` on a fresh install.
  `needsSetup:true` means NO admin has been created yet — first browser visit asks for
  username / full name / password.
- Tailscale URL: `http://100.97.188.25:8080` (changes if the runner IP changes)

## Reinstall / update
```bash
cd /home/runner/.hermes/cache/scratch
curl -sSL -o deploy.sh https://raw.githubusercontent.com/jackjons676-rebecca/reserve/main/deploy.sh
sudo bash deploy.sh --repo https://github.com/jackjons676-rebecca/reserve.git --ip <TAILSCALE_IP>
```
Idempotent: re-running updates code and keeps `data/` untouched. Review the script
before running it — it is `curl | sudo bash` territory, so download it and read it
first, then run the local copy. It asks for Node >= 24 for `node:sqlite`, but Node 22
is sufficient because that module landed in 22; the deploy script only reinstalls Node
when the running major is lower.

## Auto-start on every session
`scripts/report.sh` has a `== RESERVE (:8080) ==` block: it reports state, and starts
the service if it is down. It only restarts when HTTP != 200, so a healthy service is
never bounced. sudo is passwordless here.

## Persistence: DONE (my-red commit 6e9ea19)
The database now survives runner rebuilds, committed to the **public** `my-red` repo
at `reserve/data.sqlite`. The user explicitly accepted that (test project). Note this
repo also already tracks `9router/data.sqlite`, `hermes/state.db`, `hermes/cron/*.db`,
and the reserve db holds scrypt `pin_salt`/`pin_hash` for admins plus live session
tokens.

- **step 13b** (after the Hermes step, before the Laravel server): downloads
  `deploy.sh`, runs it with the runner's current Tailscale IP, then restores the db.
  The restore **validates first** — it counts tables in the repo copy and refuses
  anything under 5 (a valid reserve db has 7). Stale `-wal`/`-shm` from the fresh
  install are deleted before the restore so they cannot replay over it.
- **step 16** (`if: always()`): stops the service, then backs the db up.

### The trap that makes the obvious approach lose everything
The app runs sqlite in **WAL mode**. On a fresh install:
```
reserve.db       4096 bytes   <- 0 tables, integrity ok (!)
reserve.db-wal 304912 bytes   <- all 7 tables, 7 halls live in here
```
Copying `reserve.db` directly produces a **valid-looking empty database** — it does
not error, it just has no data. Verified on this machine. The workflow therefore uses
`PRAGMA wal_checkpoint(TRUNCATE)` + `VACUUM INTO`, which yields one self-contained
69 KB file with all 7 tables and `integrity_check = ok`. Never `cp` the `.db` here.

The general rule (WAL snapshots, restore validation, stale sidecars, disposable-machine
teardown ordering) lives in `dev-server-lifecycle` §7 — this section is only the
reserve-specific instance of it.

## Verified
YAML parses; every step's `run` passes `bash -n`; both embedded node programs were
extracted and executed against the live database (7 tables out, random garbage file
correctly rejected with 0 tables).
