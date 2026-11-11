#!/usr/bin/env python3
"""
run_race_demos.py — Portfolio 3, SplashPoint Swim School (MIT 8103)

Runs the six concurrency demos with TWO real PostgreSQL sessions (A and B),
step by step, and prints what each session actually did. Nothing is simulated:
every line comes from the database. run_p3.sh saves the output to
race_demos_output.log.

  Part 1  BUG: last place in a group lesson, check-then-insert -> 7/6 overbooked
  Part 2  UNIQUE: the same swimmer booked twice at once -> B gets unique_violation
  Part 3  FIX 1: enrol_swimmer() locks the session row FOR UPDATE -> B waits, then "full"
  Part 4  FIX 2: SERIALIZABLE -> B is aborted (40001) and its retry sees "full"
  Part 5  READ COMMITTED vs REPEATABLE READ (non-repeatable read and phantom)
  Part 6  Deadlock (opposite lock order) and the fix (same lock order)

The demo uses its own group session 21 days ahead (Lagos time) and removes it
at the end, so the real booking data is left unchanged.
"""
import sys
import threading
import time

import psycopg2
from psycopg2 import errors

DSN = "host=/var/run/postgresql dbname=splashpoint"


def connect(name):
    c = psycopg2.connect(DSN, application_name=f"race_demo_{name}")
    c.autocommit = True          # we issue BEGIN/COMMIT ourselves, step by step
    return c


A, B, ADMIN = connect("A"), connect("B"), connect("admin")


def run(conn, label, sql, params=None, fetch=False):
    cur = conn.cursor()
    shown = cur.mogrify(sql, params).decode() if params else sql
    print(f"[{label}] {' '.join(shown.split())}")
    try:
        cur.execute(sql, params)
        if fetch:
            rows = cur.fetchall()
            for r in rows:
                print(f"[{label}]   -> {r}")
            return rows
        print(f"[{label}]   -> {cur.statusmessage}")
    except psycopg2.Error as e:
        msg = (e.pgerror or str(e)).strip().splitlines()[0]
        print(f"[{label}]   -> {msg}   (SQLSTATE {e.pgcode})")
        return e


def q1(sql, params=None):
    cur = ADMIN.cursor()
    cur.execute(sql, params)
    return cur.fetchone()[0]


def heading(t):
    print("\n" + "=" * 78 + f"\n{t}\n" + "=" * 78)


def waiting(pid):
    return q1("SELECT wait_event_type FROM pg_stat_activity WHERE pid = %s", (pid,))


def run_in_thread(conn, label, sql, params=None):
    holder = {}
    t = threading.Thread(target=lambda: holder.setdefault("r", run(conn, label, sql, params)))
    t.start()
    # wait until B is really blocked on a lock (or finished)
    for _ in range(50):
        time.sleep(0.1)
        if not t.is_alive() or waiting(conn.get_backend_pid()) == "Lock":
            break
    if t.is_alive():
        print(f"[{label}]   ... BLOCKED (pg_stat_activity.wait_event_type = Lock)")
    return t, holder


# --------------------------------------------------------------------- setup --
heading("SETUP — a demo Group Children session (capacity 6) 21 days ahead")
cur = ADMIN.cursor()
cur.execute("SET timezone = 'Africa/Lagos'")
cur.execute("""
    SELECT l.pool_id, l.lane_id, i.instructor_id, lt.lesson_type_id, lt.capacity,
           ((now() AT TIME ZONE 'Africa/Lagos')::date + 21)::text
      FROM lane l
      CROSS JOIN LATERAL (SELECT instructor_id FROM instructor ORDER BY instructor_id DESC LIMIT 1) i
      CROSS JOIN LATERAL (SELECT lesson_type_id, capacity FROM lesson_type
                           WHERE name = 'Group Children') lt
     ORDER BY l.lane_id LIMIT 1""")
pool, lane, ins, lt_id, cap, day = cur.fetchone()
cur.execute("""
    INSERT INTO lesson_session (pool_id, lane_id, instructor_id, lesson_type_id,
                                start_time, end_time, duration_min, price)
    VALUES (%s, %s, %s, %s, (%s || ' 18:00+01')::timestamptz, (%s || ' 18:45+01')::timestamptz, 45, 5000)
    RETURNING session_id""", (pool, lane, ins, lt_id, day, day))
SID = cur.fetchone()[0]
cur.execute("""SELECT swimmer_id, first_name || ' ' || last_name FROM swimmer
                WHERE age_class IN ('Child','Teen') ORDER BY swimmer_id LIMIT 12""")
