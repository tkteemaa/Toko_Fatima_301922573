-- ============================================================================
-- constraints_test.sql — every constraint tested. Each [n] test MUST FAIL.
-- Run with: psql -v ON_ERROR_STOP=0 -f constraints_test.sql
--
-- Each test builds its OWN situation from the real data (a pool with two
-- lanes, two instructors, a test day 30 days ahead with no generated sessions)
-- so no test depends on a hard-coded id that the bulk load may have changed.
-- Times are written in Lagos local time (+01). Everything runs inside ONE
-- transaction with ON_ERROR_ROLLBACK, and is rolled back at the end, so the
-- test rows never stay in the database.
-- ============================================================================

\set ON_ERROR_STOP 0
\set ON_ERROR_ROLLBACK on
\pset pager off

\echo '===================================================================='
\echo 'Each [n] test below should print ERROR from the named constraint.'
\echo 'An ERROR here = the constraint fired correctly.'
\echo '===================================================================='

BEGIN;

-- ---------------------------------------------------------------- fixtures --
SELECT l1.pool_id AS pool, l1.lane_id AS lane_a, l2.lane_id AS lane_b
  FROM lane l1 JOIN lane l2 ON l2.pool_id = l1.pool_id AND l2.lane_id > l1.lane_id
 ORDER BY l1.lane_id LIMIT 1 \gset
SELECT lane_id AS other_pool_lane FROM lane WHERE pool_id <> :pool ORDER BY lane_id LIMIT 1 \gset
SELECT min(instructor_id) AS ins_a, max(instructor_id) AS ins_b FROM instructor \gset
SELECT lesson_type_id AS lt_private FROM lesson_type WHERE NOT is_group ORDER BY lesson_type_id LIMIT 1 \gset
SELECT lesson_type_id AS lt_group, capacity AS gcap FROM lesson_type
 WHERE is_group ORDER BY capacity DESC, lesson_type_id LIMIT 1 \gset
SELECT ((now() AT TIME ZONE 'Africa/Lagos')::date + 30)::text AS tday \gset
SELECT swimmer_id AS adult_1 FROM swimmer WHERE age_class = 'Adult' ORDER BY swimmer_id LIMIT 1 \gset
SELECT swimmer_id AS adult_2 FROM swimmer WHERE age_class = 'Adult' ORDER BY swimmer_id OFFSET 1 LIMIT 1 \gset

\echo 'Fixtures: pool' :pool ', lanes' :lane_a '&' :lane_b ', instructors' :ins_a '&' :ins_b ', test day' :tday

-- base group session: lane_a, instructor ins_a, 10:00-10:45 Lagos time
INSERT INTO lesson_session (pool_id, lane_id, instructor_id, lesson_type_id,
                            start_time, end_time, duration_min, price)
VALUES (:pool, :lane_a, :ins_a, :lt_group,
        (:'tday' || ' 10:00+01')::timestamptz, (:'tday' || ' 10:45+01')::timestamptz, 45, 5000)
RETURNING session_id AS base_sid \gset

-- base private session: lane_b, instructor ins_b, 12:00-12:30 Lagos time, one adult enrolled
INSERT INTO lesson_session (pool_id, lane_id, instructor_id, lesson_type_id,
                            start_time, end_time, duration_min, price)
VALUES (:pool, :lane_b, :ins_b, :lt_private,
        (:'tday' || ' 12:00+01')::timestamptz, (:'tday' || ' 12:30+01')::timestamptz, 30, 8000)
RETURNING session_id AS priv_sid \gset
INSERT INTO enrolment (session_id, swimmer_id, status)
VALUES (:priv_sid, :adult_1, 'confirmed') RETURNING enrolment_id AS priv_eid \gset

-- --------------------------------------------------------------------- tests --
\echo ''
\echo '[1] Lane overlap (same lane, different instructor) — expect exclusion_violation on excl_lane_overlap'
INSERT INTO lesson_session (pool_id, lane_id, instructor_id, lesson_type_id, start_time, end_time, duration_min, price)
VALUES (:pool, :lane_a, :ins_b, :lt_private,
        (:'tday' || ' 10:15+01')::timestamptz, (:'tday' || ' 10:45+01')::timestamptz, 30, 8000);

\echo ''
\echo '[2] Instructor overlap (same instructor, other lane) — expect exclusion_violation on excl_instructor_overlap'
INSERT INTO lesson_session (pool_id, lane_id, instructor_id, lesson_type_id, start_time, end_time, duration_min, price)
VALUES (:pool, :lane_b, :ins_a, :lt_private,
        (:'tday' || ' 10:15+01')::timestamptz, (:'tday' || ' 10:45+01')::timestamptz, 30, 8000);

\echo ''
\echo '[3] Session starting 05:30 Lagos time — expect check_violation (start before 06:00)'
INSERT INTO lesson_session (pool_id, lane_id, instructor_id, lesson_type_id, start_time, end_time, duration_min, price)
VALUES (:pool, :lane_b, :ins_b, :lt_private,
        (:'tday' || ' 05:30+01')::timestamptz, (:'tday' || ' 06:00+01')::timestamptz, 30, 8000);

