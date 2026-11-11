-- ============================================================================
-- schema.sql — SplashPoint Swim School (Portfolio 1, MIT 8103)
-- 9 tables in 3NF, two exclusion constraints on tstzrange, two triggers.
-- Run AFTER: CREATE EXTENSION btree_gist;  (setup.sh does this on the splashpoint db)
-- ============================================================================

\set ON_ERROR_STOP on

BEGIN;

DROP TABLE IF EXISTS payment, enrolment, lesson_session, lesson_type,
                    swimmer, guardian, instructor, lane, pool CASCADE;
DROP FUNCTION IF EXISTS enforce_group_capacity() CASCADE;
DROP FUNCTION IF EXISTS enforce_swimmer_guardian() CASCADE;
DROP FUNCTION IF EXISTS enforce_session_lane_pool() CASCADE;

-- ----------------------------------------------------------------------------
-- 1. pool  — a swim school location (4 in total: Wuse, Maitama, Ikoyi, Lekki)
-- ----------------------------------------------------------------------------
CREATE TABLE pool (
    pool_id        SERIAL PRIMARY KEY,
    name           TEXT NOT NULL,
    city           TEXT NOT NULL CHECK (city IN ('Abuja','Lagos')),
    address        TEXT NOT NULL,
    opening_time   TIME NOT NULL CHECK (opening_time >= '06:00:00'),
    closing_time   TIME NOT NULL CHECK (closing_time <= '20:00:00'),
    CHECK (closing_time > opening_time)
);

-- ----------------------------------------------------------------------------
-- 2. lane  — a swim lane inside a pool. max_capacity = how many swimmers can
--    share the lane in one group session.
-- ----------------------------------------------------------------------------
CREATE TABLE lane (
    lane_id        SERIAL PRIMARY KEY,
    pool_id        INTEGER NOT NULL REFERENCES pool(pool_id) ON DELETE CASCADE,
    lane_number    INTEGER NOT NULL CHECK (lane_number > 0),
    max_capacity   INTEGER NOT NULL CHECK (max_capacity BETWEEN 1 AND 10),
    UNIQUE (pool_id, lane_number)
);

-- ----------------------------------------------------------------------------
-- 3. instructor — swim teachers
-- ----------------------------------------------------------------------------
CREATE TABLE instructor (
    instructor_id       SERIAL PRIMARY KEY,
    first_name          TEXT NOT NULL,
    last_name           TEXT NOT NULL,
    phone               TEXT NOT NULL,
    email               TEXT NOT NULL UNIQUE,
    hire_date           DATE NOT NULL DEFAULT CURRENT_DATE,
    certification_level TEXT NOT NULL CHECK (certification_level IN ('Level 1','Level 2','Level 3','Level 4'))
);

-- ----------------------------------------------------------------------------
-- 4. guardian — for under-18 swimmers only
-- ----------------------------------------------------------------------------
CREATE TABLE guardian (
    guardian_id   SERIAL PRIMARY KEY,
    first_name    TEXT NOT NULL,
    last_name     TEXT NOT NULL,
    phone         TEXT NOT NULL,
    email         TEXT NOT NULL,
    relationship  TEXT NOT NULL CHECK (relationship IN ('Mother','Father','Grandparent','Aunt','Uncle','Legal Guardian','Other'))
);

-- ----------------------------------------------------------------------------
-- 5. swimmer — children and adults. guardian_id is nullable but a trigger
--    forces it to be set when the swimmer is under 18.
-- ----------------------------------------------------------------------------
CREATE TABLE swimmer (
    swimmer_id    SERIAL PRIMARY KEY,
    first_name    TEXT NOT NULL,
    last_name     TEXT NOT NULL,
    dob           DATE NOT NULL,
    age_class     TEXT NOT NULL CHECK (age_class IN ('Child','Teen','Adult','Senior')),
    phone         TEXT,
    email         TEXT,
    guardian_id   INTEGER REFERENCES guardian(guardian_id)
    -- "dob not in the future" is enforced in trg_swimmer_guardian, not a CHECK:
    -- a CHECK using CURRENT_DATE is not immutable and can break dump/restore.
);

-- ----------------------------------------------------------------------------
-- 6. lesson_type — private, group, adult beginner, etc.
-- ----------------------------------------------------------------------------
CREATE TABLE lesson_type (
    lesson_type_id        SERIAL PRIMARY KEY,
    name                  TEXT NOT NULL UNIQUE,
    description           TEXT,
    default_duration_min  INTEGER NOT NULL CHECK (default_duration_min BETWEEN 30 AND 60),
    is_group              BOOLEAN NOT NULL DEFAULT FALSE,
    capacity              INTEGER NOT NULL DEFAULT 1 CHECK (capacity BETWEEN 1 AND 6)
);

-- ----------------------------------------------------------------------------
-- 7. lesson_session — pool + lane + instructor + lesson_type + time window
--    `during` is a tstzrange used by the two exclusion constraints.
--    start_time / end_time / duration_min are stored as plain columns for
--    easy reporting; `during` is generated from them.
-- ----------------------------------------------------------------------------
CREATE TABLE lesson_session (
    session_id      SERIAL PRIMARY KEY,
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
    -- sessions only between 06:00 and 20:00 local pool time
    -- Opening hours are checked in Lagos local time (WAT). A plain ::time cast
    -- would use the session TimeZone (UTC in Codespaces) and shift by 1 hour.
    CHECK ((start_time AT TIME ZONE 'Africa/Lagos')::time >= '06:00:00'),
    CHECK ((end_time   AT TIME ZONE 'Africa/Lagos')::time <= '20:00:00')
    -- Note: a CHECK constraint cannot reference other tables, so the rule
    -- "lane must belong to the chosen pool" is enforced by a trigger below.
);

