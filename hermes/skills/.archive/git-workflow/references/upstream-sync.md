# Verifying fork / canonical base-branch sync

## The refs that must be compared

| Ref | How to read it |
|---|---|
| canonical base | `git ls-remote https://github.com/<owner>/<repo>.git refs/heads/<base>` |
| fork base | `git ls-remote <fork> refs/heads/<base>` |
| fork work branch | `git ls-remote <fork> refs/heads/<branch>` |
| local work branch | `git rev-parse <branch>` |

Full sync means all four are the same commit SHA. Comparing the local branch against the fork's
base is a **circular** check — both are the fork, so they can be stale together and still look
clean. The canonical ref is the only one that answers "am I behind".

## Verification block

```bash
git fetch https://github.com/<owner>/<repo>.git <base>
git fetch <fork> --prune

echo "canonical: $(git ls-remote https://github.com/<owner>/<repo>.git refs/heads/<base>)"
echo "fork base: $(git ls-remote <fork> refs/heads/<base>)"
echo "fork brnch:$(git ls-remote <fork> refs/heads/<branch>)"
echo "local brnch:$(git rev-parse <branch>)"

printf "canonical tree: %s\n" "$(git rev-parse FETCH_HEAD^{tree})"
printf "branch    tree: %s\n" "$(git rev-parse <branch>^{tree})"

git rev-list --left-right --count FETCH_HEAD...<branch>   # expect 0  0
git diff --stat FETCH_HEAD <branch>                       # expect empty
git status --porcelain                                    # expect empty
```

Tree hashes equal but SHAs differing means rewritten history — investigate, never force-push
over it.

## Decision table

| `rev-list --left-right --count FETCH_HEAD...HEAD` | Working tree | Action |
|---|---|---|
| `N  0` | dirty file upstream never touched (lockfile noise) | discard the noise, then sync |
| `N  0` | files upstream also changed | merge first, resolve, then sync |
| `0  M` | any | work already merged upstream; nothing to sync — report in sync |
| `0  0` | clean | already in sync; push nothing |

## Refspec rules

`git push <fork> FETCH_HEAD:refs/heads/<base>` — mirrors canonical into the fork, creating the
branch when absent.

`git push <fork> HEAD:refs/heads/<branch>` — the only safe form for your own branch while
`branch.<name>.merge` points at the base branch. `git push` and `git push <fork> <name>` both
target the base branch in that configuration.

## Reporting

State the four SHAs (or that they are identical), the ahead/behind count, and whether anything
was actually pushed. When nothing needed pushing, say so plainly instead of narrating a no-op push
as an update, and mention the other branches in the fork that you deliberately left alone.