\echo ''
\echo '[4] Session ending 20:30 Lagos time — expect check_violation (end after 20:00)'
INSERT INTO lesson_session (pool_id, lane_id, instructor_id, lesson_type_id, start_time, end_time, duration_min, price)
VALUES (:pool, :lane_b, :ins_b, :lt_private,
        (:'tday' || ' 19:45+01')::timestamptz, (:'tday' || ' 20:30+01')::timestamptz, 45, 5000);

\echo ''
\echo '[5] Session too short (15 min) — expect check_violation'
INSERT INTO lesson_session (pool_id, lane_id, instructor_id, lesson_type_id, start_time, end_time, duration_min, price)
VALUES (:pool, :lane_b, :ins_b, :lt_private,
        (:'tday' || ' 13:00+01')::timestamptz, (:'tday' || ' 13:15+01')::timestamptz, 15, 8000);

\echo ''
\echo '[6] Session too long (90 min) — expect check_violation'
INSERT INTO lesson_session (pool_id, lane_id, instructor_id, lesson_type_id, start_time, end_time, duration_min, price)
VALUES (:pool, :lane_b, :ins_b, :lt_private,
        (:'tday' || ' 13:00+01')::timestamptz, (:'tday' || ' 14:30+01')::timestamptz, 90, 15000);

\echo ''
\echo '[7] Payment amount 0 — expect check_violation on payment_amount_check'
INSERT INTO payment (enrolment_id, amount, payment_method, status) VALUES (:priv_eid, 0.00, 'Cash', 'paid');

\echo ''
\echo '[7b] Payment amount negative — expect check_violation on payment_amount_check'
INSERT INTO payment (enrolment_id, amount, payment_method, status) VALUES (:priv_eid, -500.00, 'Cash', 'paid');

\echo ''
\echo '[8] Group session over capacity — expect check_violation from trg_group_capacity'
\echo '    (first fill the base group session to capacity with Child/Teen swimmers)'
INSERT INTO enrolment (session_id, swimmer_id, status)
SELECT :base_sid, swimmer_id, 'confirmed' FROM swimmer
 WHERE age_class IN ('Child','Teen') ORDER BY swimmer_id LIMIT :gcap;
SELECT count(*) AS enrolled_now, :gcap AS capacity FROM enrolment WHERE session_id = :base_sid;
INSERT INTO enrolment (session_id, swimmer_id, status)
SELECT :base_sid, swimmer_id, 'confirmed' FROM swimmer
 WHERE age_class IN ('Child','Teen') ORDER BY swimmer_id OFFSET :gcap LIMIT 1;

\echo ''
\echo '[9] Second swimmer in a private session — expect check_violation from trg_group_capacity'
INSERT INTO enrolment (session_id, swimmer_id, status) VALUES (:priv_sid, :adult_2, 'confirmed');

\echo ''
\echo '[10] Under-18 swimmer without a guardian — expect check_violation from trg_swimmer_guardian'
INSERT INTO swimmer (first_name, last_name, dob, age_class, phone, email, guardian_id)
VALUES ('Zainab', 'Garba', (CURRENT_DATE - INTERVAL '10 years')::date, 'Child', NULL, NULL, NULL);

\echo ''
\echo '[10b] Date of birth in the future — expect check_violation from trg_swimmer_guardian'
INSERT INTO swimmer (first_name, last_name, dob, age_class, phone, email, guardian_id)
VALUES ('Musa', 'Danjuma', CURRENT_DATE + 5, 'Adult', '08031234567', 'musa.danjuma@gmail.com', NULL);

\echo ''
\echo '[11] Pool in a city other than Abuja/Lagos — expect check_violation on pool_city_check'
INSERT INTO pool (name, city, address, opening_time, closing_time)
VALUES ('SplashPoint Kano', 'Kano', 'Zoo Road, Kano', '06:00:00', '20:00:00');

\echo ''
\echo '[12] Lesson type capacity 10 — expect check_violation on lesson_type_capacity_check'
INSERT INTO lesson_type (name, description, default_duration_min, is_group, capacity)
VALUES ('Mega Group', 'Should fail', 45, TRUE, 10);

\echo ''
\echo '[13] Payment method Crypto — expect check_violation on payment_payment_method_check'
INSERT INTO payment (enrolment_id, amount, payment_method, status) VALUES (:priv_eid, 8000.00, 'Crypto', 'paid');

\echo ''
\echo '[14] Same swimmer enrolled twice in one session — expect unique_violation'
INSERT INTO enrolment (session_id, swimmer_id, status) VALUES (:priv_sid, :adult_1, 'cancelled');

\echo ''
\echo '[15] Lane from a different pool — expect check_violation from trg_session_lane_pool'
INSERT INTO lesson_session (pool_id, lane_id, instructor_id, lesson_type_id, start_time, end_time, duration_min, price)
VALUES (:pool, :other_pool_lane, :ins_b, :lt_private,
        (:'tday' || ' 15:00+01')::timestamptz, (:'tday' || ' 15:30+01')::timestamptz, 30, 8000);

\echo ''
\echo '[16] CONTROL (should SUCCEED): mark attendance in the FULL group session.'
\echo '     The capacity trigger does not count the row being updated, so this works.'
UPDATE enrolment SET status = 'attended', attended = TRUE WHERE session_id = :base_sid;

ROLLBACK;

\echo ''
\echo '===================================================================='
\echo 'Tests [1]-[15] should each show an ERROR; [16] should show UPDATE n.'
\echo 'All test rows were rolled back (the database is unchanged).'
\echo '===================================================================='