-- No two sessions in the same lane may overlap in time
ALTER TABLE lesson_session
    ADD CONSTRAINT excl_lane_overlap
    EXCLUDE USING gist (lane_id WITH =, during WITH &&);

-- No instructor may teach two overlapping sessions
ALTER TABLE lesson_session
    ADD CONSTRAINT excl_instructor_overlap
    EXCLUDE USING gist (instructor_id WITH =, during WITH &&);

-- ----------------------------------------------------------------------------
-- 8. enrolment — a swimmer booked into a session
-- ----------------------------------------------------------------------------
CREATE TABLE enrolment (
    enrolment_id  SERIAL PRIMARY KEY,
    session_id    INTEGER NOT NULL REFERENCES lesson_session(session_id) ON DELETE CASCADE,
    swimmer_id    INTEGER NOT NULL REFERENCES swimmer(swimmer_id),
    enrol_date    TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    status        TEXT NOT NULL DEFAULT 'confirmed' CHECK (status IN ('confirmed','cancelled','attended','no_show')),
    attended      BOOLEAN,
    UNIQUE (session_id, swimmer_id)  -- a swimmer cannot be enrolled twice in the same session
);

-- ----------------------------------------------------------------------------
-- 9. payment — one per enrolment (per-lesson model). amount > 0
-- ----------------------------------------------------------------------------
CREATE TABLE payment (
    payment_id       SERIAL PRIMARY KEY,
    enrolment_id     INTEGER NOT NULL UNIQUE REFERENCES enrolment(enrolment_id) ON DELETE CASCADE,
    amount           NUMERIC(10,2) NOT NULL CHECK (amount > 0),
    payment_date     TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    payment_method   TEXT NOT NULL CHECK (payment_method IN ('Card','Bank Transfer','Cash','USSD','POS')),
    status           TEXT NOT NULL DEFAULT 'paid' CHECK (status IN ('paid','refunded','failed'))
);

-- ============================================================================
-- TRIGGERS
-- ============================================================================

-- (a) Group sessions cannot exceed capacity
CREATE OR REPLACE FUNCTION enforce_group_capacity()
RETURNS TRIGGER AS $$
DECLARE
    current_count INTEGER;
    cap           INTEGER;
    is_grp        BOOLEAN;
BEGIN
    SELECT lt.capacity, lt.is_group
      INTO cap, is_grp
      FROM lesson_session ls
      JOIN lesson_type lt ON lt.lesson_type_id = ls.lesson_type_id
     WHERE ls.session_id = NEW.session_id;

    -- Only active enrolments use a place; a cancelled/no-show row never blocks.
    IF NEW.status NOT IN ('confirmed','attended') THEN
        RETURN NEW;
    END IF;

    IF is_grp THEN
        SELECT count(*) INTO current_count FROM enrolment
         WHERE session_id = NEW.session_id
           AND status IN ('confirmed','attended')
           AND enrolment_id IS DISTINCT FROM NEW.enrolment_id;  -- don't count this row on UPDATE
        IF current_count + 1 > cap THEN
            RAISE EXCEPTION 'Group session % is full (capacity=%, already enrolled=%)',
                NEW.session_id, cap, current_count
                USING ERRCODE = 'check_violation';
        END IF;
    ELSE  -- private lesson — capacity is always 1
        IF cap = 1 THEN
            SELECT count(*) INTO current_count FROM enrolment
             WHERE session_id = NEW.session_id
               AND status IN ('confirmed','attended')
               AND enrolment_id IS DISTINCT FROM NEW.enrolment_id;
            IF current_count + 1 > 1 THEN
                RAISE EXCEPTION 'Private session % already has a swimmer', NEW.session_id
                    USING ERRCODE = 'check_violation';
            END IF;
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_group_capacity
    BEFORE INSERT OR UPDATE ON enrolment
    FOR EACH ROW EXECUTE FUNCTION enforce_group_capacity();

-- (b) A swimmer under 18 must have a guardian
CREATE OR REPLACE FUNCTION enforce_swimmer_guardian()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.dob > CURRENT_DATE THEN
        RAISE EXCEPTION 'Swimmer % has a date of birth in the future (%)',
            NEW.first_name, NEW.dob
            USING ERRCODE = 'check_violation';
    END IF;
    IF date_part('year', age(NEW.dob)) < 18 AND NEW.guardian_id IS NULL THEN
        RAISE EXCEPTION 'Swimmer % is under 18 (dob=%) but has no guardian_id',
            NEW.first_name, NEW.dob
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_swimmer_guardian
    BEFORE INSERT OR UPDATE ON swimmer
    FOR EACH ROW EXECUTE FUNCTION enforce_swimmer_guardian();

-- (c) A lesson_session's lane must belong to the chosen pool
--     (cannot be a CHECK because it crosses tables)
CREATE OR REPLACE FUNCTION enforce_session_lane_pool()
RETURNS TRIGGER AS $$
DECLARE
    lane_pool INTEGER;
BEGIN
    SELECT pool_id INTO lane_pool FROM lane WHERE lane_id = NEW.lane_id;
    IF lane_pool IS NULL THEN
        RAISE EXCEPTION 'Lane % does not exist', NEW.lane_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;
    IF lane_pool <> NEW.pool_id THEN
        RAISE EXCEPTION 'Lane % belongs to pool %, not pool %',
            NEW.lane_id, lane_pool, NEW.pool_id
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_session_lane_pool
    BEFORE INSERT OR UPDATE ON lesson_session
    FOR EACH ROW EXECUTE FUNCTION enforce_session_lane_pool();

COMMIT;
