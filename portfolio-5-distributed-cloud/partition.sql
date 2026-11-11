-- ============================================================================
-- partition.sql — convert lesson_session into a monthly range-partitioned table
-- SplashPoint Swim School (Portfolio 5, MIT 8103)
--
-- Strategy:
--   1. Create a NEW partitioned lesson_session_part table with the same columns
--      and the same exclusion constraints as lesson_session.
--   2. Create monthly child partitions for the 2-year window the bulk generator
--      covered, plus next month and the month after (so future inserts work).
--   3. Copy the data across.
--   4. (Optionally) rename lesson_session -> lesson_session_old, lesson_session_part -> lesson_session
--      so existing queries hit the partitioned version.
--
-- We do the rename at the end so the rest of the portfolio can keep using the
-- table name "lesson_session" without changes.
-- ============================================================================

\set ON_ERROR_STOP on
\pset pager off

SET timezone = 'Africa/Lagos';   -- month boundaries in Lagos time

-- Re-run safety: if lesson_session is already partitioned, skip the conversion
SELECT (relkind = 'p') AS already_partitioned FROM pg_class
 WHERE relname = 'lesson_session' AND relnamespace = 'public'::regnamespace \gset
\if :already_partitioned
\echo 'lesson_session is already partitioned (earlier run) - skipping the conversion, showing the demo only.'
\else
BEGIN;

-- ----------------------------------------------------------------------------
-- 1. Create the partitioned parent table.
--    PostgreSQL 16 does NOT allow exclusion constraints on a partitioned
--    parent, so the two no-overlap constraints are added to EACH monthly
--    partition in step 2. A lesson never crosses midnight, so it always sits
--    inside one month and the per-partition constraint is enough.
-- ----------------------------------------------------------------------------
DROP TABLE IF EXISTS lesson_session_part CASCADE;
DROP TABLE IF EXISTS lesson_session_old CASCADE;   -- left over from an earlier run

CREATE TABLE lesson_session_part (
    session_id      SERIAL,
    pool_id         INTEGER NOT NULL REFERENCES pool(pool_id),
    lane_id         INTEGER NOT NULL REFERENCES lane(lane_id),
    instructor_id   INTEGER NOT NULL REFERENCES instructor(instructor_id),
    lesson_type_id  INTEGER NOT NULL REFERENCES lesson_type(lesson_type_id),
    start_time      TIMESTAMPTZ NOT NULL,
    end_time        TIMESTAMPTZ NOT NULL,
    duration_min    INTEGER NOT NULL CHECK (duration_min BETWEEN 30 AND 60),
    price           NUMERIC(10,2) NOT NULL CHECK (price > 0),
    during          tstzrange GENERATED ALWAYS AS (tstzrange(start_time, end_time, '[)')) STORED,
    CHECK (end_time > start_time),
    CHECK (EXTRACT(EPOCH FROM (end_time - start_time))::INTEGER BETWEEN 1800 AND 3600),
    CHECK ((start_time AT TIME ZONE 'Africa/Lagos')::time >= '06:00:00'),
    CHECK ((end_time   AT TIME ZONE 'Africa/Lagos')::time <= '20:00:00'),
    PRIMARY KEY (session_id, start_time)   -- partition key must be in PK
) PARTITION BY RANGE (start_time);


-- ----------------------------------------------------------------------------
-- 2. Create monthly child partitions for the 2-year window + 2 future months.
--    Dates are computed relative to CURRENT_DATE so the script never expires.
-- ----------------------------------------------------------------------------
DO $$
DECLARE
    d DATE := date_trunc('month', (CURRENT_DATE - INTERVAL '2 years')::DATE);
    end_d DATE := date_trunc('month', (CURRENT_DATE + INTERVAL '2 months')::DATE);
    part_name TEXT;
    part_start TIMESTAMPTZ;
    part_end   TIMESTAMPTZ;
BEGIN
    WHILE d <= end_d LOOP
        part_name := 'lesson_session_part_' || to_char(d, 'YYYY_MM');
        part_start := d::TIMESTAMPTZ;
        part_end   := (d + INTERVAL '1 month')::TIMESTAMPTZ;
        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS %I PARTITION OF lesson_session_part FOR VALUES FROM (%L) TO (%L)',
            part_name, part_start, part_end
        );
        -- the no-overlap rules from P1, per partition
        EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I EXCLUDE USING gist (lane_id WITH =, during WITH &&)',
                       part_name, part_name || '_excl_lane');
        EXECUTE format('ALTER TABLE %I ADD CONSTRAINT %I EXCLUDE USING gist (instructor_id WITH =, during WITH &&)',
                       part_name, part_name || '_excl_instr');
        d := d + INTERVAL '1 month';
    END LOOP;
END $$;

-- Safety net for dates outside the monthly range (should stay EMPTY)
CREATE TABLE lesson_session_part_default PARTITION OF lesson_session_part DEFAULT;

\echo 'Created monthly partitions. Listing them:'
SELECT count(*) AS partitions, min(c.relname) AS first, max(c.relname) FILTER (WHERE c.relname <> 'lesson_session_part_default') AS last
  FROM pg_inherits
  JOIN pg_class c ON c.oid = pg_inherits.inhrelid
 WHERE inhparent = 'lesson_session_part'::regclass;

