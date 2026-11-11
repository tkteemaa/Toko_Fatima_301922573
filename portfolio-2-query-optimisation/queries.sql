-- ============================================================================
-- queries.sql — 6 analytical queries for SplashPoint (Portfolio 2, MIT 8103)
-- Each query: a header, the SQL itself (real answer), then EXPLAIN ANALYZE.
-- run_p2.sh runs this file TWICE: once BEFORE indexes.sql, once AFTER.
--
-- Dates are relative to "now" in Lagos time, so the file never goes stale.
-- Q1, Q2, Q3 and Q6 are SELECTIVE (one pool / one instructor / a recent date
-- range), which is where an index can help. Q4 and Q5 read the whole history
-- on purpose: they show that an index does NOT help a full-table aggregate.
-- ============================================================================

\pset pager off
\timing on
SET timezone = 'Africa/Lagos';

-- ============================================================================
-- Q1. Free lanes at Ikoyi tomorrow between 10:00 and 10:45 (booking screen).
--     NOT EXISTS against sessions whose `during` range overlaps the window.
-- ============================================================================
\echo '===== Q1: Free lanes at SplashPoint Ikoyi tomorrow 10:00-10:45 ====='
SELECT l.lane_id, l.lane_number, l.max_capacity
  FROM lane l
  JOIN pool p ON p.pool_id = l.pool_id AND p.name = 'SplashPoint Ikoyi'
 WHERE NOT EXISTS (
        SELECT 1 FROM lesson_session ls
         WHERE ls.lane_id = l.lane_id
           AND ls.during && tstzrange(current_date + 1 + time '10:00', current_date + 1 + time '10:45', '[)'))
 ORDER BY l.lane_number;

\echo '--- Q1 EXPLAIN ANALYZE ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT l.lane_id, l.lane_number, l.max_capacity
  FROM lane l
  JOIN pool p ON p.pool_id = l.pool_id AND p.name = 'SplashPoint Ikoyi'
 WHERE NOT EXISTS (
        SELECT 1 FROM lesson_session ls
         WHERE ls.lane_id = l.lane_id
           AND ls.during && tstzrange(current_date + 1 + time '10:00', current_date + 1 + time '10:45', '[)'))
 ORDER BY l.lane_number;

-- ============================================================================
-- Q2. One instructor's lessons per month over the last 12 months (workload).
-- ============================================================================
\echo '===== Q2: Lessons per month for instructor 7, last 12 months ====='
SELECT i.instructor_id,
       i.first_name || ' ' || i.last_name AS instructor,
       to_char(date_trunc('month', ls.start_time), 'YYYY-MM') AS month,
       count(*) AS lessons_taught,
       sum(ls.duration_min) AS minutes_taught
  FROM instructor i
  JOIN lesson_session ls ON ls.instructor_id = i.instructor_id
 WHERE i.instructor_id = 7
   AND ls.start_time >= now() - interval '12 months'
   AND ls.start_time <  now()
 GROUP BY i.instructor_id, i.first_name, i.last_name, date_trunc('month', ls.start_time)
 ORDER BY month;

\echo '--- Q2 EXPLAIN ANALYZE ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT i.instructor_id,
       i.first_name || ' ' || i.last_name AS instructor,
       to_char(date_trunc('month', ls.start_time), 'YYYY-MM') AS month,
       count(*) AS lessons_taught,
       sum(ls.duration_min) AS minutes_taught
  FROM instructor i
  JOIN lesson_session ls ON ls.instructor_id = i.instructor_id
 WHERE i.instructor_id = 7
   AND ls.start_time >= now() - interval '12 months'
   AND ls.start_time <  now()
 GROUP BY i.instructor_id, i.first_name, i.last_name, date_trunc('month', ls.start_time)
 ORDER BY month;

-- ============================================================================
-- Q3. Revenue per pool for the last 30 days (paid payments only, in Naira).
-- ============================================================================
\echo '===== Q3: Revenue per pool, last 30 days ====='
SELECT p.pool_id,
       p.name AS pool,
       to_char(sum(pay.amount), 'FM999,999,990.00') AS revenue_ngn,
       count(*) AS payments
  FROM pool p
  JOIN lesson_session ls ON ls.pool_id = p.pool_id
  JOIN enrolment e       ON e.session_id = ls.session_id
  JOIN payment pay       ON pay.enrolment_id = e.enrolment_id
 WHERE pay.status = 'paid'
   AND ls.start_time >= now() - interval '30 days'
   AND ls.start_time <  now()
 GROUP BY p.pool_id, p.name
 ORDER BY sum(pay.amount) DESC;      -- order by the number, not the formatted text

\echo '--- Q3 EXPLAIN ANALYZE ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT p.pool_id,
       p.name AS pool,
       sum(pay.amount) AS revenue_ngn,
       count(*) AS payments
  FROM pool p
  JOIN lesson_session ls ON ls.pool_id = p.pool_id
  JOIN enrolment e       ON e.session_id = ls.session_id
  JOIN payment pay       ON pay.enrolment_id = e.enrolment_id
 WHERE pay.status = 'paid'
   AND ls.start_time >= now() - interval '30 days'
   AND ls.start_time <  now()
 GROUP BY p.pool_id, p.name
 ORDER BY sum(pay.amount) DESC;

