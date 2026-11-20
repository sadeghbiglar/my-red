# Security-scan triage for `hermes plugins install`

The install scan reports per-line findings with `file:line`, then a verdict. The report is printed
twice in one install attempt (scan runs, then re-runs on confirmation), so raw counts are ~2x — dedupe
before reading counts as meaningful.

## Verdict / message → action

| Message | Meaning | Action |
|---|---|---|
| `BLOCKED — Blocked (community source + caution verdict, N findings)` | strings matched heuristics | Triage below, then `--force` only if the executable surface is clean |
| `custom (unreviewed) source — not from the Hermes catalog` | not curated | expected for any GitHub install |
| Verdict `CAUTION` | pattern matches, no malicious behavior proven | triage |
| Verdict `MALICIOUS`, or any HIGH finding inside the executable surface | real risk in shipped code | do **not** force; stop and report to the user |
| HIGH findings only under `docs/`, `*.md`, `tests/` | prose and fixtures | inert; force is defensible |

## Finding classes that are documentation noise

- `destructive` HIGH on `rm -rf ~/.config/<harness>/...` in `INSTALL.md` / `README.<harness>.md` → uninstall instructions in prose.
- `credential_exposure` on `const TOKEN = 'testtoken-...'` under `tests/**` → hardcoded test fixture, never a live secret.
- `exfiltration` on `env | grep` inside a `SKILL.md` body → an example command quoted in skill documentation.
- `supply_chain` / `traversal` MEDIUM in bulk across `docs/` and `tests/` → path strings inside markdown.

## The rule that decides it

A finding counts only if its `file:line` lies in code the plugin actually executes. Group by top-level
directory first: when the executable surface is one file, read that one file end to end and decide on it
alone. Findings whose quoted line wrapped onto the next log line are missed by path-only regex — scan
those by eye.

## superpowers worked example (shape, not a verdict to copy)

233 findings, all under `docs/`, `tests/`, and `*.md`; the only executable surface was
`.hermes-plugin/__init__.py` plus `plugin.yaml`, and that Python file only builds and injects a text
bootstrap — no network, no file writes, no subprocess. Triage result: inert, `--force` justified.
Re-derive this from the actual files; never reuse the conclusion without re-reading them.