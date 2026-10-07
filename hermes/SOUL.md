# h-dashboard Development Instructions

## Project

The main project is:

`h-dashboard`

Canonical upstream repository:

`https://github.com/sadeghbiglar/h-dashboard`

Each server has its own fork/repository and its own dedicated working branch.

The server startup workflow already clones the correct repository, configures Git remotes, and checks out the correct branch.

**Never hardcode the fork URL or server-specific branch name.**

Always use the existing Git configuration of the current server.

---

# Session Initialization

Whenever a new session starts and the user is working on `h-dashboard`:

1. Go to the existing local repository:

```bash
cd h-dashboard
```

2. Inspect the existing Git configuration:

```bash
git remote -v
git branch --show-current
git status
```

3. Do not clone the repository again.

4. Do not modify existing Git remotes.

5. Do not guess or hardcode the current server's branch name.

6. Do not switch branches unless explicitly instructed.

7. Synchronize the canonical upstream `beta` branch with this server's fork according to the existing Git remote configuration.

8. Synchronize the current server-specific working branch from the fork's `beta` branch.

9. Push the synchronized current branch to its existing remote.

The exact remote names must be determined from:

```bash
git remote -v
```

Do not assume that `origin` or `upstream` has a specific meaning without checking.

---

# Normal Development Workflow

After session initialization:

* Always work on the current server-specific branch.
* Never switch to another branch unless explicitly instructed.
* All code changes must be made on the current branch.
* When work is complete, commit the changes to the current branch.
* Push the current branch to its existing remote.
* Do not push normal development work directly to `beta`.
* Do not modify the repository's remote configuration.
* Do not create another fork.
* Do not clone another copy of the repository.

Before committing:

```bash
git status
git diff
```

Create clear and meaningful commits.

After committing, push the current branch to its configured remote.

---

# Pull Requests

When the user says:

`pr`

create a Pull Request from the current server-specific branch to:

`beta`

of the canonical repository:

`https://github.com/sadeghbiglar/h-dashboard`

Use GitHub MCP when available.

Do not merge the Pull Request unless the user explicitly asks for the merge.

---

# Project Instructions

Before doing development work in `h-dashboard`:

1. Find `AGENTS.md`.
2. Read it carefully.
3. Follow all instructions in `AGENTS.md`.
4. Treat `AGENTS.md` as authoritative project instructions.
5. Keep its instructions in context throughout the task.

Do not skip reading `AGENTS.md`.

---

# Required Tools

For `h-dashboard` development, use these tools whenever relevant:

* Laravel Boost
* Context7
* GitHub MCP
* CodeGraph MCP

Before substantial development work, verify that these tools are available.

If one is unavailable:

1. Diagnose the problem.
2. Configure or start it if possible.
3. Verify that it is working.
4. Use it once available.

Do not silently pretend that an unavailable tool was used.

---

# CodeGraph

CodeGraph must be available for the `h-dashboard` project.

If CodeGraph is not available:

1. Diagnose its configuration.
2. Fix or configure it when possible.
3. Verify that it can access `h-dashboard`.
4. Use CodeGraph when analyzing the project's structure, relationships, dependencies, or existing implementation.

---

# Documentation First

The `read-the-damn-docs` skill must always be used for applicable work.

It must be installed if it is missing:

```bash
npx @agent-native/skills@latest add --skill read-the-damn-docs
```

Do not require the user to remind you to use this skill.

Before implementing or changing behavior:

1. Read the relevant documentation.
2. Prefer official/current documentation.
3. Check the actual project implementation when necessary.
4. Follow the documented/current API rather than relying on memory or assumptions.

---

# shadcn/improve

The `shadcn/improve` skill should be available for applicable frontend/UI work.

If it is missing, install/configure it before using it.

---

# General Rules

* Follow the user's explicit instructions for the current task.
* A newer explicit user instruction overrides these persistent instructions for that specific task.
* Do not ask the user to repeat these instructions at the beginning of every session.
* Do not invent project structure, APIs, configuration, or tool availability.
* Inspect the existing project and configuration before making assumptions.
* Preserve existing project conventions unless the user explicitly requests a change.
* Prefer small, focused changes over unnecessary refactoring.
* Verify changes before committing and pushing.
