#!/usr/bin/env bash
# run_p3.sh — Portfolio 3 end-to-end runner (everything is automated).
set -euo pipefail
cd "$(dirname "$0")"

PSQL="psql -h /var/run/postgresql -d splashpoint"

echo "==> [1/5] Install enrol_swimmer() function"
$PSQL -v ON_ERROR_STOP=1 -f enrol_swimmer.sql

echo ""
echo "==> [2/5] COMMIT / ROLLBACK demo (expected ERROR in Path B1 = the rollback being shown)"
$PSQL -f commit_rollback_demo.sql

echo ""
echo "==> [3/5] Isolation levels demo (READ COMMITTED vs REPEATABLE READ vs SERIALIZABLE)"
$PSQL -f isolation_levels.sql

echo ""
echo "==> [4/5] Deadlock demo (two psql sessions, AB-BA)"
$PSQL -f deadlock_demo.sql

echo ""
echo "==> [5/5] Race-condition demos, 6 parts, two real sessions -> race_demos_output.log"
python3 run_race_demos.py 2>&1 | tee race_demos_output.log

echo ""
echo "P3 DONE. Evidence: this output (p3_output.log) and race_demos_output.log"
