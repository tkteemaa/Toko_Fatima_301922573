# Normalisation Walk-through — SplashPoint Swim School

This document walks the SplashPoint schema from a single denormalised "lesson booking" table up to **3NF**, explaining each step and why each violation forces a split.

---

## 0. The "everything in one table" starting point (UNF — unnormalised form)

Imagine the front desk keeps one Google Sheet per booking. A row might look like:

| booking_id | pool | lane | instructor | lesson_type | start | end | swimmer_name | swimmer_dob | guardian_name | guardian_phone | amount | method |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | Ikoyi | Lane 3 | Adaora Bello | Group | 2026-11-09 10:00 | 2026-11-09 10:45 | Chika Okafor | 2018-03-12 | Ngozi Okafor | 0803… | 5000 | Card |
| 2 | Ikoyi | Lane 3 | Adaora Bello | Group | 2026-11-09 10:00 | 2026-11-09 10:45 | Tunde Bello | 2017-07-22 | Kemi Bello | 0805… | 5000 | Card |
| 3 | Wuse | Lane 1 | Musa Ibrahim | Private | 2026-11-09 11:00 | 2026-11-09 11:30 | Ada Eze | 1995-01-15 |  |  | 8000 | Cash |

Problems:

- **Repeating groups.** A group session has multiple swimmers; storing one row per swimmer duplicates the entire pool/lane/instructor/lesson_type/start/end for every swimmer in the same session.
- **Multi-valued attributes.** A swimmer's parent may have two phone numbers.
- **Implicit relationships.** "Guardian" is implied to belong to "swimmer" but there is no key linking them.
- **No atomic keys.** There is no clean primary key for any entity.

---

## 1. First Normal Form (1NF)

> A relation is in 1NF if every attribute is atomic and there are no repeating groups.

Actions:

1. Split the "guardian_name | guardian_phone" pair off the booking row — guardian is a separate concept.
2. Force one phone number per row (multi-valued phone is moved to a separate `guardian_phone` table in production; for this portfolio we keep one phone per guardian to keep the schema readable).
3. Define a primary key for the booking table: `(booking_id)`.
4. Split the swimmer out of the booking — a swimmer is a separate entity with its own key (`swimmer_id`).

After 1NF we have relations:

- `booking(booking_id, pool, lane, instructor, lesson_type, start, end, swimmer_id, amount, method)`
- `swimmer(swimmer_id, swimmer_name, swimmer_dob, guardian_id)`
- `guardian(guardian_id, guardian_name, guardian_phone)`

But `pool`, `lane`, `instructor`, `lesson_type` are still *text strings* that get repeated on every booking. That sets up the 2NF problem.

---

## 2. Second Normal Form (2NF)

> A relation is in 2NF if it is in 1NF and every non-prime attribute depends on the **whole** primary key, not just a part of it.

The booking table is already single-key (`booking_id`), so 2NF is automatically satisfied once we identify that `pool`, `lane`, `instructor`, `lesson_type`, `start`, `end` describe the **session**, not the booking. We split the session out:

- `lesson_session(session_id, pool_id, lane_id, instructor_id, lesson_type_id, start_time, end_time)` — PK `session_id`
- `enrolment(enrolment_id, session_id, swimmer_id, enrol_date, status, attended)` — PK `enrolment_id`; `(session_id, swimmer_id)` candidate key
- `payment(payment_id, enrolment_id, amount, payment_date, payment_method, status)` — PK `payment_id`

Now every non-prime attribute depends on the whole primary key of its relation. We are in 2NF.

---

## 3. Third Normal Form (3NF)

> A relation is in 3NF if it is in 2NF and no non-prime attribute is transitively dependent on the primary key.

Remaining transitive dependencies to eliminate:

