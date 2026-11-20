# Extension removal / presence audit

Run the whole list before answering "it is gone" or "it isn't there". Miss one surface and the audit reports a false clean.

## Probe list

| Surface | Probe | A hit means |
|---|---|---|
| Installed plugins | `ls ~/.hermes/plugins/` | directory per installed plugin |
| Plugin registry | `hermes plugins list` | installed set (NOT the catalog) |
| Platform / toolset config | `grep -n -A5 -i "<name>" ~/.hermes/config.yaml` | a `platforms.<name>` or toolset block |
| Credentials | `grep -i "<PREFIX>_" ~/.hermes/.env; env \| grep -i "<PREFIX>_"` | stored token / URL |
| Scheduled jobs | `~/.hermes/cron/jobs.json` — list every job name + `enabled` | a job driving the integration |
| Skills | `find ~/.hermes/skills -maxdepth 2 -iname '*<name>*'` | a skill pack for it |
| Memory | `grep -ril -e <name> ~/.hermes/memories/` | a persisted fact about it |
| Kanban | `sqlite3 ~/.hermes/kanban.db "select ... where title like '%<name>%'"` | tasks referencing it |
| Vault | `~/.hermes/vault/` (encrypted, `vault.json.enc`) | stored logins/cards for its sites |
| Runtime / message history | `sqlite3 ~/.hermes/state.db "select count(*) from messages where content like '%<name>%'"` | prior conversation mentions (NOT an install) |
| Tool surface | tool catalog: any `<prefix>_*` tools deferred-listed | the extension is actually live in-session |

## Interpret correctly

- Message-history and log hits are conversation artifacts, not installations. Ignore them in the verdict.
- Upstream source under `~/.hermes/hermes-agent/` and `~/.hermes/installs/` matches any popular extension. Never edit it — it is a clean git checkout and `hermes update` overwrites local patches.
- `hermes plugins show <name>` resolves installed plugins only; it always misses a catalog-only entry.

## Removing, when it is really installed

1. `hermes plugins remove <name>` (aliases: `rm`, `uninstall`).
2. Re-run the probe list — do not assume the CLI cleared config, env, or cron.
3. Delete any leftover credentials from `~/.hermes/.env` by hand.
4. Restart / reload the gateway so the platform loader drops the entry.
5. Report what was removed per surface, and anything deliberately left in place (with the reason).

## Verdict style

Give the per-surface evidence, then one plain conclusion — "nothing installed, nothing to remove". Do not perform speculative deletions or edits to upstream code to make the request visibly "done".