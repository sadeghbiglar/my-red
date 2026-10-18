# The academy ephemeral runner (GitHub Actions → Tailscale)

## Where the machine actually comes from
`/home/runner/academy1` is a checkout on a **GitHub-hosted ephemeral runner**, built
by the workflow `sadeghbiglar/my-red` → `.github/workflows/ssh.yml` (workflow name
`academy`, branch `academy`). The `academy1` repo itself has **no** workflow.

Each run: `tailscale up --hostname=academy --advertise-exit-node`, then keeps alive
300 min, then step 17 `tailscale logout`. Everything under `~/.hermes` is restored
from `my-red/hermes/` at boot and pushed back at shutdown — so `my-red/hermes/` is
the source of truth for skills, memories, config and cron, not the local disk.

Workflow step map (names shift as steps are added — grep for the name, do not trust
a number):
- 4b purge stale Tailscale nodes · 5 join Tailscale · 7 clone academy1 onto `academy`
- 12 restore/start 9router · 13 Hermes + state restore · 13b install/restore `reserve`
- 14 Laravel server · **14b development autopilot** · 15 keep-alive · 16 state sync
  back to `my-red` · 17 Tailscale logout

Useful commands (repo is NOT cloned locally; use the GitHub API):
```bash
gh run list --repo sadeghbiglar/my-red --workflow ssh.yml --limit 8
gh api repos/sadeghbiglar/my-red/contents/hermes/skills --jq '.[].name'
gh api repos/sadeghbiglar/my-red/contents/.github/workflows/ssh.yml --jq '.content' | base64 -d
```

## Why `academy-1` appeared
A leaked Tailscale node, not primarily two runners at once. The mechanism below runs
on every teardown, so a single killed run is enough; a manual `workflow_dispatch`
overlapping the 6-hourly `schedule` just makes it happen faster.

## The root cause of `academy-1` — keep-alive vs timeout-minutes
`timeout-minutes: 340` with a keep-alive of `for i in {1..340}` meant the job was
killed at exactly the moment step 15 ended. GitHub kills the job at
`timeout-minutes` WITHOUT running `if: always()` steps, so **step 17
(`tailscale logout`) almost never executed**. The node stayed registered in the
tailnet, and the next runner found `academy` taken -> `academy-1`.

`if: always()` covers step failure and cancellation, NOT the job timeout. Any future
change to the keep-alive length must keep `timeout-minutes` above it with real margin.
Current values: keep-alive 300m, timeout 330m, cron `0 */6 * * *` (360m) — 30 minutes
of headroom before the next scheduled run. This ordering rule is the general lesson;
`dev-server-lifecycle` §7 states it for any disposable-machine teardown.

## The fix already pushed (my-red commits a7124e2 + 16a1976)
1. **`concurrency: group: academy-machine, cancel-in-progress: false`** — a run that
   arrives while another is live queues instead of spawning a parallel runner.
2. **keep-alive 340->300, timeout 340->330** — the actual fix; step 17 now always runs.
3. **Step 17 verifies** it worked (`tailscaled` must stop reporting a state).
4. **Step 4b "Purge stale Tailscale nodes"** (belt-and-braces) — lists
   `/api/v2/tailnet/-/devices` and DELETEs every node named `academy` or
   `academy-<digits>`. Matching is strict (`academyxyz` / `academy-abc` are NOT
   touched; verified with a stubbed API response). **Skips with a warning unless the
   `TAILSCALE_API_KEY` secret is set** — that secret does NOT exist and could not be
   created from this machine (the Tailscale console requires a web login).
   Step 5 asserts the joined hostname and exits 1 if it is not exactly `academy`, so a
   stale node fails loudly instead of silently becoming `academy-2`.
5. `php artisan key:generate --force` after `cp .env.example.mysql .env` — the template
   ships `APP_KEY=` empty, which caused the MissingAppKeyException on every fresh boot.
6. `config.yaml` is scrubbed of `/home/runner/h-dashboard` in both directions;
   `skills/h-dashboard-session` deleted in both directions; `seed-message.txt` now says
   `cd academy1`.

## Optional hardening (only needed if an `academy-N` name ever appears again)
Set the secret so step 4b can clean up autonomously:
```bash
# Tailscale console -> Settings -> API keys -> Generate (no write access needed for DELETE)
gh secret set TAILSCALE_API_KEY --repo sadeghbiglar/my-red
```
Without it, the timeout fix plus concurrency is still sufficient for a single name —
this only covers nodes leaked by an external cause (runner deleted mid-run, etc.).

## h-dashboard is retired
`sadgehbiglar/my-reb` -> workflow `rebecca` (cron `0 */7 * * *`, cloned
`h-dashboard.git`) is **disabled_manually** as of 2026-10-17. Do not re-enable it and
do not reintroduce the `h-dashboard-session` skill. `my-red/hermes/` has been scrubbed.

## Editing the workflow without a local clone
Clone to scratch, never into the repo:
```bash
cd /home/runner/.hermes/cache/scratch
git clone --depth 1 --branch academy https://github.com/sadeghbiglar/my-red.git my-red-wk
cd my-red-wk && git remote set-url origin "https://x-access-token:$(grep -o 'ghp_[A-Za-z0-9]*' ~/.hermes/.env | head -1)@github.com/sadeghbiglar/my-red.git"
# edit, then:
git add <paths> && git -c user.name='sadeghbiglar/' -c user.email='sadeghbiglar/@users.noreply.github.com' commit -q -F /path/to/msg.txt && git push origin academy
```

**Validate the workflow before pushing, every time.** `gh workflow list` does not
validate and a bad `run:` block fails the whole machine at boot. Two checks, both
cheap:
```bash
# 1. YAML parses
python3 -c "import yaml,pathlib; yaml.safe_load(pathlib.Path('.github/workflows/ssh.yml').read_text())"

# 2. every embedded bash step is syntactically valid — extract the run: blocks
#    out of the parsed YAML and shell-check each one
bash -n /tmp/extracted-steps.sh
```
YAML-valid is not shell-valid: a broken continuation inside one `run:` block only
surfaces when the runner executes that step.

**Extracting values out of a `run:` block to test the logic separately:** copy the
block into `/tmp/step-N.sh` and run it against fixtures instead of reasoning about
it. Field-parsing that reads multi-word values needs `IFS=$'\t' read -r A B C` —
plain `read` splits on the default IFS and truncates the first field at its first
space. Test all three states: a populated record, an empty one, and a malformed
entry.
