#!/usr/bin/env bash
# Triage a Hermes plugin security scan WITHOUT overriding it.
# Usage: bash scripts/triage-plugin-scan.sh owner/repo
# Installs nothing. A blocked install attempt is the input it reads.
set -uo pipefail

REPO="${1:-}"
if [ -z "$REPO" ]; then
  echo "usage: triage-plugin-scan.sh owner/repo" >&2
  exit 64
fi

LOG="$(mktemp -t hermes-scan-XXXXXX.log)"
hermes plugins install "$REPO" --enable >"$LOG" 2>&1
rc=$?
echo "install exit=$rc (1 = blocked by scan, which is the expected outcome here)"
echo "full log: $LOG"

echo
echo "== verdict =="
grep -E 'Verdict|Decision:' "$LOG" | sort -u

# The report is emitted twice per attempt; dedupe before counting.
FINDINGS="$(mktemp -t hermes-findings-XXXXXX)"
grep -E '^ +(LOW|MEDIUM|HIGH|CRITICAL) ' "$LOG" | sort -u >"$FINDINGS"
echo "unique findings: $(wc -l <"$FINDINGS")"

echo
echo "== severity x category =="
tr -s ' ' <"$FINDINGS" | awk '{print $1, $2}' | sort | uniq -c | sort -rn

echo
echo "== findings by top-level directory =="
tr -s ' ' <"$FINDINGS" | grep -oE '[^ ]+\.[A-Za-z]+' | cut -d/ -f1 | sort | uniq -c | sort -rn

echo
echo "== findings in the executable surface (read these yourself) =="
grep -E '(\.hermes-plugin/|hooks/|scripts/|bin/|index\.[jt]s|plugin\.(yaml|json))' "$FINDINGS" || \
  echo "(none — all findings are docs/tests prose)"

echo
echo "== read the entrypoint before deciding =="
for f in .hermes-plugin/plugin.yaml .hermes-plugin/__init__.py plugin.yaml index.js; do
  [ -e "$f" ] && echo "present: $f"
done