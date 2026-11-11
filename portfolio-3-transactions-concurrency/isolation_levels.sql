-- ============================================================================
-- isolation_levels.sql — demonstrates the phenomena each isolation level
-- prevents or allows.
--
-- IMPORTANT: This script demonstrates the phenomena in a SINGLE terminal using
-- a SEPARATE psql subprocess (called via \!) to simulate the second transaction.
-- This is the simplest way to demonstrate real concurrency in a single script.
--
-- For a step-by-step two-terminal demo, follow race_condition_guide.md.
-- ============================================================================

\set ON_ERROR_STOP 0
\pset pager off

\echo '===================================================================='
\echo 'PHENOMENON 1: NON-REPEATABLE READ'
\echo '  Under READ COMMITTED, the same SELECT inside one transaction can'
\echo '  return different rows if another transaction commits a change in'
\echo '  between. Under REPEATABLE READ, the SELECT returns the same snapshot.'
\echo '===================================================================='
\echo ''

-- Setup: pick a swimmer we will modify in the "second transaction"
-- \gset keeps the id/name in psql variables. The second session (\! psql) cannot
-- see this session's variables or temp tables, so it selects the SAME swimmer
-- with the same rule: the lowest swimmer_id among adults.
SELECT swimmer_id AS iso_id, first_name AS iso_name FROM swimmer
 WHERE age_class = 'Adult' ORDER BY swimmer_id LIMIT 1 \gset
\echo 'Target swimmer BEFORE:'
SELECT swimmer_id, first_name FROM swimmer
 WHERE swimmer_id = :iso_id;
\echo ''

\echo '--- Under READ COMMITTED (default) ---'
\echo 'T1 starts a transaction and reads the swimmer. THEN a second psql'
\echo 'session updates the swimmer and commits. T1 reads again — under'
\echo 'READ COMMITTED the new value IS visible (NON-REPEATABLE READ).'

BEGIN ISOLATION LEVEL READ COMMITTED;
\echo 'T1 first read:'
SELECT first_name FROM swimmer
 WHERE swimmer_id = :iso_id;

\echo '  [second session runs UPDATE + COMMIT in background]'
\! psql -h /var/run/postgresql -d splashpoint -c "UPDATE swimmer SET first_name='TEMP_RC_RENAMED' WHERE swimmer_id=(SELECT min(swimmer_id) FROM swimmer WHERE age_class='Adult');"

\echo 'T1 second read (same transaction):'
SELECT first_name FROM swimmer
 WHERE swimmer_id = :iso_id;
\echo '  ^^^ Should show TEMP_RC_RENAMED — NON-REPEATABLE READ happened.'
ROLLBACK;

-- restore
UPDATE swimmer SET first_name = :'iso_name'
 WHERE swimmer_id = :iso_id;
\echo ''

\echo '--- Under REPEATABLE READ ---'
\echo 'T1 starts a REPEATABLE READ transaction; both reads see the SAME snapshot.'

BEGIN ISOLATION LEVEL REPEATABLE READ;
\echo 'T1 first read:'
SELECT first_name FROM swimmer
 WHERE swimmer_id = :iso_id;

\! psql -h /var/run/postgresql -d splashpoint -c "UPDATE swimmer SET first_name='TEMP_RR_RENAMED' WHERE swimmer_id=(SELECT min(swimmer_id) FROM swimmer WHERE age_class='Adult');"

\echo 'T1 second read (same REPEATABLE READ transaction):'
SELECT first_name FROM swimmer
 WHERE swimmer_id = :iso_id;
\echo '  ^^^ Should show the ORIGINAL name — snapshot is frozen, no non-repeatable read.'
ROLLBACK;

-- restore
UPDATE swimmer SET first_name = :'iso_name'
 WHERE swimmer_id = :iso_id;
\echo ''

\echo '===================================================================='
\echo 'PHENOMENON 2: PHANTOM READ'
\echo '  Under READ COMMITTED, a COUNT(*) can change between two reads in'
\echo '  the same transaction if another transaction inserts/deletes matching'
\echo '  rows. PostgreSQL REPEATABLE READ prevents phantom reads.'
\echo '===================================================================='
\echo ''

\echo '--- Under READ COMMITTED ---'
BEGIN ISOLATION LEVEL READ COMMITTED;
\echo 'T1 first count of Adult swimmers:'
SELECT count(*) AS adults_before FROM swimmer WHERE age_class='Adult';

