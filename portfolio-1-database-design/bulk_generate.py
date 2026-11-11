#!/usr/bin/env python3
r"""
bulk_generate.py — SplashPoint Swim School (Portfolio 1, MIT 8103)

Emits 50,000+ enrolments (and matching payments) spread over the last 2 years
relative to today, with:
  - no two sessions overlapping in the same lane
  - no instructor teaching two overlapping sessions
  - no group session over capacity
  - realistic Nigerian names (Yoruba, Igbo, Hausa, mixed)
  - prices in Naira (₦) for the five lesson types
  - dates relative to today (NOT fixed dates that expire)

Output: a ./bulk_data/ directory with CSV files:
  pools.csv, lanes.csv, instructors.csv, guardians.csv, swimmers.csv,
  lesson_types.csv, lesson_sessions.csv, enrolments.csv, payments.csv

These are loaded by bulk_load.sql using \copy.

Usage:
  python3 bulk_generate.py
  python3 bulk_generate.py --enrolments 80000   # bigger
"""

import csv
import os
import random
import sys
from datetime import datetime, timedelta, time, date

random.seed(20260207)  # reproducible

# ----------------------------------------------------------------------------
# 0. CLI args
# ----------------------------------------------------------------------------
TARGET_ENROLMENTS = 60000  # default > 50k; tune via --enrolments
for i, a in enumerate(sys.argv[1:]):
    if a == "--enrolments" and i + 2 <= len(sys.argv):
        TARGET_ENROLMENTS = int(sys.argv[i + 2])

OUT_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "bulk_data")
os.makedirs(OUT_DIR, exist_ok=True)

TODAY = date.today()
NOW = datetime.now()
# Two years of history PLUS the next 14 days, so there are always future
# sessions for the constraint tests (P1) and the booking demos (P3).
START_DATE = TODAY - timedelta(days=730)
END_DATE   = TODAY + timedelta(days=14)

def years_ago(n):
    """Same calendar day n years ago (Feb 29 -> Feb 28)."""
    try:
        return TODAY.replace(year=TODAY.year - n)
    except ValueError:
        return TODAY.replace(year=TODAY.year - n, day=28)

# ----------------------------------------------------------------------------
# 1. Static seed (matches seed.sql-ish, but bigger)
# ----------------------------------------------------------------------------
POOLS = [
    ("SplashPoint Wuse",     "Abuja", "14 Adetokunbo Ademola Crescent, Wuse 2, Abuja",     "06:00:00", "20:00:00"),
    ("SplashPoint Maitama",  "Abuja", "20 IBB Way, Maitama, Abuja",                          "06:00:00", "20:00:00"),
    ("SplashPoint Ikoyi",    "Lagos", "8 Bank Road, Ikoyi, Lagos",                            "06:00:00", "20:00:00"),
    ("SplashPoint Lekki",    "Lagos", "12 Admiralty Way, Lekki Phase 1, Lagos",               "06:00:00", "20:00:00"),
]

# lanes per pool (pool_idx, lane_number, max_capacity)
LANES = []
for pool_idx, _ in enumerate(POOLS, start=1):
    n_lanes = random.choice([3, 4, 5])
    for n in range(1, n_lanes + 1):
        LANES.append((pool_idx, n, random.choice([4, 6])))

LESSON_TYPES = [
    # name, description, default_duration_min, is_group, capacity, price_ngn
    ("Private 1-on-1",  "One swimmer, one instructor",               30, False, 1, 8000),
    ("Group Children",  "Up to 6 children learning together",        45, True,  6, 5000),
    ("Group Adult",     "Up to 4 adults learning together",          45, True,  4, 6000),
    ("Adult Beginner",  "Up to 4 adults, no prior experience",       60, True,  4, 7000),
    ("Toddler Splash",  "Up to 4 toddlers with guardian in water",   30, True,  4, 4000),
]

# Nigerian names — Yoruba, Igbo, Hausa, mixed
FIRST_NAMES_M = ["Tunde","Chidi","Ibrahim","Emeka","Sani","Bola","Kunle","Yusuf","Obinna","Ahmed",
                 "Femi","Daniel","Seyi","Abdullahi","Tope","Kelechi","Gbolahan","Musiliu","Jide","Hassan",
                 "Bayo","Uche","Nasir","Wale","Chukwu","Tanimu","Ade","Onyeka","Suleiman","Ifedayo"]
