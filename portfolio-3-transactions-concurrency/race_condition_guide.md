# Last place in a group lesson — two-terminal guide (manual version)

`run_race_demos.py` runs all of this automatically with two real sessions and saves `race_demos_output.log`.
Use this table only if you want to repeat it by hand (e.g. during a verification call).
Run **one statement per step**, in order. No `pg_sleep` is needed.

Open two terminals: `psql -h /var/run/postgresql -d splashpoint` in each.

## Setup (Terminal A only)

```sql
SET timezone = 'Africa/Lagos';
-- a demo Group Children lesson (capacity 6) 21 days ahead, 18:00-18:45 Lagos time
INSERT INTO lesson_session (pool_id, lane_id, instructor_id, lesson_type_id, start_time, end_time, duration_min, price)
SELECT 1, (SELECT min(lane_id) FROM lane WHERE pool_id = 1), (SELECT max(instructor_id) FROM instructor),
       (SELECT lesson_type_id FROM lesson_type WHERE name = 'Group Children'),
       current_date + 21 + time '18:00', current_date + 21 + time '18:45', 45, 5000
RETURNING session_id AS sid \gset
-- 5 of 6 places taken
INSERT INTO enrolment (session_id, swimmer_id, status)
SELECT :sid, swimmer_id, 'confirmed' FROM swimmer WHERE age_class IN ('Child','Teen') ORDER BY swimmer_id LIMIT 5;
SELECT min(swimmer_id) AS s1 FROM swimmer WHERE age_class IN ('Child','Teen') AND swimmer_id NOT IN (SELECT swimmer_id FROM enrolment WHERE session_id = :sid) \gset
SELECT min(swimmer_id) AS s2 FROM swimmer WHERE age_class IN ('Child','Teen') AND swimmer_id > :s1 AND swimmer_id NOT IN (SELECT swimmer_id FROM enrolment WHERE session_id = :sid) \gset
\echo :sid :s1 :s2
```

In **Terminal B** type the three numbers printed above: `\set sid …` `\set s1 …` `\set s2 …`

## Part 1 — the bug (READ COMMITTED)

| Step | Terminal A | Terminal B |
| --- | --- | --- |
| 1 | `BEGIN;` | |
| 2 | `SELECT count(*) FROM enrolment WHERE session_id = :sid;` → 5 | |
| 3 | | `BEGIN;` |
| 4 | | `SELECT count(*) FROM enrolment WHERE session_id = :sid;` → 5 |
| 5 | `INSERT INTO enrolment (session_id, swimmer_id) VALUES (:sid, :s1);` | |
| 6 | | `INSERT INTO enrolment (session_id, swimmer_id) VALUES (:sid, :s2);` |
| 7 | `COMMIT;` | |
| 8 | | `COMMIT;` |
| 9 | `SELECT count(*) FROM enrolment WHERE session_id = :sid;` → **7** | |

Reset (A): `DELETE FROM enrolment WHERE session_id = :sid AND swimmer_id IN (:s1, :s2);`

## Part 3 — Fix 1: FOR UPDATE inside enrol_swimmer()

| Step | Terminal A | Terminal B |
| --- | --- | --- |
| 1 | `BEGIN;` | |
| 2 | `SELECT enrol_swimmer(:sid, :s1, 'Card');` | |
| 3 | | `BEGIN;` |
| 4 | | `SELECT enrol_swimmer(:sid, :s2, 'Card');` → **waits** |
| 5 | `COMMIT;` | → `ERROR: Session … is full (capacity=6, already enrolled=6)` |
| 6 | | `ROLLBACK;` |

Reset (A): `DELETE FROM enrolment WHERE session_id = :sid AND swimmer_id IN (:s1, :s2);`

## Part 4 — Fix 2: SERIALIZABLE

| Step | Terminal A | Terminal B |
| --- | --- | --- |
| 1 | `BEGIN ISOLATION LEVEL SERIALIZABLE;` | |
| 2 | `SELECT count(*) FROM enrolment WHERE session_id = :sid;` → 5 | |
| 3 | | `BEGIN ISOLATION LEVEL SERIALIZABLE;` |
| 4 | | `SELECT count(*) FROM enrolment WHERE session_id = :sid;` → 5 |
| 5 | `INSERT INTO enrolment (session_id, swimmer_id) VALUES (:sid, :s1);` | |
| 6 | | `INSERT INTO enrolment (session_id, swimmer_id) VALUES (:sid, :s2);` |
| 7 | `COMMIT;` | |
| 8 | | `COMMIT;` → `ERROR: could not serialize access …` (40001) |
| 9 | | retry steps 3–6 → the INSERT is refused: `Group session … is full` |

## Clean up (A)

```sql
DELETE FROM enrolment WHERE session_id = :sid;        -- payments cascade
DELETE FROM lesson_session WHERE session_id = :sid;
```
