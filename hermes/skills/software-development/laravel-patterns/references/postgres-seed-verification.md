# Postgres-specific seed & migration verification

Applies when the project runs on PostgreSQL. The MySQL/SQLite equivalents are simpler
(no extensions, no dump tool).

## Dump before `migrate:fresh --seed`

`--fresh` drops every table. Take a dump first — it is the only way back if the seed is
lossy. Put it somewhere gitignored.

```bash
mkdir -p .hermes-backups
export PGPASSWORD="$(grep -E '^DB_PASSWORD=' .env | cut -d= -f2- | tr -d "'\"" )"
pg_dump -h 127.0.0.1 -U app_user -d app_db -Fc -f .hermes-backups/db-$(date +%Y%m%d-%H%M%S).dump
```

Never mutate a service credential from a masked or inferred value — read it from `.env`
and mask it in output.

## Snapshot row counts in one pass

Do not query per-table. One `DB::select()` over `pg_tables` returns everything:

```sql
SELECT relname, n_live_tup FROM pg_stat_user_tables ORDER BY relname;
```

Snapshot BEFORE the seed, diff AFTER. Equal counts across the board is the evidence that
seeders rebuilt the reference data rather than leaving hand-made rows behind. A table that
comes back with a different count names the non-deterministic seeder — or the unseeded
table.

## Re-verify extensions and versions after seeding

A seed that recreates extension-backed tables can drop them. Re-assert after the run:

```sql
SELECT extname, extversion FROM pg_extension ORDER BY extname;
```

**Rule:** a seed run is verified only when every seeder reports DONE, extension versions
still resolve, AND post-seed counts match the pre-seed snapshot. Anything less is a
partial success that reads exactly like a full one.