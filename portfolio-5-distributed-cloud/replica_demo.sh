#!/usr/bin/env bash
# replica_demo.sh — ONE script for the streaming-replica demo (Portfolio 5).
# It switches between the two servers itself, so nothing is typed by hand:
#   1. who is who (port, in recovery?)   2. a write is REJECTED on the replica
#   3. insert on the primary             4. the row ARRIVES on the replica
#   5. replication lag                   6. pg_stat_replication on the primary
set -euo pipefail

PRIMARY="psql -h /var/run/postgresql -p 5432 -d splashpoint -X"
REPLICA="psql -h /var/run/postgresql -p 5433 -d splashpoint -X"

echo "===== 1. Who is who ====="
echo "-- PRIMARY:"
$PRIMARY -c "SELECT current_setting('port') AS port, pg_is_in_recovery() AS in_recovery, pg_current_wal_lsn() AS wal_lsn;"
echo "-- REPLICA:"
$REPLICA -c "SELECT current_setting('port') AS port, pg_is_in_recovery() AS in_recovery, pg_last_wal_replay_lsn() AS replayed_lsn;"

echo "===== 2. A write on the REPLICA is rejected ====="
$REPLICA -c "INSERT INTO pool (name, city, address, opening_time, closing_time)
             VALUES ('SplashPoint Gwarinpa', 'Abuja', '3rd Avenue, Gwarinpa, Abuja', '06:00', '20:00');" || true

echo "===== 3. Reads work on the replica and match the primary ====="
for side in PRIMARY REPLICA; do
  echo "-- $side:"
  ${!side} -At -c "SELECT 'sessions=' || (SELECT count(*) FROM lesson_session) || '  enrolments=' || (SELECT count(*) FROM enrolment) || '  instructors=' || (SELECT count(*) FROM instructor);"
done

echo "===== 4. Hire a new instructor on the PRIMARY, then look for her on the REPLICA ====="
EMAIL="halima.danjuma@splashpoint.ng"
$PRIMARY -qc "DELETE FROM instructor WHERE email = '$EMAIL';"   # re-run safety (she teaches no lessons)
$PRIMARY -c "INSERT INTO instructor (first_name, last_name, phone, email, hire_date, certification_level)
             VALUES ('Halima', 'Danjuma', '08035551234', '$EMAIL', CURRENT_DATE, 'Level 2')
             RETURNING instructor_id, first_name, last_name, email;"
for i in $(seq 1 20); do
  FOUND=$($REPLICA -At -c "SELECT count(*) FROM instructor WHERE email = '$EMAIL';")
  [ "$FOUND" = "1" ] && break
  sleep 0.2
done
echo "-- REPLICA after ~$(( (i-1) * 200 )) ms of waiting:"
$REPLICA -c "SELECT instructor_id, first_name, last_name, email FROM instructor WHERE email = '$EMAIL';"

echo "===== 5. Replication lag seen from the REPLICA ====="
$REPLICA -c "SELECT pg_last_wal_receive_lsn() AS received, pg_last_wal_replay_lsn() AS replayed,
                    now() - pg_last_xact_replay_timestamp() AS time_since_last_replayed_tx;"

echo "===== 6. pg_stat_replication on the PRIMARY ====="
$PRIMARY -c "SELECT application_name, client_addr, state, sync_state, sent_lsn, replay_lsn,
                    write_lag, flush_lag, replay_lag FROM pg_stat_replication;"
echo "Replica demo finished."