FIRST_NAMES_F = ["Ngozi","Aisha","Chioma","Fatima","Kemi","Zainab","Adaora","Hauwa","Bisi","Funke",
                 "Maryam","Sandra","Bukola","Halima","Titilayo","Rukayat","Stella","Amina","Yetunde","Lola",
                 "Ifeoma","Saadatu","Tomi","Adaeze","Nkechi","Blessing","Oluwaseun","Hadiza","Ola","Folake"]
LAST_NAMES = ["Okafor","Bello","Eze","Adeyemi","Sani","Nwosu","Yusuf","Ibrahim","Muhammed","Okon",
              "Ali","Ojo","Toko","Lawal","Eze","Adebayo","Okeke","Danjuma","Oladipo","Garba",
              "Abubakar","Mohammed","Nnamdi","Uzor","Okoro","Salami","Bashir","Akpan","Idris","Oyelowo"]
RELATIONSHIPS = ["Mother","Father","Grandparent","Aunt","Uncle","Legal Guardian","Other"]

# ----------------------------------------------------------------------------
# 2. Generate pools, lanes, instructors, lesson_types, guardians, swimmers
# ----------------------------------------------------------------------------
pools_rows = []
for i, (name, city, addr, ot, ct) in enumerate(POOLS, start=1):
    pools_rows.append((i, name, city, addr, ot, ct))

lanes_rows = []
lane_id = 1
for pool_idx, lane_num, cap in LANES:
    lanes_rows.append((lane_id, pool_idx, lane_num, cap))
    lane_id += 1

# instructors — 30 of them, spread across both cities
INSTRUCTOR_COUNT = 30
instructors_rows = []
for i in range(1, INSTRUCTOR_COUNT + 1):
    sex = random.choice(["M","F"])
    fn = random.choice(FIRST_NAMES_M if sex == "M" else FIRST_NAMES_F)
    ln = random.choice(LAST_NAMES)
    phone = "0803" + str(random.randint(1000000, 9999999))
    email = f"{fn.lower()}.{ln.lower()}{i}@splashpoint.ng"
    hire = (TODAY - timedelta(days=random.randint(120, 2500))).isoformat()
    cert = random.choice(["Level 1","Level 2","Level 3","Level 4"])
    instructors_rows.append((i, fn, ln, phone, email, hire, cert))

# lesson types
lesson_types_rows = []
for i, (name, desc, dur, is_grp, cap, price) in enumerate(LESSON_TYPES, start=1):
    lesson_types_rows.append((i, name, desc, dur, is_grp, cap))

# guardians — 5000 (some swimmers share guardians)
GUARDIAN_COUNT = 5000
guardians_rows = []
for i in range(1, GUARDIAN_COUNT + 1):
    sex = random.choice(["M","F"])
    fn = random.choice(FIRST_NAMES_M if sex == "M" else FIRST_NAMES_F)
    ln = random.choice(LAST_NAMES)
    phone = "080" + str(random.randint(100000000, 999999999))
    email = f"{fn.lower()}.{ln.lower()}{i}@gmail.com"
    rel = random.choice(RELATIONSHIPS)
    guardians_rows.append((i, fn, ln, phone, email, rel))

# swimmers — 20000 (mix of children/teens/adults)
SWIMMER_COUNT = 20000
swimmers_rows = []
for i in range(1, SWIMMER_COUNT + 1):
    sex = random.choice(["M","F"])
    fn = random.choice(FIRST_NAMES_M if sex == "M" else FIRST_NAMES_F)
    ln = random.choice(LAST_NAMES)
    # Age distribution: 40% under 13, 25% teen, 30% adult, 5% senior
    age_bucket = random.choices(["child","teen","adult","senior"], weights=[40,25,30,5])[0]
    if age_bucket == "child":
        age = random.randint(3, 12)
    elif age_bucket == "teen":
        age = random.randint(13, 17)
    elif age_bucket == "adult":
        age = random.randint(18, 60)
    else:
        age = random.randint(61, 80)
    # exact age: born between (age+1) years ago + 1 day and exactly `age` years ago
    dob = (years_ago(age) - timedelta(days=random.randint(0, 364))).isoformat()
    if age < 13:
        age_class = "Child"
    elif age < 18:
        age_class = "Teen"
    elif age < 60:
        age_class = "Adult"
    else:
        age_class = "Senior"
    if age < 18:
        guardian_id = random.randint(1, GUARDIAN_COUNT)
        phone = None
        email = None
    else:
        guardian_id = None
        phone = "080" + str(random.randint(100000000, 999999999))
        email = f"{fn.lower()}.{ln.lower()}{i}@gmail.com"
    swimmers_rows.append((i, fn, ln, dob, age_class, phone, email, guardian_id))

