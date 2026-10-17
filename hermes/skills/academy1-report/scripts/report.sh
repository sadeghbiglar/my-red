#!/usr/bin/env bash
# academy1 start-of-session report.
# Prints branch, recent commits, working-tree state, upstream divergence, server.
set -uo pipefail
REPO=/home/runner/academy1

if [ ! -d "$REPO/.git" ]; then
  echo "REPO_MISSING: $REPO is not a git repo"
  exit 1
fi

cd "$REPO" || exit 1

echo "== BRANCH =="
git branch --show-current

echo "== LAST COMMIT =="
git log -1 --date=iso --format='%h %ad %an %s'

echo "== RECENT COMMITS =="
git log --oneline -8

echo "== UNPUSHED =="
git log --oneline origin/academy..HEAD 2>/dev/null || echo "(no origin/academy ref)"

echo "== DIRTY =="
git status --short || true

echo "== DIFFSTAT =="
git diff --stat || true

echo "== SERVER :8000 =="
if (ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null) | grep -q ':8000'; then
  (ss -ltnp 2>/dev/null || netstat -ltnp 2>/dev/null) | grep ':8000'
else
  echo "nothing listening on :8000"
fi

echo "== TOOLS =="
if php -m 2>/dev/null | grep -q '^pdo_sqlite$'; then
  echo "pdo_sqlite: yes"
else
  echo "pdo_sqlite: MISSING (sqlite test suite cannot run)"
fi
if systemctl --user list-unit-files 2>/dev/null | grep -q academy1-serve; then
  echo "academy1-serve.service: present"
else
  echo "academy1-serve.service: ABSENT (server unsupervised)"
fi