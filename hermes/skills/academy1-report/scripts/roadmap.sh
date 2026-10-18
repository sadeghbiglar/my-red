#!/usr/bin/env bash
echo "== ROADMAP (GitHub) =="
if ! command -v gh >/dev/null 2>&1; then echo "gh not available"; exit 0; fi
N=$(gh api "repos/sadeghbiglar/academy1/issues?state=open&per_page=100" --jq '[.[]|select(.pull_request|not)]|length' 2>/dev/null)
echo "total open issues: ${N:-?}"
for MS in "M0 بنیاد و زیرساخت" "M1 دانش‌آموزان" "M2 اساتید و مالی پرسنل" "M3 دوره‌ها و ثبت‌نام" "M4 زمان‌بندی و حضور و غیاب" "M5 نمرات و ارزیابی" "M6 مالی و شهریه" "M7 گزارش‌ها و داشبورد" "M8 اتمام و سخت‌سازی"; do
  C=$(gh api "repos/sadeghbiglar/academy1/issues?state=open&per_page=100" --jq "[.[]|select(.pull_request|not)|select(.milestone.title==\"$MS\")]|length" 2>/dev/null)
  printf "  %-32s %s open\n" "$MS" "${C:-?}"
done
echo "-- next up --"
gh issue list --repo sadeghbiglar/academy1 --state open --limit 3 --json number,title --jq '.[] | "  #\(.number) \(.title)"' 2>/dev/null || true
