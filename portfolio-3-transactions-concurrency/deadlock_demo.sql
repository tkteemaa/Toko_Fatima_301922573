-- ============================================================================
-- deadlock_demo.sql — classic AB-BA deadlock with two real psql sessions.
-- T_A locks swimmer s1 then s2; T_B locks s2 then s1. PostgreSQL detects the
-- cycle and aborts one of them with "ERROR: deadlock detected".
-- (run_race_demos.py Part 6 shows the same thing step by step, plus the fix.)
-- ============================================================================

\set ON_ERROR_STOP 0
\pset pager off

\echo '===== DEADLOCK DEMO ====='
SELECT min(swimmer_id) AS s1 FROM swimmer WHERE age_class = 'Adult' \gset
SELECT min(swimmer_id) AS s2 FROM swimmer WHERE age_class = 'Adult' AND swimmer_id > :s1 \gset
\echo 'Lock targets: swimmer' :s1 'and swimmer' :s2

-- Write the two session scripts. (\o only redirects query OUTPUT, so the SQL
-- text is written with \! printf; :s1/:s2 are passed in with psql -v.)
\! printf '%s\n' "\\echo T_A: lock s1" "BEGIN;" "UPDATE swimmer SET phone = phone WHERE swimmer_id = :s1;" "SELECT pg_sleep(2);" "\\echo T_A: now lock s2" "UPDATE swimmer SET phone = phone WHERE swimmer_id = :s2;" "COMMIT;" > /tmp/splash_ta.sql
\! printf '%s\n' "\\echo T_B: lock s2" "BEGIN;" "UPDATE swimmer SET phone = phone WHERE swimmer_id = :s2;" "SELECT pg_sleep(2);" "\\echo T_B: now lock s1" "UPDATE swimmer SET phone = phone WHERE swimmer_id = :s1;" "COMMIT;" > /tmp/splash_tb.sql

\echo 'Launching T_A and T_B at the same time (each in its own psql session)...'
\! S1=$(psql -h /var/run/postgresql -d splashpoint -tAc "SELECT min(swimmer_id) FROM swimmer WHERE age_class='Adult'"); S2=$(psql -h /var/run/postgresql -d splashpoint -tAc "SELECT min(swimmer_id) FROM swimmer WHERE age_class='Adult' AND swimmer_id > $S1"); psql -h /var/run/postgresql -d splashpoint -v s1=$S1 -v s2=$S2 -f /tmp/splash_ta.sql > /tmp/splash_ta.out 2>&1 & psql -h /var/run/postgresql -d splashpoint -v s1=$S1 -v s2=$S2 -f /tmp/splash_tb.sql > /tmp/splash_tb.out 2>&1 & wait

\echo '----- T_A output -----'
\! cat /tmp/splash_ta.out
\echo '----- T_B output -----'
\! cat /tmp/splash_tb.out
\echo ''
\echo 'One session shows ERROR: deadlock detected (it was rolled back); the other COMMITs.'
\echo 'Fix: always lock rows in the SAME order (e.g. ascending swimmer_id) — see run_race_demos.py Part 6.'
