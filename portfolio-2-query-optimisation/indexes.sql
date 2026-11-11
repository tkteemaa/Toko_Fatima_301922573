-- ============================================================================
-- indexes.sql — indexes added AFTER the "before" run of queries.sql.
-- Run this between the BEFORE and AFTER runs.
-- ============================================================================

\set ON_ERROR_STOP on
BEGIN;

-- Q3, Q6: "sessions in the last N days" range filter on start_time
CREATE INDEX IF NOT EXISTS idx_session_start
    ON lesson_session (start_time);

-- Q1, Q3, Q4: filter lesson_session by pool_id and start_time
CREATE INDEX IF NOT EXISTS idx_session_pool_start
    ON lesson_session (pool_id, start_time);

-- Q2, Q6: filter lesson_session by instructor_id and start_time
CREATE INDEX IF NOT EXISTS idx_session_instructor_start
    ON lesson_session (instructor_id, start_time);

-- Q4: filter lesson_session by lane_id and start_time
CREATE INDEX IF NOT EXISTS idx_session_lane_start
    ON lesson_session (lane_id, start_time);

-- Q4, Q6: filter enrolment by session_id and status
CREATE INDEX IF NOT EXISTS idx_enrolment_session_status
    ON enrolment (session_id, status);

-- Q6: partial index — only no_show rows. Tiny index, fast lookups.
CREATE INDEX IF NOT EXISTS idx_enrolment_no_show
    ON enrolment (session_id)
    WHERE status = 'no_show';

-- Q3: payment status filter (only 'paid' counts toward revenue)
CREATE INDEX IF NOT EXISTS idx_payment_status_paid
    ON payment (enrolment_id)
    WHERE status = 'paid';

-- Q5: enrolment status filter for "attended"
CREATE INDEX IF NOT EXISTS idx_enrolment_attended
    ON enrolment (session_id, swimmer_id)
    WHERE status = 'attended';

-- refresh stats so the planner sees the new indexes
ANALYZE lesson_session;
ANALYZE enrolment;
ANALYZE payment;

COMMIT;
\echo 'Indexes created. Re-run queries.sql to capture the AFTER plans.'
