---
name: hermes-extensions
description: "Install, verify, or fix Hermes plugins and skills."
version: 1.1.0
license: MIT
metadata:
  hermes:
    tags: [hermes, plugins, skills, integrations, mcp, superpowers]
    related_skills: [hermes-agent]
---

# Hermes Extensions (plugins, skills, MCP servers)

## When to Use

- The user asks whether an integration (plugin, skill pack, MCP server) is installed, enabled, or working.
- Installing or repairing an extension, or diagnosing one that silently does nothing.
- The user supplies a plugin/skill repo URL to add, or an existing one stopped triggering.
- Session-start routine: the user asks every session to confirm these integrations are live.

## Step 1 — Verify before installing anything

The user asks every session to confirm these integrations are live and to fix any that are broken, so this class of task recurs. "Installed" is unproven until a runtime check passes — a name in config is not an install record.

Never read install state from `config.yaml`. `plugins.enabled` is a *selection* list, not an install record: it can name a plugin whose directory was never fetched, and that plugin then silently does nothing.

```bash
hermes plugins list          # authoritative: name, status, version, source
ls ~/.hermes/plugins/        # what actually landed on disk
```

A name in `config.yaml` but absent from `hermes plugins list` (and from the plugins dir) is NOT installed. Report that before proposing an install.

## Step 2 — Read the upstream repo's harness-specific instructions

The install command is harness-specific; do not invent it. Read the plugin repo's README section for *this* harness (Hermes Agent / Claude Code / Codex …) before running anything, and prefer the repo's own `.hermes-plugin/plugin.yaml` for the declared hooks.

## Step 3 — Install

```bash
hermes plugins install <owner/repo> --enable
```

Benign warnings on a repo-root install, none of which mean failure: `custom (unreviewed) source — not from the Hermes catalog`, `Skipped Node deps`, and `doesn't contain plugin.yaml, plugin.json, or __init__.py` — that last one fires when the manifest lives in `.hermes-plugin/`, which is the normal repo-root layout.

## Step 4 — When the security scan blocks: triage, then decide

A block means "unreviewed community source + caution verdict", not "malware". Triage before overriding:

1. Group findings by file path. Findings confined to `*.md`, `docs/`, and `tests/` are documentation samples and test fixtures, not shipped behavior.
2. Read the plugin's real executable entrypoint end to end (`.hermes-plugin/__init__.py`, `plugin.yaml`, `index.js`, `hooks/`). Look for network calls, file writes, `subprocess`, credential reads.
3. Only then re-run with `--force`, and tell the user what the findings were and why they were judged inert.

Never pass `--force` without having read the entrypoint yourself. Never force a *malicious* verdict or a HIGH finding located in the executable surface — stop and report instead.

Use `scripts/triage-plugin-scan.sh <owner/repo>` to produce the grouped report, and `references/security-scan-triage.md` for the verdict/finding-class decision table.

## Step 5 — Prove it works (four checks, all required)

```bash
hermes plugins list | grep -i <name>   # enabled + a version number
hermes plugins doctor <name>           # manifest parse, import, registration: OK
skills_list                            # plugin skills present, category "plugin"
```

Plus: install output must report the gateway reloaded and registered hooks. Any one of these missing means not working — say so, do not summarize as installed.

## Step 6 — Remove / "is it even there?" audit

Removal and "does this exist at all" are the same sweep — an audit must cover every surface where an integration can hide, or it reports a false clean. Work the probe list in `references/extension-removal-audit.md` (plugins dir + CLI, `config.yaml` platform/toolset blocks, `.env` and process env, cron jobs, skills, memories, kanban, vault, and the SQLite row counts).

Report the audit as evidence per surface, then state the one honest conclusion ("nothing installed, nothing to remove") rather than performing a deletion for show.

**A reference to the extension inside upstream core code is not an install.** `~/.hermes/hermes-agent` is a clean git checkout of upstream: catalog entries (`plugin-catalog/<name>.yaml`), migration shims, metrics allowlists, and docs all mention extensions nobody installed. Never patch or delete those to satisfy a "remove it" request — it forks the repo and `hermes update` overwrites it. Say so explicitly and offer the real alternative (block future install, or leave it).

## Pitfalls

- **`hermes skills list` does not list plugin-provided skills.** Only the `skills_list` tool does, under category `plugin`. Grepping CLI output for a plugin's skills is a false negative; never conclude the install failed from it.
- **Plugin skills need the qualified name**: `skill_view(name="<plugin>:<skill>")`. The bare name will not resolve.
- **Catalog misses are normal.** `hermes plugins search` / `browse` cover only the curated catalog, so an unreviewed GitHub plugin never appears there. Absence from search is not evidence of nonexistence — check disk.
- **`hermes plugins show <name>` returning "not found" proves nothing about the catalog.** It resolves installed plugins only, so a name present in `plugin-catalog/` will always miss. Use it to confirm absence of an *install*, never to claim the extension does not exist.
- **Exclude `~/.hermes/hermes-agent/` and `~/.hermes/installs/` from greps.** Those are upstream source and staged build copies; a naive recursive grep matches dozens of files for any popular extension and buries the real signal. Filter them, then read what remains.
- **Never pass `--force` on an install the user did not ask for.** A "remove it" or "is it there" request is an audit, not authorization to re-clone and enable it.
- **A long session can silently lose a plugin bootstrap.** Hermes has no post-compaction hook: a session that compacts over its first turn drops the injected bootstrap and the skills stop triggering. Symptom = "skills stopped applying mid-conversation"; fix = start a fresh session, never a reinstall.
- **Reinstall only when the entrypoint is broken.** Refresh an installed plugin with `hermes plugins update <name>`; re-running `install` re-clones and churns the tree.

## superpowers (obra/superpowers)

Installed at `~/.hermes/plugins/superpowers`, exposes ~15 skills as `superpowers:<name>`. Process skills come first and gate the rest: `brainstorming` before any plan or new feature, `systematic-debugging` before any bug fix, `writing-plans` → `executing-plans` / `subagent-driven-development` for implementation, `verification-before-completion` before reporting work as done. `using-superpowers` must not be re-invoked once its bootstrap is loaded.

Install command, verified 2026-10-05: `hermes plugins install obra/superpowers --enable --force`.
`--force` is required — the security scan BLOCKS with 233 findings, all of them
"LOW persistence" hits in `*.md` docs, test fixtures, and skill prose (e.g.
`references/hermes-tools.md` mentioning "your instructions file"). None land in the
executable surface. Before forcing, read `.hermes-plugin/__init__.py`: it is pure —
`register_skill()` loops the `skills/` tree and a `pre_llm_call` hook returns the
bootstrap string on the first turn; no network, subprocess, or credential access
(verify with a grep for `requests|urllib|socket|subprocess|os.system|popen|curl|wget|token|api_key|password|.env`).
Benign install warnings to ignore: `custom (unreviewed) source`,
`Skipped Node deps`, and `doesn't contain plugin.yaml, plugin.json, or __init__.py`
(the manifest lives in `.hermes-plugin/`). Success signal is
`Gateway reloaded plugins ... active in the running gateway now: hooks` plus
`hermes plugins doctor superpowers` reporting 1 hook.