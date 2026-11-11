-- ============================================================================
-- commit_rollback_demo.sql — COMMIT (success) and ROLLBACK (failure) paths of
-- enrol_swimmer(). SplashPoint Swim School (Portfolio 3, MIT 8103)
-- Uses \gset variables (no hand-copied ids) and picks a future adult group
-- session with at least 2 free places, so it works on every re-run.
-- ============================================================================

\set ON_ERROR_STOP 0
\pset pager off

\echo '===================================================================='
\echo 'Setup: a future adult group session with free places + 2 adult swimmers'
\echo '===================================================================='
SELECT ls.session_id AS sid, lt.name AS lesson, lt.capacity AS cap,
       to_char(ls.start_time AT TIME ZONE 'Africa/Lagos', 'YYYY-MM-DD HH24:MI') AS starts_lagos
  FROM lesson_session ls
  JOIN lesson_type lt ON lt.lesson_type_id = ls.lesson_type_id
 WHERE lt.is_group AND lt.name IN ('Group Adult', 'Adult Beginner')
   AND ls.start_time > now()
   AND (SELECT count(*) FROM enrolment e WHERE e.session_id = ls.session_id
         AND e.status IN ('confirmed','attended')) <= lt.capacity - 2
 ORDER BY ls.start_time LIMIT 1 \gset
SELECT swimmer_id AS sw1 FROM swimmer s
 WHERE age_class = 'Adult'
   AND NOT EXISTS (SELECT 1 FROM enrolment e WHERE e.session_id = :sid AND e.swimmer_id = s.swimmer_id)
 ORDER BY swimmer_id LIMIT 1 \gset
SELECT swimmer_id AS sw2 FROM swimmer s
 WHERE age_class = 'Adult' AND swimmer_id <> :sw1
   AND NOT EXISTS (SELECT 1 FROM enrolment e WHERE e.session_id = :sid AND e.swimmer_id = s.swimmer_id)
 ORDER BY swimmer_id LIMIT 1 \gset
\echo 'Session' :sid '(' :lesson ', capacity' :cap ', starts' :starts_lagos ') — swimmers' :sw1 'and' :sw2

\echo ''
\echo '===================================================================='
\echo 'PATH A — SUCCESS: enrol + valid payment, then COMMIT'
\echo '===================================================================='
SELECT (SELECT count(*) FROM enrolment WHERE session_id = :sid) AS enrolments_before,
       (SELECT count(*) FROM payment p JOIN enrolment e USING (enrolment_id) WHERE e.session_id = :sid) AS payments_before;
BEGIN;
SELECT enrol_swimmer(:sid, :sw1, 'Card') AS new_enrolment_id;
COMMIT;
SELECT (SELECT count(*) FROM enrolment WHERE session_id = :sid) AS enrolments_after,
       (SELECT count(*) FROM payment p JOIN enrolment e USING (enrolment_id) WHERE e.session_id = :sid) AS payments_after;
\echo '  ^ both +1: the enrolment AND its payment were committed together.'

\echo ''
\echo '===================================================================='
\echo 'PATH B1 — FAILURE INSIDE THE FUNCTION: invalid payment method'
\echo '  The enrolment row is inserted first; then the payment INSERT breaks the'
\echo '  payment_method CHECK. The whole call fails, so the enrolment disappears too.'
\echo '===================================================================='
BEGIN;
SELECT enrol_swimmer(:sid, :sw2, 'Crypto') AS new_enrolment_id;
ROLLBACK;
SELECT (SELECT count(*) FROM enrolment WHERE session_id = :sid AND swimmer_id = :sw2) AS sw2_enrolments,
       (SELECT count(*) FROM payment p JOIN enrolment e USING (enrolment_id)
         WHERE e.session_id = :sid AND e.swimmer_id = :sw2) AS sw2_payments;
\echo '  ^ both 0: no half-finished booking was left behind (atomicity).'

\echo ''
\echo '===================================================================='
\echo 'PATH B2 — EXPLICIT ROLLBACK: enrol succeeds, then the card is declined'
\echo '===================================================================='
BEGIN;
SELECT enrol_swimmer(:sid, :sw2, 'Card') AS new_enrolment_id;
\echo 'Inside the open transaction swimmer' :sw2 'is enrolled:'
SELECT count(*) AS sw2_enrolments_inside_tx FROM enrolment WHERE session_id = :sid AND swimmer_id = :sw2;
\echo 'Payment gateway says DECLINED -> the application issues ROLLBACK'
ROLLBACK;
SELECT (SELECT count(*) FROM enrolment WHERE session_id = :sid AND swimmer_id = :sw2) AS sw2_enrolments_after_rollback,
       (SELECT count(*) FROM payment p JOIN enrolment e USING (enrolment_id)
         WHERE e.session_id = :sid AND e.swimmer_id = :sw2) AS sw2_payments_after_rollback;

\echo ''
\echo 'CONCLUSION: Path A persisted both rows; Paths B1 and B2 left nothing behind.'
