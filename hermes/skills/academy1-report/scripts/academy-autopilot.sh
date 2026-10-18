#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────
#  خلبان خودکار توسعه academy1
#
#  در هر بوت ماشین اجرا می‌شود، صف را می‌خواند، روی برنج academy کار می‌کند،
#  تست می‌گیرد، commit و push می‌کند، و صف را به‌روز می‌کند.
#
#  هیچ‌وقت به main دست نمی‌زند: main شاخه انتشار است و به تأیید کاربر نیاز
#  دارد. کاربر تأیید کرد که کار تا تمام شدن همه issueها ادامه دارد.
# ─────────────────────────────────────────────────────────────
set -uo pipefail

REPO=/home/runner/academy1
QUEUE="$REPO/.academy/queue.json"
BRANCH=academy
MAX_ISSUES_PER_RUN=1     # یک issue در هر اجرا؛ اگر بیشتر شد ریسک از دست رفتن کار بالا می‌رود

cd "$REPO" || { echo "REPO_MISSING"; exit 1; }

log() { printf '[academy-autopilot] %s\n' "$*"; }

[ -f "$QUEUE" ] || { log "NO_QUEUE: $QUEUE missing"; exit 1; }

# ── وضعیت مخزن ────────────────────────────────────────────
CURRENT=$(git branch --show-current)
if [ "$CURRENT" != "$BRANCH" ]; then
  log "switching to $BRANCH (was $CURRENT)"
  git checkout "$BRANCH" 2>&1 | tail -2
fi

git fetch origin "$BRANCH" --quiet 2>/dev/null || true
BEHIND=$(git rev-list --count HEAD..origin/$BRANCH 2>/dev/null || echo 0)
if [ "$BEHIND" -gt 0 ]; then
  log "fast-forwarding from origin/$BRANCH ($BEHIND commits)"
  git merge --ff-only origin/$BRANCH 2>&1 | tail -2
fi

# فایل‌های lockfile نباید در commit بروند: تغییراتشان از نصب پکیج است،
# نه از کار ما، و قاطی شدنشان scope کار را غیرقابل بازبینی می‌کند.
LOCKFILES="composer.json composer.lock package-lock.json package.json"

stage_all_but_locks() {
  git add -A
  for f in $LOCKFILES; do
    git restore --staged "$f" 2>/dev/null || true
  done
}

# ── انتخاب کار بعدی ───────────────────────────────────────
IFS=$'\t' read -r ISSUE TITLE WHY < <(python3 - "$QUEUE" <<'PY'
import json, sys
q = json.load(open(sys.argv[1]))
if q.get("in_progress"):
    item = q["in_progress"]
else:
    nxt = q.get("next") or []
    if not nxt:
        print("NONE\t\t\t"); sys.exit(0)
    item = nxt[0]
print("%s\t%s\t%s" % (item.get("issue"), item.get("title"), item.get("why", "")))

PY
)

if [ "${ISSUE:-NONE}" = "NONE" ]; then
  log "QUEUE_EMPTY: همه issueهای صف تمام شده‌اند — کار متوقف، نه خراب."
  exit 0
fi

log "next issue #${ISSUE}: ${TITLE}"
log "why: ${WHY}"

