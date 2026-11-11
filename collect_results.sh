#!/usr/bin/env bash
# collect_results.sh — gathers the REAL outputs of every portfolio into my_results.txt
# (paste that file back for the documentation). Run from the repo root.
cd "$(dirname "$0")"
OUT=my_results.txt

section() { echo; echo "################################################################"; echo "### $1"; echo "################################################################"; }
show() {  # file [max_lines]
  if [ -f "$1" ]; then
    if [ -n "${2:-}" ] && [ "$(wc -l < "$1")" -gt "$2" ]; then
      head -n "$2" "$1"; echo "... ($(wc -l < "$1") lines in total, rest in $1)"
    else cat "$1"; fi
  else echo "(no $1 — this part did not run)"; fi
}

{
  section "ENVIRONMENT"
  echo "date:       $(date '+%Y-%m-%d %H:%M %Z')"
  echo "repo:       ${GITHUB_REPOSITORY:-$(git config --get remote.origin.url 2>/dev/null)}"
  echo "codespace:  ${CODESPACE_NAME:-not a codespace}"
  echo "user:       $(whoami)"
  echo "postgres:   $(psql -h /var/run/postgresql -d splashpoint -Atc 'SHOW server_version' 2>/dev/null)"
  echo "mongodb:    $(mongosh --quiet --eval 'db.version()' 2>/dev/null)"
  echo "commits:"; git log --oneline -n 12 2>/dev/null

  section "P1 — DATABASE DESIGN"
  show portfolio-1-database-design/p1_output.log

  section "P2 — QUERY OPTIMISATION (summary)"
  show portfolio-2-query-optimisation/explain_summary.txt
  section "P2 — query answers + plans BEFORE (first 160 lines)"
  show portfolio-2-query-optimisation/explain_log_before.txt 160
  section "P2 — Q2/Q3 plans AFTER"
  if [ -f portfolio-2-query-optimisation/explain_log_after.txt ]; then
    awk '/--- Q2 EXPLAIN/,/--- Q3 EXPLAIN/' portfolio-2-query-optimisation/explain_log_after.txt
    awk '/--- Q3 EXPLAIN/,/Execution Time/' portfolio-2-query-optimisation/explain_log_after.txt
  else echo "(no explain_log_after.txt)"; fi

  section "P3 — TRANSACTIONS & CONCURRENCY"
  show portfolio-3-transactions-concurrency/p3_output.log

  section "P4 — NOSQL (MongoDB)"
  show portfolio-4-nosql/p4_output.log

  section "P5 — DISTRIBUTED & CLOUD"
  show portfolio-5-distributed-cloud/p5_output.log
} > "$OUT" 2>&1

echo "Wrote $OUT ($(wc -l < "$OUT") lines). Open it, press Ctrl+A, Ctrl+C and paste it back."