CHILD_IDS = [r[0] for r in swimmers_rows if r[4] in ("Child",)]
YOUNG_IDS = [r[0] for r in swimmers_rows if r[4] in ("Child", "Teen")]
ADULT_IDS = [r[0] for r in swimmers_rows if r[4] in ("Adult", "Senior")]
ALL_IDS   = [r[0] for r in swimmers_rows]
# Which swimmers suit which lesson type (no adults in "Group Children", etc.)
LT_SWIMMERS = {1: ALL_IDS, 2: YOUNG_IDS, 3: ADULT_IDS, 4: ADULT_IDS, 5: CHILD_IDS}

# ----------------------------------------------------------------------------
# 3. Generate lesson_sessions — the heart of the no-overlap constraint
#    Strategy:
#      - For each (pool, day) generate a schedule of sessions per lane.
#      - Sessions are 30 / 45 / 60 minutes long, between 06:00 and 20:00.
#      - Each lane's sessions are sequential with a small random gap (0..30 min).
#      - Each session gets an instructor chosen so that instructor doesn't
#        already have an overlapping session somewhere that day.
#      - Group sessions get capacity filled at most with cap swimmers.
# ----------------------------------------------------------------------------

DAYS = (END_DATE - START_DATE).days + 1

# Lesson type lookup
LT_LOOKUP = {i + 1: LESSON_TYPES[i] for i in range(len(LESSON_TYPES))}  # id -> tuple

# Lane -> pool_idx
LANE_TO_POOL = {lid: pool_idx for lid, (pool_idx, _, _) in zip(range(1, len(LANES) + 1), LANES)}

# Build a per-day, per-lane list of sessions
lesson_sessions_rows = []
session_id_counter = 1

# We need enough sessions to host 60k enrolments:
#   average capacity ~ 3.5 swimmers per session  -> need ~ 60k/3.5 ~ 17000 sessions
#   over 730 days, ~ 23 sessions per day across all lanes (8 pools * ~4 lanes = ~16 lanes)
#   Each lane hosts ~ 8 sessions/day  -> ~ 130 sessions/day total
#   That's plenty. We'll cap sessions per lane per day to keep things realistic.

SESSIONS_PER_LANE_PER_DAY_RANGE = (1, 4)   # ~30k sessions, so most sessions have swimmers (4-8 left ~70% empty)
POOL_INSTRUCTOR_PREFERENCE = {
    1: list(range(1, 16)),   # Abuja
    2: list(range(1, 16)),
    3: list(range(11, 31)),  # Lagos
    4: list(range(11, 31)),
}

# For each (date, instructor) track booked ranges so we never double-book an instructor
instructor_booked = {}   # (date_iso, instructor_id) -> list of (start_dt, end_dt)

