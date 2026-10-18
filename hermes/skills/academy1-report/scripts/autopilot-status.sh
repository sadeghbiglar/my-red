#!/usr/bin/env bash
# خلاصه وضعیت خلبان خودکار — در report.sh صدا زده می‌شود
REPO=/home/runner/academy1
QUEUE="$REPO/.academy/queue.json"

echo "== AUTOPILOT =="
if [ ! -f "$QUEUE" ]; then
  echo "queue: MISSING ($QUEUE) — autopilot will not run"
  exit 0
fi

python3 - "$QUEUE" <<'PY'
import json, sys
q = json.load(open(sys.argv[1]))
done = q.get("done") or []
nxt = q.get("next") or []
ip = q.get("in_progress")
print("done: %d   queued: %d" % (len(done), len(nxt)))
if ip:
    print("IN PROGRESS  #%s  %s" % (ip.get("issue"), ip.get("title")))
if nxt:
    print("NEXT         #%s  %s" % (nxt[0].get("issue"), nxt[0].get("title")))
elif not ip:
    print("queue empty — all planned issues finished")
PY

# آخرین اجرای واقعی، اگر لاگش مانده باشد
if [ -f /tmp/autopilot.log ]; then
  echo "last run:"
  grep '^\[academy-autopilot\]' /tmp/autopilot.log | tail -6 | sed 's/^/  /'
fi