# ── اجرای کار توسط عامل ───────────────────────────────────
# عامل باید issue را بخواند، کد بزند، تست بنویسد، گیت کند.
# prompt صریحاً می‌گوید main را لمس نکند.
PROMPT=$(cat <<EOP
تو خلبان خودکار توسعه پروژه academy1 هستی (آموزشگاه خصوصی، Laravel 13 + Livewire 4 + mary UI).

کار فعلی: issue #${ISSUE} — ${TITLE}
دلیل اولویت: ${WHY}

الزامات سخت (از REQUIREMENTS.md):
- همه‌جا تاریخ شمسی؛ در DB میلادی. از helpers.php استفاده کن: jalali_date() برای نمایش، miladi_date() برای ورودی، parse_number() برای اعداد. هرگز مستقیم Jalalian::fromDateTime را در view صدا نزن.
- فیلد تاریخ فقط از کامپوننت jalali-date-picker (app/Livewire/JalaliDatePicker.php) استفاده کند.
- تست‌ها class-based PHPUnit هستند، Pest نیست.
- فارسی و RTL.

روش کار:
1. issue را از GitHub بخوان: gh issue view ${ISSUE} --repo sadeghbiglar/academy1
2. کد را بنویس، تست بنویس (اول تست).
3. دروازه‌ها باید سبز شود: php artisan test و php vendor/laravel/pint/builds/pint
4. یک issue = یک commit با پیام توضیحی که «چرا» را بگوید نه اینکه «چه» را.
5. commit و push روی برنج academy. به main هرگز دست نزن.
6. اگر issue تمام شد: در GitHub issue را close کن و صف را به‌روز کن (پایین توضیح داده شده).
7. اگر وسط کار متوقف شدی، کار ناتمام را commit کن و issue را باز بگذار — ناقص بهتر از گم‌شده است.

به‌روزرسانی صف — فایل ${QUEUE}:
- issue انجام‌شده را به آرایه done اضافه کن.
- از next حذفش کن و اولین عنصر باقیمانده را در_progress بگذار (اگر کار تمام نشده) یا next[0] را بردار.
- تاریخ امروز را در updated بنویس.

قانون: هیچ فایلی به اسم composer.json، composer.lock، package-lock.json، package.json را commit نکن؛ آن‌ها drift نصب پکیج‌اند نه کار تو.
EOP
)

RESULT=$(cd "$REPO" && timeout 3000 hermes chat -q "$PROMPT" 2>/tmp/autopilot-err.log)
RC=$?

if [ $RC -ne 0 ]; then
  log "AGENT_FAILED rc=$RC — tail of stderr:"
  tail -20 /tmp/autopilot-err.log || true
  exit $RC
fi

log "agent finished; verifying the gates"

# ── دروازه‌ها: کار نباید با تست قرمز تحویل شود ───────────────
cd "$REPO" || exit 1

if ! php artisan test 2>&1 | tail -3 | grep -q '"result":"passed"'; then
  log "TESTS_RED — کار commit نشد تا وقتی تست‌ها سبز نشوند"
  php artisan test 2>&1 | tail -5
  exit 1
fi
log "tests green"

if ! php vendor/laravel/pint/builds/pint --test 2>&1 | grep -q '"result":"pass"'; then
  log "PINT_DIRTY — در حال اصلاح"
  php vendor/laravel/pint/builds/pint >/dev/null 2>&1
  php artisan test 2>&1 | tail -3 | grep -q '"result":"passed"' || { log "TESTS_BROKE_AFTER_PINT"; exit 1; }
fi
log "pint green"

# ── commit و push ─────────────────────────────────────────
if git diff --cached --quiet && [ -z "$(git status --porcelain | grep -v '^??')" ]; then
  log "NOTHING_TO_COMMIT"
else
  stage_all_but_locks
  git -c user.name="sadeghbiglar/" -c user.email="sadeghbiglar/@users.noreply.github.com" \
      commit -q -m "issue #${ISSUE}: ${TITLE}

${WHY}

Tests and pint are green." 2>&1 | tail -2

  if [ -n "$(git diff --cached --name-only)" ]; then
    git add -A -- . ':!composer.json' ':!composer.lock' ':!package-lock.json' ':!package.json'
    git -c user.name="sadeghbiglar/" -c user.email="sadeghbiglar/@users.noreply.github.com" \
        commit -q --amend --no-edit 2>&1 | tail -1
  fi

  git push origin HEAD:refs/heads/$BRANCH 2>&1 | tail -2
  log "pushed $(git rev-parse --short HEAD)"
fi

echo "$RESULT"
log "done"