1. **`pool` (name, city, address, opening_time, closing_time)** depends on `pool_id`, but in `lesson_session` we still store `pool_id` directly while `lane.pool_id` also tells us the pool. We move all pool attributes into a `pool` table. `lane` references `pool` via `pool_id`. The session's `pool_id` is kept on `lesson_session` for fast reporting but it is *consistent* with `lane.pool_id` via a CHECK constraint.
2. **`lane` (lane_number, max_capacity)** depends on `lane_id`. We split `lane` out so that the lane's `max_capacity` is not repeated on every session.
3. **`instructor` (first_name, last_name, phone, email, hire_date, certification_level)** depends on `instructor_id`. Split out into `instructor`.
4. **`lesson_type` (name, description, default_duration_min, is_group, capacity)** depends on `lesson_type_id`. Split out into `lesson_type`.
5. **`guardian`** is already split out from `swimmer` in 1NF; in 3NF we ensure that `swimmer.guardian_id` is a clean FK and that guardian attributes (name, phone, email, relationship) live only on `guardian`.
6. **`payment.amount`** is denormalised-looking but is *not* a transitive dependency — the price of a session at the time of booking is historical and may differ from today's session price, so we store it explicitly on the enrolment's payment. (This is the classic "price vs list_price" pattern.)

After all splits the schema is in 3NF. The final 9 tables are:

| Relation | PK | Notable non-prime attributes | All non-prime attrs depend only on PK? |
| --- | --- | --- | --- |
| `pool` | `pool_id` | name, city, address, opening_time, closing_time | yes |
| `lane` | `lane_id` | pool_id (FK), lane_number, max_capacity | yes |
| `instructor` | `instructor_id` | first_name, last_name, phone, email, hire_date, certification_level | yes |
| `guardian` | `guardian_id` | first_name, last_name, phone, email, relationship | yes |
| `swimmer` | `swimmer_id` | first_name, last_name, dob, age_class, phone, email, guardian_id (FK) | yes |
| `lesson_type` | `lesson_type_id` | name, description, default_duration_min, is_group, capacity | yes |
| `lesson_session` | `session_id` | pool_id (FK), lane_id (FK), instructor_id (FK), lesson_type_id (FK), start_time, end_time, duration_min, price, during | yes |
| `enrolment` | `enrolment_id` | session_id (FK), swimmer_id (FK), enrol_date, status, attended | yes |
| `payment` | `payment_id` | enrolment_id (FK), amount, payment_date, payment_method, status | yes |

---

## 4. BCNF — why we stopped at 3NF

3NF is sufficient for the CA brief. The only candidate BCNF violation in the schema is `lesson_session`: the FD `pool_id, lane_number → lane_id` (a lane number is unique within a pool) is preserved trivially because `lesson_session` references `lane_id` directly, not `(pool_id, lane_number)`. So the schema is in fact BCNF on that path. The remaining FDs are all `key → everything`, which is BCNF.

---

## 5. The two constraints that *cannot* be expressed as keys

Two of the most important business rules cannot be expressed as a key, CHECK, or referential constraint:

1. **No two sessions may overlap in the same lane.** This is a *range overlap* condition, not an equality condition. PostgreSQL solves it with an **exclusion constraint** on a `tstzrange` column, indexed by GiST. The `btree_gist` extension lets us combine the scalar `lane_id` (or `instructor_id`) with the range `during` in a single GiST index.
2. **No instructor may teach two overlapping sessions.** Same mechanism, on `instructor_id` instead of `lane_id`.
3. **A group session cannot exceed its capacity.** This is a *counting* rule across rows in `enrolment`. It requires a trigger that counts existing enrolments and refuses the new one if the count would exceed `lesson_type.capacity`.
4. **A swimmer under 18 must have a guardian.** This requires inspecting `swimmer.dob` and asserting `guardian_id IS NOT NULL`. Implemented as a trigger so that the swimmer's age is computed at insert time (a CHECK cannot reference `CURRENT_DATE` reliably without a function).

These four rules together are what makes the schema "advanced" rather than "textbook 3NF".
