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

echo "== APP_KEY =="
KEYLEN=$(grep '^APP_KEY=' .env 2>/dev/null | cut -d= -f2 | tr -d '"' | tr -d '\n' | wc -c)
if [ "${KEYLEN:-0}" -lt 32 ]; then
  echo "APP_KEY: MISSING/EMPTY -> generating (this caused MissingAppKeyException)"
  php artisan key:generate --force 2>&1 | tail -1
else
  echo "APP_KEY: present ($KEYLEN chars)"
fi

echo "== RESERVE (:8080) =="
if systemctl is-active --quiet reserve 2>/dev/null; then
  RES_HDR=$(systemctl show -p ActiveEnterTimestamp --value reserve 2>/dev/null)
  RES_CODE=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 http://127.0.0.1:8080/ 2>/dev/null)
  RES_SETUP=$(curl -s --max-time 5 http://127.0.0.1:8080/api/status 2>/dev/null)
  echo "reserve.service: active (since ${RES_HDR:-?})"
  echo "http 127.0.0.1:8080 -> ${RES_CODE}"
  echo "api: ${RES_SETUP}"
  if [ -f /opt/reserve/data/reserve.db ]; then
    echo "db: $(sudo stat -c '%s bytes, modified %y' /opt/reserve/data/reserve.db 2>/dev/null || echo 'unreadable')"
  else
    echo "db: MISSING at /opt/reserve/data/reserve.db"
  fi
  # Only restart when it is actually unhealthy — restarting a healthy service on
  # every session would drop in-flight requests for no reason.
  if [ "$RES_CODE" != "200" ]; then
    sudo -n systemctl restart reserve >/dev/null 2>&1 \
      && echo "was unhealthy (${RES_CODE}) — restarted now" \
      || echo "WARNING: unhealthy (${RES_CODE}) and restart needs sudo"
  fi
else
  echo "reserve.service: NOT RUNNING — starting it"
  sudo -n systemctl start reserve >/dev/null 2>&1 \
    && echo "started; http 127.0.0.1:8080 -> $(curl -s -o /dev/null -w '%{http_code}' --max-time 8 http://127.0.0.1:8080/)" \
    || echo "start FAILED (needs sudo, or the install is gone after a reboot)"
fi


bash "$(dirname "$0")/autopilot-status.sh"
bash "$(dirname "$0")/roadmap.sh"

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