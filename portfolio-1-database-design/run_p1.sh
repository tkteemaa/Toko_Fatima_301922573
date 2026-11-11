#!/usr/bin/env bash
# run_p1.sh — Portfolio 1 end-to-end runner.
# Codespaces-safe: uses sudo runuser -u postgres -- and Unix socket.

set -euo pipefail
cd "$(dirname "$0")"

PSQL="sudo runuser -u postgres -- psql -h /var/run/postgresql -d splashpoint"

echo "==> [0/6] Store and show times in Lagos time (WAT, UTC+1)"
$PSQL -c "ALTER DATABASE splashpoint SET timezone TO 'Africa/Lagos';"

echo "==> [1/6] (Re)create the schema"
$PSQL -v ON_ERROR_STOP=1 -f schema.sql

echo "==> [2/6] Load small hand-crafted seed"
$PSQL -v ON_ERROR_STOP=1 -f seed.sql

echo "==> [3/6] Generate 50k+ enrolments (this takes ~30-60s)"
python3 bulk_generate.py

echo "==> [4/6] Bulk-load the CSVs"
# bulk_load.sql uses \copy which reads client-side files; we run it as the
# codespace user so it can read ./bulk_data/.
psql -h /var/run/postgresql -d splashpoint -v ON_ERROR_STOP=1 -f bulk_load.sql

echo "==> [5/6] Verify row counts"
$PSQL -c "
  SELECT 'pool'           AS t, count(*) FROM pool
  UNION ALL SELECT 'lane',          count(*) FROM lane
  UNION ALL SELECT 'instructor',    count(*) FROM instructor
  UNION ALL SELECT 'guardian',      count(*) FROM guardian
  UNION ALL SELECT 'swimmer',       count(*) FROM swimmer
  UNION ALL SELECT 'lesson_type',   count(*) FROM lesson_type
  UNION ALL SELECT 'lesson_session',count(*) FROM lesson_session
  UNION ALL SELECT 'enrolment',     count(*) FROM enrolment
  UNION ALL SELECT 'payment',       count(*) FROM payment
  ORDER BY t;"

echo "==> [6/6] Run constraint tests (each must FAIL)"
$PSQL -v ON_ERROR_STOP=0 -f constraints_test.sql

echo
echo "==> Structure evidence (constraints and triggers)"
$PSQL -c '\d lesson_session'
$PSQL -c '\d swimmer'
$PSQL -c '\d enrolment'

echo
echo "P1 DONE. Screenshot:"
echo "  - The row-count table above (must show 50,000+ enrolments)"
echo "  - The constraints_test.sql output (every test should print an ERROR)"
echo "  - psql -h /var/run/postgresql -d splashpoint -c '\\d lesson_session'"
echo "    (shows both exclusion constraints and the CHECK constraints)"
echo "  - psql -h /var/run/postgresql -d splashpoint -c '\\d+ swimmer'"
echo "    (shows Triggers: trg_swimmer_guardian)"
echo "  - psql -h /var/run/postgresql -d splashpoint -c '\\d+ enrolment'"
echo "    (shows Triggers: trg_group_capacity)"