-- ============================================================================
-- Q4. Lane utilisation % over the past 730 days: booked minutes divided by
--     open minutes (14 h/day x 730 days). Reads ALL history -> full scan.
-- ============================================================================
\echo '===== Q4: Lane utilisation %, last 730 days ====='
SELECT l.lane_id,
       p.name AS pool,
       l.lane_number,
       count(ls.session_id) AS sessions_booked,
       sum(ls.duration_min) AS minutes_booked,
       round(100.0 * coalesce(sum(ls.duration_min), 0) / (14 * 60 * 730), 2) AS utilisation_pct
  FROM lane l
  JOIN pool p ON p.pool_id = l.pool_id
  LEFT JOIN lesson_session ls
         ON ls.lane_id = l.lane_id
        AND ls.start_time >= now() - interval '730 days'
        AND ls.start_time <  now()
 GROUP BY l.lane_id, p.name, l.lane_number
 ORDER BY utilisation_pct DESC;

\echo '--- Q4 EXPLAIN ANALYZE ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT l.lane_id,
       p.name AS pool,
       l.lane_number,
       count(ls.session_id) AS sessions_booked,
       sum(ls.duration_min) AS minutes_booked,
       round(100.0 * coalesce(sum(ls.duration_min), 0) / (14 * 60 * 730), 2) AS utilisation_pct
  FROM lane l
  JOIN pool p ON p.pool_id = l.pool_id
  LEFT JOIN lesson_session ls
         ON ls.lane_id = l.lane_id
        AND ls.start_time >= now() - interval '730 days'
        AND ls.start_time <  now()
 GROUP BY l.lane_id, p.name, l.lane_number
 ORDER BY utilisation_pct DESC;

-- ============================================================================
-- Q5. Distinct swimmers who ATTENDED each lesson type (all history).
--     ~83% of enrolments are 'attended', so this is NOT selective -> full scan.
-- ============================================================================
\echo '===== Q5: Distinct swimmers who attended each lesson type ====='
SELECT lt.name AS lesson_type,
       count(DISTINCT e.swimmer_id) AS distinct_swimmers
  FROM enrolment e
  JOIN lesson_session ls ON ls.session_id = e.session_id
  JOIN lesson_type lt ON lt.lesson_type_id = ls.lesson_type_id
 WHERE e.status = 'attended'
 GROUP BY lt.name
 ORDER BY distinct_swimmers DESC;

\echo '--- Q5 EXPLAIN ANALYZE ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT lt.name AS lesson_type,
       count(DISTINCT e.swimmer_id) AS distinct_swimmers
  FROM enrolment e
  JOIN lesson_session ls ON ls.session_id = e.session_id
  JOIN lesson_type lt ON lt.lesson_type_id = ls.lesson_type_id
 WHERE e.status = 'attended'
 GROUP BY lt.name
 ORDER BY distinct_swimmers DESC;

-- ============================================================================
-- Q6. Attendance / no-show rate per instructor for the last 90 days.
-- ============================================================================
\echo '===== Q6: Attendance / no-show rate per instructor, last 90 days ====='
SELECT i.instructor_id,
       i.first_name || ' ' || i.last_name AS instructor,
       count(e.enrolment_id) AS total_enrolments,
       count(*) FILTER (WHERE e.status = 'attended')  AS attended,
       count(*) FILTER (WHERE e.status = 'no_show')   AS no_show,
       count(*) FILTER (WHERE e.status = 'cancelled') AS cancelled,
       round(100.0 * count(*) FILTER (WHERE e.status = 'no_show') / nullif(count(*), 0), 2) AS no_show_pct
  FROM instructor i
  JOIN lesson_session ls ON ls.instructor_id = i.instructor_id
  JOIN enrolment e       ON e.session_id = ls.session_id
 WHERE ls.start_time >= now() - interval '90 days'
   AND ls.start_time <  now()
 GROUP BY i.instructor_id, i.first_name, i.last_name
 ORDER BY no_show_pct DESC NULLS LAST;

\echo '--- Q6 EXPLAIN ANALYZE ---'
EXPLAIN (ANALYZE, BUFFERS)
SELECT i.instructor_id,
       i.first_name || ' ' || i.last_name AS instructor,
       count(e.enrolment_id) AS total_enrolments,
       count(*) FILTER (WHERE e.status = 'attended')  AS attended,
       count(*) FILTER (WHERE e.status = 'no_show')   AS no_show,
       count(*) FILTER (WHERE e.status = 'cancelled') AS cancelled,
       round(100.0 * count(*) FILTER (WHERE e.status = 'no_show') / nullif(count(*), 0), 2) AS no_show_pct
  FROM instructor i
  JOIN lesson_session ls ON ls.instructor_id = i.instructor_id
  JOIN enrolment e       ON e.session_id = ls.session_id
 WHERE ls.start_time >= now() - interval '90 days'
   AND ls.start_time <  now()
 GROUP BY i.instructor_id, i.first_name, i.last_name
 ORDER BY no_show_pct DESC NULLS LAST;