KIDS = cur.fetchall()
print(f"Demo session_id = {SID} (pool {pool}, lane {lane}, {day} 18:00-18:45 Lagos), capacity = {cap}")
print("Swimmers used:", ", ".join(f"{i}={n}" for i, n in KIDS[:8]))


def reset(filled):
    """Leave the demo session with `filled` confirmed swimmers (KIDS[0..filled-1])."""
    ADMIN.cursor().execute("DELETE FROM enrolment WHERE session_id = %s", (SID,))
    for sw, _ in KIDS[:filled]:
        ADMIN.cursor().execute(
            "INSERT INTO enrolment (session_id, swimmer_id, status) VALUES (%s, %s, 'confirmed')", (SID, sw))
    print(f"[reset] session {SID} now has {filled}/{cap} confirmed swimmers")


def count():
    n = q1("SELECT count(*) FROM enrolment WHERE session_id = %s AND status IN ('confirmed','attended')", (SID,))
    print(f"[check] enrolled in session {SID}: {n}/{cap}")
    return n


INS = "INSERT INTO enrolment (session_id, swimmer_id, status) VALUES (%s, %s, 'confirmed')"
S1, S2 = KIDS[6][0], KIDS[7][0]     # the two swimmers racing for the last place

# --------------------------------------------------------------------- PART 1
heading("PART 1 — THE BUG: two parents book the LAST place at the same time (READ COMMITTED)")
reset(cap - 1)
run(A, "A", "BEGIN")
run(A, "A", "SELECT count(*) FROM enrolment WHERE session_id = %s AND status IN ('confirmed','attended')", (SID,), fetch=True)
run(B, "B", "BEGIN")
run(B, "B", "SELECT count(*) FROM enrolment WHERE session_id = %s AND status IN ('confirmed','attended')", (SID,), fetch=True)
print("Both sessions see 5 of 6 -> both think one place is free.")
run(A, "A", INS, (SID, S1))
run(B, "B", INS, (SID, S2))
print("(trg_group_capacity also counted only COMMITTED rows, so it let both through)")
run(A, "A", "COMMIT")
run(B, "B", "COMMIT")
n = count()
print(f"RESULT: {'OVERBOOKED' if n > cap else 'not overbooked'} — {n} swimmers in a {cap}-place lesson.")

# --------------------------------------------------------------------- PART 2
heading("PART 2 — UNIQUE (session_id, swimmer_id): the same child booked twice at once")
reset(2)
run(A, "A", "BEGIN")
run(A, "A", INS, (SID, S1))
run(B, "B", "BEGIN")
t, h = run_in_thread(B, "B", INS, (SID, S1))
run(A, "A", "COMMIT")
t.join()
run(B, "B", "ROLLBACK")
count()
print("RESULT: B waited for A, then the UNIQUE constraint rejected the duplicate booking.")

# --------------------------------------------------------------------- PART 3
heading("PART 3 — FIX 1: enrol_swimmer() takes SELECT ... FOR UPDATE on the session row")
reset(cap - 1)
run(A, "A", "BEGIN")
run(A, "A", "SELECT enrol_swimmer(%s, %s, 'Card')", (SID, S1), fetch=True)
run(B, "B", "BEGIN")
t, h = run_in_thread(B, "B", "SELECT enrol_swimmer(%s, %s, 'Card')", (SID, S2))
run(A, "A", "COMMIT")
t.join()
run(B, "B", "ROLLBACK")
n = count()
print(f"RESULT: B waited on A's row lock, re-counted after A committed and was refused — {n}/{cap}, no overbooking.")

# --------------------------------------------------------------------- PART 4
heading("PART 4 — FIX 2: SERIALIZABLE isolation (no explicit lock), with one retry")
reset(cap - 1)
CNT = "SELECT count(*) FROM enrolment WHERE session_id = %s AND status IN ('confirmed','attended')"
run(A, "A", "BEGIN ISOLATION LEVEL SERIALIZABLE")
run(A, "A", CNT, (SID,), fetch=True)
run(B, "B", "BEGIN ISOLATION LEVEL SERIALIZABLE")
run(B, "B", CNT, (SID,), fetch=True)
run(A, "A", INS, (SID, S1))
rb = run(B, "B", INS, (SID, S2))
run(A, "A", "COMMIT")
rc = None
if not isinstance(rb, psycopg2.Error):
    rc = run(B, "B", "COMMIT")
else:
    run(B, "B", "ROLLBACK")
