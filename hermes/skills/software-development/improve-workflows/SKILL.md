---
name: improve-workflows
version: 1.0.0
author: Hermes Agent (session-derived)
license: MIT
description: "Audit plan-writing and issue registration workflows."
---

# Improve Workflows

Operational patterns discovered during real improve skill executions. Supplements the improve skill (shadcn) with Hermes-specific tooling workflows.

## Issue Registration (`--issues`)

When the improve skill's `--issues` modifier publishes plans as GitHub issues:

### Procedure

1. Determine `owner/repo` from `git remote -v` — never assume from AGENTS.md or memory. The canonical upstream and the server's fork may use different owner names.
2. Check if issues are enabled: `gh issue list --repo owner/repo`. If "disabled", try the fork remote.
3. Verify labels exist: `gh label list --repo owner/repo`. Create missing ones first or omit.
4. Create: `gh issue create --repo owner/repo --title '...' --body '...' [--label '...']`
5. Record the issue URL in the plan file and tracker.

### Never hardcode issue numbers in a body you write before the issues exist

A roadmap issue that lists its slices as `#3 Teachers`, `#4 Courses` is a guess until
the slice issues are created. The first `gh issue create` decides the real numbering,
and it lands wherever the counter is — it does NOT start where your plan assumed.

**Rule:** create the slice issues FIRST, capture the numbers each call returns, then
write the parent body with the real numbers and ship it with `--body-file`.

```bash
declare -A NUM=()
url=$(gh issue create --repo "$REPO" --title "$t" --body "$b" 2>&1 | tail -1)
NUM["$(echo "$url" | grep -oE '[0-9]+$')"]="$t"
```

### Do not build a markdown body with an in-place text insertion

Post-processing a body to splice lines under section headers corrupts it. An append
loop like `sed '/^### Section$/a \\\n- #N Title\n'` glues the first bullet onto the
header line (`### 1. Teachers (staff)- #3 Teachers: migration and model`) because the
append does not start a fresh line.

**Rule:** generate the whole body as a literal file and upload it once. If it must be
assembled, use `printf`/heredoc concatenation — never in-place edits on prose.

```bash
cat > /tmp/body.md <<'EOF'
### 1. Teachers

- #3 Teachers: migration and model
EOF
gh issue edit "$N" --repo "$REPO" --body-file /tmp/body.md
```

Verify by reading the rendered section back (`gh issue view N --json body --jq '.body'`)
and eyeballing the headers — a mangled body still exits 0 on both create and edit, so
exit status proves nothing here.

### Pitfalls

- **GitHub MCP auth failure → switch to `gh` CLI immediately.** Do not retry MCP. The MCP server requires `GITHUB_PERSONAL_ACCESS_TOKEN` env var; `gh` uses stored credentials. One retry wastes time; the fallback is instant.
- **Wrong repo name.** AGENTS.md may reference a canonical name that differs from the actual git remote. `git remote -v` is authoritative. If the primary repo has issues disabled, try the fork remote.
- **Missing labels.** `--label 'improve-audit'` fails if the label doesn't exist. Either create it first (`gh label create improve-audit --repo owner/repo`) or omit labels entirely.
- **Bulk issue registration (10+ plans).** Use `cronjob_manage` with `schedule: 'every 5m'` and `repeat: N` instead of creating all issues in one turn. Track progress in `plans/tracker.json` (JSON array with `done: boolean`, `plan_file`, `issue_url` fields per finding). Set `deliver` to the user's home channel for status updates.

## Delivering a roadmap as one commit per slice

When the user asks to register a roadmap and then "do them all, each one its own
commit and push", that is a delivery contract, not a suggestion. Each slice is a
self-contained commit that independently satisfies one issue, verified before it ships.

Per slice, in order:

1. Implement it — **and nothing else**. A slice that also refactors a neighbour produces
   a commit that closes one issue and silently changes two others.
2. Gate: full test suite green, then the project's formatter (`php vendor/bin/pint --test`).
3. **Verify in the real UI**, not only in tests — a 200 on the route does not prove the
   controls work. For a list page, search for a value you can read back out of the seeded
   data and confirm the row count changes.
4. Scope-check the staged diff (`git diff --cached --stat`), grep it for hardcoded secrets,
   commit with the issue reference in the body.
5. Confirm fast-forward before pushing, then push with an explicit refspec
   (`git push origin HEAD:refs/heads/<name>`) when the local branch's tracking config
   points at a DIFFERENT branch name.
6. Verify the remote actually took it (`git ls-remote --heads`), then close the issue with
   the commit SHA in the closing comment.

**Rule:** state the resulting per-slice totals honestly in the running report — issues
closed, commits pushed, suite size — and surface open questions about scope assumptions
BEFORE building many slices on top of them. A wrong default (no auth layer, no term
scheduling) multiplies into every later commit.

