# Portfolio 3 — Transactions and Concurrency

**Student:** Fatima Toko Ali · 2026/A/MIT/0873
**Case study:** SplashPoint Swim School (simulated).
**Study sessions covered:** ACID & transactions, isolation levels, locking & MVCC, concurrency problems, serialisability & snapshot isolation.

## What this portfolio demonstrates

1. **`enrol_swimmer(p_session_id, p_swimmer_id, p_method)`** — one PL/pgSQL function that locks the session row
   (`SELECT ... FOR UPDATE`), checks the swimmer is not already booked, re-counts places, inserts the enrolment and
   records the payment. Any failure raises an error, so the enrolment and payment succeed or fail **together**.
2. **COMMIT vs ROLLBACK** (`commit_rollback_demo.sql`): Path A commits both rows; Path B1 fails *inside* the function
   (invalid payment method breaks a CHECK) and leaves nothing; Path B2 is an explicit ROLLBACK after a declined card.
3. **The last-place race condition** (`run_race_demos.py`, two real database sessions, saved to `race_demos_output.log`):
   - **Part 1 — the bug:** two parents book the last place in a 6-place Group Children lesson at the same time under
     READ COMMITTED; both succeed and the lesson ends **7/6**. The P1 trigger `trg_group_capacity` does *not* stop this,
     because each transaction counts only committed rows (check-then-act).
   - **Part 2 — UNIQUE:** the same child booked twice at once; B waits for A, then gets `unique_violation`.
   - **Part 3 — Fix 1, FOR UPDATE:** `enrol_swimmer()` locks the session row; B waits, re-counts after A commits, and is refused.
   - **Part 4 — Fix 2, SERIALIZABLE:** no explicit lock; PostgreSQL SSI aborts B with `40001`; B retries once and sees "full".
   - **Part 5 — READ COMMITTED vs REPEATABLE READ:** a price change and a new booking appear mid-transaction under
     READ COMMITTED, but not under REPEATABLE READ.
   - **Part 6 — deadlock:** opposite lock order → `40P01 deadlock detected`; same lock order → B just waits.
4. **Isolation levels** (`isolation_levels.sql`) and **deadlock** (`deadlock_demo.sql`) as plain psql scripts with a second
   psql session, as a cross-check of Parts 5 and 6.

## Files

| File | Purpose |
| --- | --- |
| `enrol_swimmer.sql` | The transactional booking function (FOR UPDATE + capacity re-check + payment). |
| `commit_rollback_demo.sql` | Success (COMMIT) and two failure (ROLLBACK) paths, using `\gset` variables. |
| `run_race_demos.py` | The six concurrency demos with two psycopg sessions; prints every statement and its real result. |
| `race_condition_guide.md` | The same race as a two-terminal step table, if you want to do it by hand for the defence. |
| `isolation_levels.sql` | Non-repeatable read, phantom read and an SSI abort with a second psql session. |
| `deadlock_demo.sql` | AB-BA deadlock with two psql sessions launched together. |
| `run_p3.sh` | Runs everything above in order (`set -euo pipefail`). |

## Run it (Codespaces)

```bash
bash portfolio-3-transactions-concurrency/run_p3.sh 2>&1 | tee p3_output.log
```

## What to screenshot

1. `race_demos_output.log` Part 1 (7/6 overbooked), Part 3 (B BLOCKED, then "Session … is full"), Part 4 (40001, then retry refused).
2. Path B1/B2 of the commit/rollback demo (counts back to 0).
3. Part 5 (the second read differs under READ COMMITTED but not REPEATABLE READ).
4. Part 6 or the deadlock demo (`ERROR: deadlock detected`).

## Plain-English explanation

A transaction is all-or-nothing (atomicity): a swimmer is never enrolled without a payment. Concurrency is harder:
two bookings that each *check* the count before *inserting* can both see "5 of 6" and both insert. A trigger that
counts rows has the same blind spot, because it cannot see the other transaction's uncommitted row. Two fixes are shown:
**pessimistic locking** (`FOR UPDATE` on the session row serialises bookings for that lesson only) and **SERIALIZABLE**
(PostgreSQL detects the dangerous read/write pattern and aborts one transaction, which the app retries). FOR UPDATE
makes the second user wait a few milliseconds; SERIALIZABLE needs retry code but no explicit locks.

| Level | Dirty read | Non-repeatable read | Phantom | Write skew |
| --- | --- | --- | --- | --- |
| READ COMMITTED (PG default) | no | possible | possible | possible |
| REPEATABLE READ (PG) | no | no | no (PG snapshot) | possible |
| SERIALIZABLE (PG SSI) | no | no | no | no (aborts one, retry) |

Deadlocks come from inconsistent lock order; PostgreSQL detects the cycle after `deadlock_timeout` (1 s) and aborts one
transaction. The fix is to always lock rows in the same order (e.g. ascending id).
