-- ============================================================================
-- bulk_load.sql — load CSVs emitted by bulk_generate.py into the schema.
-- Uses \copy from the file system (client-side). Run as the codespace user,
-- not as postgres, so \copy has read access to ./bulk_data/.
-- ============================================================================

\set ON_ERROR_STOP on
BEGIN;

-- Wipe any prior seed rows so the bulk load is idempotent
TRUNCATE payment, enrolment, lesson_session, lesson_type, swimmer, guardian,
         instructor, lane, pool RESTART IDENTITY CASCADE;

-- pools
\copy pool (pool_id, name, city, address, opening_time, closing_time) FROM 'bulk_data/pools.csv' WITH (FORMAT csv, HEADER true)
-- lanes
\copy lane (lane_id, pool_id, lane_number, max_capacity) FROM 'bulk_data/lanes.csv' WITH (FORMAT csv, HEADER true)
-- instructors
\copy instructor (instructor_id, first_name, last_name, phone, email, hire_date, certification_level) FROM 'bulk_data/instructors.csv' WITH (FORMAT csv, HEADER true)
-- guardians
\copy guardian (guardian_id, first_name, last_name, phone, email, relationship) FROM 'bulk_data/guardians.csv' WITH (FORMAT csv, HEADER true)
-- swimmers
\copy swimmer (swimmer_id, first_name, last_name, dob, age_class, phone, email, guardian_id) FROM 'bulk_data/swimmers.csv' WITH (FORMAT csv, HEADER true)
-- lesson types
\copy lesson_type (lesson_type_id, name, description, default_duration_min, is_group, capacity) FROM 'bulk_data/lesson_types.csv' WITH (FORMAT csv, HEADER true)
-- lesson sessions (during is GENERATED ALWAYS, so we omit it)
\copy lesson_session (session_id, pool_id, lane_id, instructor_id, lesson_type_id, start_time, end_time, duration_min, price) FROM 'bulk_data/lesson_sessions.csv' WITH (FORMAT csv, HEADER true)
-- enrolments — attended is nullable; CSV has empty string for NULL
\copy enrolment (enrolment_id, session_id, swimmer_id, enrol_date, status, attended) FROM 'bulk_data/enrolments.csv' WITH (FORMAT csv, HEADER true, NULL '')
-- payments
\copy payment (payment_id, enrolment_id, amount, payment_date, payment_method, status) FROM 'bulk_data/payments.csv' WITH (FORMAT csv, HEADER true)

-- sync sequences past the loaded IDs
SELECT setval('pool_pool_id_seq',         (SELECT MAX(pool_id)         FROM pool));
SELECT setval('lane_lane_id_seq',         (SELECT MAX(lane_id)         FROM lane));
SELECT setval('instructor_instructor_id_seq', (SELECT MAX(instructor_id) FROM instructor));
SELECT setval('guardian_guardian_id_seq', (SELECT MAX(guardian_id)     FROM guardian));
SELECT setval('swimmer_swimmer_id_seq',   (SELECT MAX(swimmer_id)      FROM swimmer));
SELECT setval('lesson_type_lesson_type_id_seq', (SELECT MAX(lesson_type_id) FROM lesson_type));
SELECT setval('lesson_session_session_id_seq',  (SELECT MAX(session_id)     FROM lesson_session));
SELECT setval('enrolment_enrolment_id_seq',     (SELECT MAX(enrolment_id)   FROM enrolment));
SELECT setval('payment_payment_id_seq',         (SELECT MAX(payment_id)     FROM payment));

COMMIT;

\echo 'Bulk load complete. Row counts:'
SELECT 'pool'           AS t, count(*) FROM pool
UNION ALL SELECT 'lane',          count(*) FROM lane
UNION ALL SELECT 'instructor',    count(*) FROM instructor
UNION ALL SELECT 'guardian',      count(*) FROM guardian
UNION ALL SELECT 'swimmer',       count(*) FROM swimmer
UNION ALL SELECT 'lesson_type',   count(*) FROM lesson_type
UNION ALL SELECT 'lesson_session',count(*) FROM lesson_session
UNION ALL SELECT 'enrolment',     count(*) FROM enrolment
UNION ALL SELECT 'payment',       count(*) FROM payment
ORDER BY t;