Prefer making the first complete section the reference implementation that later sections
mirror, so conventions (query ordering, form shape, validation style) are settled once.

## Subagent Audit Pattern

For the `standard` effort level (default), fan out with 4 parallel subagents:

1. **Correctness & Security** — input validation, auth/authz, SQL injection, XSS, race conditions
2. **Performance & Architecture** — N+1 queries, unbounded recursion, cache misuse, God classes
3. **Test Coverage & Quality** — untested critical paths, wrong annotations, DRY violations
4. **Tech Debt & DX** — baseline bloat, dead code, CI gaps, documentation

Each subagent prompt must include:
- Recon facts (languages, frameworks, key directories)
- Domain-specific risk hints from recon
- Decided tradeoffs from intent docs
- "Return findings only — no fixes, no file dumps"
- Hard Rules 4 and 6 from the improve skill (verbatim)

Subagent output schema per finding: `{id, category, finding, evidence, impact, effort, risk, confidence}`.

## Vetting Subagent Reports

Subagents over-report. Three failure classes to check:

1. **By-design behavior** reported as bug (e.g., "CSP unsafe-inline" when it's intentional)
2. **Mis-attributed evidence** — real finding, wrong file or line
3. **Duplicates** across subagents (same root cause, different symptoms)

Always open the cited code yourself before including a finding in the vetted table. Downgrade or reject accordingly.

## Writing a plan the executor cannot misread

A plan containing a method that does not exist is worse than a plan with a gap: the executor writes to the invented name and the failure surfaces far from the plan. **Every identifier in a plan must come from a grep or a read in the same session.**

### Verify every symbol before you write it

Before a plan body references a class, method, helper, or constant, confirm it exists:

```bash
grep -n 'public function' app/Services/YourService.php      # signature, not just the name
grep -rn 'foldedTerm' app/ resources/ | head                 # how callers reach it
```

Assume nothing from memory of the framework or from a similarly named helper. Specific traps that each broke a plan in practice:

- **A trait's static methods are not callable as `Trait::method()`.** `PersianNormalizer` is a `trait`; the callers do `use PersianNormalizer;` then `self::foldedTerm(...)`. Writing `PersianNormalizer::foldedTerm(...)` compiles into a fatal.
- **Helper namespaces, not just names.** A method may exist on the model but as a differently-named public function. Check the real name.
- **Dependency check before inventing syntax.** A planned `d3.scaleQuantize(...)` in a project whose only frontend runtime dependency is Leaflet-by-CDN means the plan ships a plan that cannot run. Grep `package.json` and the view's `<script src>` tags.
- **Test-helper methods must come from the shared trait.** If a plan invents `$this->tokenFor(...)` because that reads nicely, the executor discovers at run time that the real helper is `createApiToken($user, $abilities)` plus a `forgetGuards()` call. Read `tests/Support/Concerns/` first.

### Fix in place, never ship a known-wrong snippet

When a snippet in a plan turns out wrong, patch that snippet. Do not leave it and append a note — a "remove the line above" instruction is an executor trap, and a plan that says "…actually use X" reads as two half-plans.

The cheap order that catches most of this: write one task, then immediately grep every symbol it introduced before writing the next task. Fix at the point of discovery, where the surrounding context is still in hand.

### Do not let a plan assert a count it did not measure

A plan that says "the suite has N tests and must stay green" launders a number from a docs file. Either measure it in the session or phrase the gate relationally ("the count is at least the baseline plus the new tests").

## A plan's own test suite is part of the plan

A TDD-shaped plan is only as good as the assertions that pin the risky inputs. Before shipping, list the input classes the spec implies but no happy-path test touches — cross-branch visibility, cycles, non-ASCII text, SQL metacharacters, duplicate submissions — and require each to be pinned by a named test inside the task that owns that code. Put the list in the plan header once, so the executor sees it while writing the tasks, and attach each line to a task as you write it.

## Plans Directory Structure

```
plans/
  tracker.json              ← queue for automated processing
  README.md                 ← index: priority order, dependency graph, status
  001-<slug>.md
  002-<slug>.md
```

Each plan file stamps the commit hash it was written against (`git rev-parse --short HEAD`).

The `tracker.json` schema:
```json
{
  "last_created": 0,
  "findings": [
    {
      "num": 1,
      "id": "SEC-001",
      "slug": "short-slug",
      "title": "Plan title",
      "category": "security",
      "effort": "M",
      "impact": "high",
      "done": false,
      "plan_file": "plans/001-short-slug.md",
      "issue_url": "https://github.com/.../issues/N"
    }
  ]
}
```