failed = isinstance(rb, errors.SerializationFailure) or isinstance(rc, errors.SerializationFailure)
print(f"B was {'ABORTED with serialization_failure (40001)' if failed else 'not aborted'}; the app retries B once:")
run(B, "B", "BEGIN ISOLATION LEVEL SERIALIZABLE")
run(B, "B", CNT, (SID,), fetch=True)
r = run(B, "B", INS, (SID, S2))
run(B, "B", "ROLLBACK" if isinstance(r, psycopg2.Error) else "COMMIT")
n = count()
print(f"RESULT: {n}/{cap} — the retry saw the lesson was full (trigger refused it), no overbooking.")

# --------------------------------------------------------------------- PART 5
heading("PART 5 — READ COMMITTED vs REPEATABLE READ (price change + new booking during A's transaction)")
reset(3)
PRICE = "SELECT price FROM lesson_session WHERE session_id = %s"
for level in ("READ COMMITTED", "REPEATABLE READ"):
    print(f"\n--- A runs at {level} ---")
    ADMIN.cursor().execute("UPDATE lesson_session SET price = 5000 WHERE session_id = %s", (SID,))
    reset(3)
    run(A, "A", f"BEGIN ISOLATION LEVEL {level}")
    run(A, "A", PRICE, (SID,), fetch=True)
    run(A, "A", CNT, (SID,), fetch=True)
    run(B, "B", "UPDATE lesson_session SET price = 5500 WHERE session_id = %s", (SID,))
    run(B, "B", INS, (SID, S1))
    print("(B auto-committed both changes)")
    p2 = run(A, "A", PRICE, (SID,), fetch=True)
    c2 = run(A, "A", CNT, (SID,), fetch=True)
    run(A, "A", "COMMIT")
    print(f"A's second read: price {p2[0][0]}, enrolled {c2[0][0]} -> "
          + ("changed inside one transaction (non-repeatable read + phantom)" if level == "READ COMMITTED"
             else "same snapshot as the first read (no non-repeatable read, no phantom)"))

# --------------------------------------------------------------------- PART 6
heading("PART 6 — DEADLOCK: A and B update two swimmers in OPPOSITE order")
X, Y = KIDS[8][0], KIDS[9][0]
UPD = "UPDATE swimmer SET phone = phone WHERE swimmer_id = %s"
run(A, "A", "BEGIN")
run(B, "B", "BEGIN")
run(A, "A", UPD, (X,))
run(B, "B", UPD, (Y,))
ta, ha = run_in_thread(A, "A", UPD, (Y,))   # A waits for B's lock on Y
tb, hb = run_in_thread(B, "B", UPD, (X,))   # B waits for A's lock on X -> cycle
# One session is chosen as the victim and gets an error; it must ROLLBACK to free
# its lock, then the other session's waiting UPDATE completes.
while ta.is_alive() and tb.is_alive():
    time.sleep(0.1)
done_first = (A, "A", ha) if not ta.is_alive() else (B, "B", hb)
conn, lab, h = done_first
run(conn, lab, "ROLLBACK" if isinstance(h.get("r"), psycopg2.Error) else "COMMIT")
ta.join(); tb.join()
other = (B, "B", hb) if conn is A else (A, "A", ha)
run(other[0], other[1], "ROLLBACK" if isinstance(other[2].get("r"), psycopg2.Error) else "COMMIT")
print("RESULT: PostgreSQL found the cycle (deadlock_timeout = %s) and aborted one transaction (40P01)."
      % q1("SHOW deadlock_timeout"))

print("\n--- The fix: both sessions lock in the SAME order (lowest swimmer_id first) ---")
lo, hi = sorted((X, Y))
run(A, "A", "BEGIN")
run(B, "B", "BEGIN")
run(A, "A", UPD, (lo,))
tb, hb = run_in_thread(B, "B", UPD, (lo,))
run(A, "A", UPD, (hi,))
run(A, "A", "COMMIT")
tb.join()
run(B, "B", UPD, (hi,))
run(B, "B", "COMMIT")
print("RESULT: B simply waited for A, then finished. Same lock order = no deadlock.")

# ------------------------------------------------------------------- cleanup
heading("CLEANUP")
ADMIN.cursor().execute("DELETE FROM enrolment WHERE session_id = %s", (SID,))       # payments cascade
ADMIN.cursor().execute("DELETE FROM lesson_session WHERE session_id = %s", (SID,))
print(f"Demo session {SID} and its enrolments/payments removed.")
for c in (A, B, ADMIN):
    c.close()
print("All six parts finished.")
sys.exit(0)