\! psql -h /var/run/postgresql -d splashpoint -c "INSERT INTO swimmer (first_name, last_name, dob, age_class, phone, email) VALUES ('PhantomRC','Test','1990-01-01','Adult','08090000999','phantom.rc@test.com');"

\echo 'T1 second count (same transaction):'
SELECT count(*) AS adults_after FROM swimmer WHERE age_class='Adult';
\echo '  ^^^ adults_after should be adults_before + 1 — PHANTOM READ happened.'
ROLLBACK;
-- clean up the inserted row
DELETE FROM swimmer WHERE email = 'phantom.rc@test.com';  -- the other session committed it
\echo ''

\echo '--- Under REPEATABLE READ ---'
BEGIN ISOLATION LEVEL REPEATABLE READ;
\echo 'T1 first count of Adult swimmers:'
SELECT count(*) AS adults_before FROM swimmer WHERE age_class='Adult';

\! psql -h /var/run/postgresql -d splashpoint -c "INSERT INTO swimmer (first_name, last_name, dob, age_class, phone, email) VALUES ('PhantomRR','Test','1990-01-01','Adult','08090000998','phantom.rr@test.com');"

\echo 'T1 second count (same REPEATABLE READ transaction):'
SELECT count(*) AS adults_after FROM swimmer WHERE age_class='Adult';
\echo '  ^^^ adults_after should EQUAL adults_before — PHANTOM READ prevented.'
ROLLBACK;
DELETE FROM swimmer WHERE email = 'phantom.rr@test.com';
\echo ''

\echo '===================================================================='
\echo 'PHENOMENON 3: WRITE SKEW (only prevented by SERIALIZABLE)'
\echo '  Under REPEATABLE READ, write skew is POSSIBLE.'
\echo '  Under SERIALIZABLE, PostgreSQL SSI detects the conflict and aborts.'
\echo '  run_race_demos.py Part 4 shows SSI aborting a booking, then the retry.'
\echo '===================================================================='
\echo ''

\echo 'Quick demonstration of SERIALIZABLE aborting on conflict:'
\echo 'T1 starts a SERIALIZABLE transaction and reads swimmer count.'
\echo 'T2 starts SERIALIZABLE, reads same count, INSERTs, COMMITs.'
\echo 'T1 then INSERTs and COMMITs — should get could not serialize access.'

-- T1: read
BEGIN ISOLATION LEVEL SERIALIZABLE;
SELECT count(*) AS t1_count FROM swimmer WHERE age_class='Adult';

-- T2: read, insert, commit (in subshell)
\! psql -h /var/run/postgresql -d splashpoint -c "BEGIN ISOLATION LEVEL SERIALIZABLE; SELECT count(*) FROM swimmer WHERE age_class='Adult'; INSERT INTO swimmer (first_name, last_name, dob, age_class, phone, email) VALUES ('SerialT2','Test','1990-01-01','Adult','08090000997','serial.t2@test.com'); COMMIT;"

-- T1: insert and commit (should fail with serialization conflict)
\echo 'T1 now INSERTs and COMMITs (should fail with serialization conflict):'
INSERT INTO swimmer (first_name, last_name, dob, age_class, phone, email)
VALUES ('SerialT1','Test','1990-01-01','Adult','08090000996','serial.t1@test.com');
COMMIT;
\echo '  ^^^ T1 should fail with: ERROR: could not serialize access due to read/write dependencies among transactions'
\echo '      (the INSERT or the COMMIT reports it; a failed COMMIT ends the transaction as a ROLLBACK)'

-- clean up
DELETE FROM swimmer WHERE email IN ('serial.t1@test.com','serial.t2@test.com');
\echo ''

\echo '===================================================================='
\echo 'ISOLATION LEVELS SUMMARY'
\echo '===================================================================='
\echo 'READ COMMITTED  (PG default): no dirty reads; non-repeatable reads POSSIBLE; phantoms POSSIBLE; write skew POSSIBLE.'
\echo 'REPEATABLE READ (PG):          no dirty reads; no non-repeatable reads; NO phantoms (PG-specific); write skew STILL POSSIBLE.'
\echo 'SERIALIZABLE  (PG SSI):        no dirty reads; no non-repeatable reads; no phantoms; no write skew. Conflicts abort with retry hint.'
