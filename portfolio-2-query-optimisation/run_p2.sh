#!/usr/bin/env bash
# run_p2.sh — Portfolio 2 end-to-end runner.
# Fair comparison: drop the P2 indexes, ANALYZE, capture BEFORE plans,
# add the indexes, ANALYZE, capture AFTER plans, then print a timing table.

set -euo pipefail
cd "$(dirname "$0")"

PSQL="psql -h /var/run/postgresql -d splashpoint"

echo "==> [1/5] Reset: drop the P2 indexes (so re-runs are fair) and ANALYZE"
$PSQL -v ON_ERROR_STOP=1 -q <<'SQL'
DROP INDEX IF EXISTS idx_session_start, idx_session_pool_start, idx_session_instructor_start,
  idx_session_lane_start, idx_enrolment_session_status, idx_enrolment_no_show,
  idx_payment_status_paid, idx_enrolment_attended;
ANALYZE;
SQL

echo "==> [2/5] BEFORE indexes: run queries.sql -> explain_log_before.txt"
$PSQL -v ON_ERROR_STOP=1 -f queries.sql > explain_log_before.txt 2>&1
echo "    wrote explain_log_before.txt"

echo "==> [3/5] Add the indexes (indexes.sql) and ANALYZE"
$PSQL -v ON_ERROR_STOP=1 -f indexes.sql

echo "==> [4/5] AFTER indexes: run queries.sql -> explain_log_after.txt"
$PSQL -v ON_ERROR_STOP=1 -f queries.sql > explain_log_after.txt 2>&1
echo "    wrote explain_log_after.txt"

echo "==> [5/5] Before/after summary (Execution Time from EXPLAIN ANALYZE)"
summ() {  # file -> "Qn<TAB>ms<TAB>how lesson_session is read<TAB>how enrolment is read"
  awk '
    function kind(line,   k) {
      if (line ~ /Index Only Scan/) k="Index Only Scan"; else if (line ~ /Bitmap Heap Scan/) k="Bitmap Heap Scan";
      else if (line ~ /Index Scan/) k="Index Scan"; else k="Seq Scan";
      if (match(line, /using [a-z_]+/)) k = k " (" substr(line, RSTART+6, RLENGTH-6) ")";
      return k }
    /^--- Q[0-9] EXPLAIN ANALYZE ---/ { q=$2; ls="-"; en="-" }
    q!="" && ls=="-" && / on (public\.)?lesson_session / { ls=kind($0) }
    q!="" && ls=="Bitmap Heap Scan" && /Bitmap Index Scan on/ { match($0, /on [a-z_]+/); ls=ls " (" substr($0, RSTART+3, RLENGTH-3) ")" }
    q!="" && en=="-" && / on (public\.)?enrolment / { en=kind($0) }
    q!="" && /Execution Time:/ { printf "%s\t%s\t%s\t%s\n", q, $3, ls, en; q="" }
  ' "$1"
}
summ explain_log_before.txt > /tmp/p2_before.$$
summ explain_log_after.txt  > /tmp/p2_after.$$
{
  printf "%-3s %10s %10s %7s | %-42s %-18s | %-42s %s\n" "Q" "before_ms" "after_ms" "speedup" "BEFORE lesson_session" "BEFORE enrolment" "AFTER lesson_session" "AFTER enrolment"
  paste /tmp/p2_before.$$ /tmp/p2_after.$$ | awk -F'\t' '{
      sp = ($6 > 0) ? sprintf("%.1fx", $2/$6) : "-";
      printf "%-3s %10s %10s %7s | %-42s %-18s | %-42s %s\n", $1, $2, $6, sp, $3, $4, $7, $8 }'
} | tee explain_summary.txt
rm -f /tmp/p2_before.$$ /tmp/p2_after.$$

echo
echo "P2 DONE. Evidence files: explain_log_before.txt, explain_log_after.txt, explain_summary.txt"
echo "  Full-history aggregates (Q4, Q5) are expected to keep a Seq Scan — see explain_results.md."