for day_offset in range(DAYS):
    d = START_DATE + timedelta(days=day_offset)
    d_iso = d.isoformat()
    # skip a few random days per pool (public holidays, pool maintenance)
    if random.random() < 0.05:
        continue
    for lane_idx_in_list, (pool_idx, lane_num, lane_cap) in enumerate(LANES):
        lane_id = lane_idx_in_list + 1
        n_sessions = random.randint(*SESSIONS_PER_LANE_PER_DAY_RANGE)
        # Sessions start between 06:00 and 19:00, sequential
        cur_hour, cur_min = 6, 0
        for _ in range(n_sessions):
            # choose a lesson type compatible with the lane capacity
            valid_lts = [i for i, lt in LT_LOOKUP.items() if lt[4] <= lane_cap]
            lt_id = random.choice(valid_lts)
            lt = LT_LOOKUP[lt_id]
            duration_min = lt[2]
            price = lt[5]
            # add a random gap of 0-30 min before this session
            gap = random.randint(0, 30)
            cur_min += gap
            while cur_min >= 60:
                cur_min -= 60
                cur_hour += 1
            if cur_hour >= 19:
                break  # day full
            start_dt = datetime(d.year, d.month, d.day, cur_hour, cur_min)
            end_dt   = start_dt + timedelta(minutes=duration_min)
            if end_dt.time() > time(20, 0):
                break
            # choose an instructor who is free in this window
            pool_instructors = POOL_INSTRUCTOR_PREFERENCE[pool_idx]
            random.shuffle(pool_instructors)
            chosen_instructor = None
            for ins_id in pool_instructors:
                booked = instructor_booked.get((d_iso, ins_id), [])
                conflict = False
                for (bs, be) in booked:
                    if start_dt < be and end_dt > bs:
                        conflict = True
                        break
                if not conflict:
                    chosen_instructor = ins_id
                    break
            if chosen_instructor is None:
                # all preferred instructors busy; try any instructor
                all_ids = list(range(1, INSTRUCTOR_COUNT + 1))
                random.shuffle(all_ids)
                for ins_id in all_ids:
                    booked = instructor_booked.get((d_iso, ins_id), [])
                    conflict = any(start_dt < be and end_dt > bs for (bs, be) in booked)
                    if not conflict:
                        chosen_instructor = ins_id
                        break
            if chosen_instructor is None:
                # truly nobody free; advance the clock and try next
                cur_min += duration_min
                while cur_min >= 60:
                    cur_min -= 60
                    cur_hour += 1
                continue
            # book the instructor
            instructor_booked.setdefault((d_iso, chosen_instructor), []).append((start_dt, end_dt))
            # insert session
            lesson_sessions_rows.append((
                session_id_counter,
                pool_idx,
                lane_id,
                chosen_instructor,
                lt_id,
                start_dt.strftime("%Y-%m-%d %H:%M:%S+01"),   # Lagos local time (WAT)
                end_dt.strftime("%Y-%m-%d %H:%M:%S+01"),
                duration_min,
                f"{price}.00",
            ))
            session_id_counter += 1
            # advance the clock
            cur_min += duration_min
            while cur_min >= 60:
                cur_min -= 60
                cur_hour += 1

print(f"Generated {len(lesson_sessions_rows)} lesson sessions over {DAYS} days.")

# ----------------------------------------------------------------------------
# 4. Generate enrolments — 60k+
#    For each session, enrol up to `capacity` swimmers (no over-capacity).
# ----------------------------------------------------------------------------
enrolments_rows = []
payments_rows = []
enrolment_id = 1
payment_id = 1
swimmer_busy = set()   # (swimmer_id, date) -> one lesson per swimmer per day
target = TARGET_ENROLMENTS

# Shuffle sessions for realistic enrol_date distribution
session_idx_order = list(range(len(lesson_sessions_rows)))
random.shuffle(session_idx_order)