-- ----------------------------------------------------------------------------
-- 3. Copy the data across. lesson_session has the `during` column as GENERATED
--    ALWAYS, so we must NOT insert into it.
-- ----------------------------------------------------------------------------
INSERT INTO lesson_session_part (session_id, pool_id, lane_id, instructor_id,
                                  lesson_type_id, start_time, end_time,
                                  duration_min, price)
SELECT session_id, pool_id, lane_id, instructor_id, lesson_type_id,
       start_time, end_time, duration_min, price
  FROM lesson_session;

\echo 'Rows copied to partitioned table (and rows that fell into DEFAULT — must be 0):'
SELECT (SELECT count(*) FROM lesson_session_part) AS rows_in_partitioned_table,
       (SELECT count(*) FROM lesson_session_part_default) AS rows_in_default;
\echo 'Rows per partition (last 6 months shown):'
SELECT tableoid::regclass AS partition, count(*) AS sessions
  FROM lesson_session_part GROUP BY 1 ORDER BY 1 DESC LIMIT 6;

-- ----------------------------------------------------------------------------
-- 4. Swap names: lesson_session -> lesson_session_old, lesson_session_part -> lesson_session
--    The FK from enrolment.session_id to lesson_session.session_id CANNOT be
--    re-created on a partitioned table because the partitioned table's PK is
--    (session_id, start_time) — partitioned-table unique constraints MUST
--    include the partition key. We therefore DROP the FK from enrolment and
--    rely on application logic + the trg_session_lane_pool trigger for
--    integrity. (This is a well-known PostgreSQL partitioning trade-off;
--    see https://www.postgresql.org/docs/16/ddl-partitioning.html#DDL-PARTITIONING-LIMITATIONS)
-- ----------------------------------------------------------------------------
ALTER TABLE enrolment DROP CONSTRAINT IF EXISTS enrolment_session_id_fkey;

-- Rename the originals out of the way
ALTER TABLE lesson_session RENAME TO lesson_session_old;
ALTER TABLE lesson_session_part RENAME TO lesson_session;

-- Re-attach the P1 trigger "lane must belong to the pool" to the new table
CREATE TRIGGER trg_session_lane_pool
    BEFORE INSERT OR UPDATE ON lesson_session
    FOR EACH ROW EXECUTE FUNCTION enforce_session_lane_pool();

-- Replace the lost FK enrolment.session_id -> lesson_session with a trigger
CREATE OR REPLACE FUNCTION enforce_enrolment_session() RETURNS trigger AS $f$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM lesson_session WHERE session_id = NEW.session_id) THEN
        RAISE EXCEPTION 'Session % does not exist', NEW.session_id USING ERRCODE = 'foreign_key_violation';
    END IF;
    RETURN NEW;
END $f$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS trg_enrolment_session ON enrolment;
CREATE TRIGGER trg_enrolment_session
    BEFORE INSERT OR UPDATE OF session_id ON enrolment
    FOR EACH ROW EXECUTE FUNCTION enforce_enrolment_session();

-- The FK from enrolment to the new (partitioned) lesson_session cannot
-- reference session_id alone. Application code remains responsible for
-- only enrolling into valid session_ids. (If desired, you can add a
-- NON-partitioned lookup table lesson_session_id(session_id) maintained
-- by triggers — out of scope for this portfolio.)

-- Move the sequence so new inserts continue from the max session_id
SELECT setval(pg_get_serial_sequence('lesson_session', 'session_id'),
              (SELECT COALESCE(MAX(session_id), 1) FROM lesson_session));

-- The old un-partitioned copy is no longer needed (CASCADE: its own indexes/triggers)
DROP TABLE lesson_session_old CASCADE;

COMMIT;
ANALYZE lesson_session;
\endif

-- ----------------------------------------------------------------------------
-- 5. Demonstrate partition pruning with EXPLAIN
-- ----------------------------------------------------------------------------
\echo ''
\echo '===== PARTITION PRUNING DEMO ====='
\echo 'Query: sessions in the current month'
EXPLAIN (ANALYZE, BUFFERS)
SELECT count(*) FROM lesson_session
 WHERE start_time >= date_trunc('month', now())
   AND start_time <  date_trunc('month', now() + INTERVAL '1 month');

\echo ''
\echo 'Only the current month partition appears in the plan above: the others were pruned.'
\echo ''
\echo '===== Integrity still enforced on the partitioned table ====='
\set ON_ERROR_STOP off
\echo 'Overlapping session in the same lane (expect exclusion_violation on the month partition):'
INSERT INTO lesson_session (pool_id, lane_id, instructor_id, lesson_type_id, start_time, end_time, duration_min, price)
SELECT ls.pool_id, ls.lane_id,
       (SELECT min(instructor_id) FROM instructor WHERE instructor_id <> ls.instructor_id),
       ls.lesson_type_id, ls.start_time + interval '10 minutes', ls.start_time + interval '40 minutes', 30, ls.price
  FROM lesson_session ls WHERE ls.start_time > now() ORDER BY ls.start_time LIMIT 1;
\echo 'Enrolment into a session that does not exist (expect foreign_key_violation from trg_enrolment_session):'
INSERT INTO enrolment (session_id, swimmer_id, status) VALUES (-1, 1, 'confirmed');
\set ON_ERROR_STOP on
\echo ''
\echo '===== DESCRIPTIVE OUTPUT ====='
\d lesson_session
