#!/usr/bin/env bash
# run_p4.sh — Portfolio 4 end-to-end runner (MongoDB).
set -euo pipefail
cd "$(dirname "$0")"

MONGOSH="mongosh --quiet"

echo "==> [0/5] Make sure mongod is running"
if ! $MONGOSH --eval "db.runCommand({ping:1}).ok" >/dev/null 2>&1; then
  sudo mkdir -p /data/db
  sudo mongod --fork --logpath /var/log/mongod.log --dbpath /data/db --bind_ip 127.0.0.1
fi

echo "==> [1/5] Export the real ATTENDED lessons from PostgreSQL (P1) -> pg_attended.jsonl"
psql -h /var/run/postgresql -d splashpoint -v ON_ERROR_STOP=1 -At -c "
  SELECT json_build_object(
           'enrolment_id', e.enrolment_id, 'swimmer_id', s.swimmer_id,
           'swimmer_name', s.first_name || ' ' || s.last_name, 'age_class', s.age_class,
           'session_id', ls.session_id, 'instructor_id', ls.instructor_id,
           'lesson_type', lt.name, 'start_time', ls.start_time)
    FROM enrolment e
    JOIN swimmer s         ON s.swimmer_id = e.swimmer_id
    JOIN lesson_session ls ON ls.session_id = e.session_id
    JOIN lesson_type lt    ON lt.lesson_type_id = ls.lesson_type_id
   WHERE e.status = 'attended'
   ORDER BY s.swimmer_id, ls.start_time" > pg_attended.jsonl
echo "    $(wc -l < pg_attended.jsonl) attended lessons exported"

echo "==> [2/5] (Re)create progress_notes with the \$jsonSchema validator (+ 2 rejected test docs)"
$MONGOSH splashpoint schema_validation.js

echo ""
echo "==> [3/5] Seed one progress note per attended lesson (40,000+)"
$MONGOSH splashpoint seed_progress.js

echo ""
echo "==> [4/5] Aggregation pipelines"
$MONGOSH splashpoint aggregations.js

echo ""
echo "==> [5/5] Index demo: COLLSCAN before, IXSCAN after"
$MONGOSH splashpoint indexes.js

echo ""
echo "P4 DONE. Evidence: this output (p4_output.log), index_explain_before.txt, index_explain_after.txt"