for s_idx in session_idx_order:
    if len(enrolments_rows) >= target:
        break
    sid, pool_idx, lane_id, instructor_id, lt_id, start, end, dur, price = lesson_sessions_rows[s_idx]
    lt = LT_LOOKUP[lt_id]
    cap = lt[4]
    # Number enrolled: weighted by capacity (group sessions more filled)
    if lt[3]:  # group
        n_enrolled = random.choices(
            range(0, cap + 1),
            weights=[1, 2, 3, 4, 5, 6, 7][: cap + 1]
        )[0]
    else:  # private — 0 or 1
        n_enrolled = random.choices([0, 1], weights=[3, 7])[0]
    if n_enrolled == 0:
        continue
    # choose swimmers of the right age group, max one lesson per swimmer per day
    sess_start_dt = datetime.strptime(start, "%Y-%m-%d %H:%M:%S+01")
    day_key = sess_start_dt.date()
    candidates = LT_SWIMMERS[lt_id]
    chosen = []
    tries = 0
    while len(chosen) < n_enrolled and tries < 50:
        tries += 1
        sw = random.choice(candidates)
        if sw in chosen or (sw, day_key) in swimmer_busy:
            continue
        chosen.append(sw)
    for sw in chosen:
        swimmer_busy.add((sw, day_key))
    # enrol_date is before session start, and never in the future
    enrol_dt = sess_start_dt - timedelta(days=random.randint(0, 14), hours=random.randint(0, 23))
    if enrol_dt < datetime(START_DATE.year, START_DATE.month, START_DATE.day):
        enrol_dt = datetime.combine(START_DATE, time(8, 0))
    if enrol_dt > NOW:
        enrol_dt = NOW - timedelta(hours=random.randint(1, 48))
    # attendance: mostly attended; some no-show
    for swimmer_id in chosen:
        if len(enrolments_rows) >= target:
            break
        # attendance only set for sessions in the past
        if sess_start_dt < NOW:
            r = random.random()
            if r < 0.85:
                status, attended = "attended", True
            elif r < 0.95:
                status, attended = "no_show", False
            else:
                status, attended = "cancelled", None
        else:
            status, attended = "confirmed", None
        enrolments_rows.append((
            enrolment_id,
            sid,
            swimmer_id,
            enrol_dt.strftime("%Y-%m-%d %H:%M:%S+01"),
            status,
            "TRUE" if attended else ("FALSE" if attended is False else ""),
        ))
        # payment — only for confirmed/attended/no_show, not cancelled
        if status != "cancelled":
            method = random.choice(["Card","Bank Transfer","Cash","USSD","POS"])
            pay_status = "paid" if random.random() < 0.98 else "failed"
            payments_rows.append((
                payment_id,
                enrolment_id,
                price,
                enrol_dt.strftime("%Y-%m-%d %H:%M:%S+01"),
                method,
                pay_status,
            ))
            payment_id += 1
        enrolment_id += 1

print(f"Generated {len(enrolments_rows)} enrolments and {len(payments_rows)} payments.")

# ----------------------------------------------------------------------------
# 5. Write CSVs
# ----------------------------------------------------------------------------
def write_csv(path, header, rows):
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        for r in rows:
            w.writerow(r)

write_csv(os.path.join(OUT_DIR, "pools.csv"),
          ["pool_id","name","city","address","opening_time","closing_time"], pools_rows)
write_csv(os.path.join(OUT_DIR, "lanes.csv"),
          ["lane_id","pool_id","lane_number","max_capacity"], lanes_rows)
write_csv(os.path.join(OUT_DIR, "instructors.csv"),
          ["instructor_id","first_name","last_name","phone","email","hire_date","certification_level"], instructors_rows)
write_csv(os.path.join(OUT_DIR, "guardians.csv"),
          ["guardian_id","first_name","last_name","phone","email","relationship"], guardians_rows)
write_csv(os.path.join(OUT_DIR, "swimmers.csv"),
          ["swimmer_id","first_name","last_name","dob","age_class","phone","email","guardian_id"], swimmers_rows)
write_csv(os.path.join(OUT_DIR, "lesson_types.csv"),
          ["lesson_type_id","name","description","default_duration_min","is_group","capacity"], lesson_types_rows)
write_csv(os.path.join(OUT_DIR, "lesson_sessions.csv"),
          ["session_id","pool_id","lane_id","instructor_id","lesson_type_id","start_time","end_time","duration_min","price"], lesson_sessions_rows)
write_csv(os.path.join(OUT_DIR, "enrolments.csv"),
          ["enrolment_id","session_id","swimmer_id","enrol_date","status","attended"], enrolments_rows)
write_csv(os.path.join(OUT_DIR, "payments.csv"),
          ["payment_id","enrolment_id","amount","payment_date","payment_method","status"], payments_rows)

print(f"\nWrote 9 CSV files to {OUT_DIR}")
print(f"Total enrolments: {len(enrolments_rows)}")
print(f"Total payments:   {len(payments_rows)}")
print(f"Total sessions:   {len(lesson_sessions_rows)}")
print(f"Total swimmers:   {len(swimmers_rows)}")
