# Advanced Database Systems Portfolio — MIT 8103

**Student:** Fatima Toko Ali
**Matric number:** 2026/A/MIT/0873
**Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 Advanced Database Systems (2026/2027, First Semester)
**Case study:** Swimming Lesson Booking for **SplashPoint Swim School** (simulated) — pools in Abuja (Wuse, Maitama) and Lagos (Ikoyi, Lekki).

GitHub repository: **[GitHub link]**

---

## What this repository contains

Five portfolios, each in its own folder, each runnable with its own `run_pN.sh` script:

| Portfolio | Folder | What it demonstrates | Study session |
| --- | --- | --- | --- |
| P1 | `portfolio-1-database-design/` | ER diagram, 3NF schema (9 tables), exclusion constraints on `tstzrange`, triggers, 50k+ row bulk generator, constraint tests that must FAIL. | ER modelling, normalisation, integrity constraints & triggers |
| P2 | `portfolio-2-query-optimisation/` | 6 analytical SQL queries, EXPLAIN ANALYZE before/after indexes, before/after table. | SQL analytics, query plans, indexing, performance tuning |
| P3 | `portfolio-3-transactions-concurrency/` | `enrol_swimmer()` transactional function, COMMIT/ROLLBACK, two-terminal race condition guide (bug → FOR UPDATE fix → SERIALIZABLE retry fix), isolation levels, deadlock demo. | ACID, isolation levels, locking & MVCC, concurrency problems, serialisability |
| P4 | `portfolio-4-nosql/` | MongoDB swimmer-progress notes with `$jsonSchema` validation, 40k+ documents, aggregation pipelines, COLLSCAN → IXSCAN index demo, SQL vs NoSQL comparison. | NoSQL foundations, MongoDB document modelling, aggregation framework, indexing, SQL vs NoSQL |
| P5 | `portfolio-5-distributed-cloud/` | Monthly range partitioning of `lesson_session`, primary + streaming read replica setup script, replica demo (writes rejected, new rows arrive), cloud architecture keeping data in Nigeria per NDPA 2023, CAP and sync-vs-async trade-offs, extra protection for children's data. | Partitioning, replication, CAP, cloud databases, data sovereignty |

A `docs/00_brief_summary.md` summarises the CA brief and maps each portfolio to the course-note study sessions.

The final 2–3 page PDF (`Ali_Fatima_Documentation.pdf`) is **not** in this ZIP. It is produced after the student has run every portfolio, from her real results.

---

## One-time setup (Codespaces, Ubuntu 24.04)

Run from the repo root:

```bash
bash setup.sh
```

`setup.sh`:

1. Removes `/etc/apt/sources.list.d/yarn.list` (a known Codespaces quirk that breaks `apt-get update`).
2. Installs PostgreSQL 16 and MongoDB 8 (community edition) via `apt`.
3. Initialises and starts PostgreSQL 16 on the Unix socket `/var/run/postgresql` (no TCP password needed).
4. Starts MongoDB 8 on the default port `27017` (localhost, no auth for the demo).
5. Creates the `splashpoint` PostgreSQL database and the `splashpoint` MongoDB database.
6. Installs the `btree_gist` extension (needed for the exclusion constraints in P1).
7. Sets the database time zone to Africa/Lagos and installs the Python `psycopg2-binary` and `pymongo` packages.

After `setup.sh` finishes, run each portfolio's `run_pN.sh` script. Each `run_pN.sh` is self-contained and prints what it is doing.

---

## Running each portfolio

```bash
# P1 — schema, 60,000 enrolments, 17 constraint tests
bash portfolio-1-database-design/run_p1.sh 2>&1 | tee p1_output.log
# P2 — 6 queries, EXPLAIN ANALYZE before/after indexes, summary table
bash portfolio-2-query-optimisation/run_p2.sh 2>&1 | tee p2_output.log
# P3 — enrol_swimmer(), COMMIT/ROLLBACK, isolation, deadlock, 6-part race demo
bash portfolio-3-transactions-concurrency/run_p3.sh 2>&1 | tee p3_output.log
# P4 — MongoDB validator, 50k notes from the real attended lessons, aggregations, COLLSCAN -> IXSCAN
bash portfolio-4-nosql/run_p4.sh 2>&1 | tee p4_output.log
# P5 — monthly partitions + pruning, streaming replica, one-script replica demo
bash portfolio-5-distributed-cloud/run_p5.sh 2>&1 | tee p5_output.log
# gather every result into my_results.txt
bash collect_results.sh
```

Each portfolio folder has its own `README.md` with what it demonstrates, what to screenshot and a plain-English explanation. `CHANGES.md` lists every fix made after testing.

---

## Progressive commits

Each portfolio is committed and pushed on its own, straight after it runs, together with its output log
(`pN_output.log`). `collect_results.sh` then gathers every log into `my_results.txt` for the documentation.

---

## Honesty rules (read me)

- Every plan, timing, MongoDB `explain()` result and screenshot comes from the student's own run in her own Codespace
  (the `pN_output.log`, `explain_summary.txt`, `race_demos_output.log` and `replication_output.log` files).
- No simulated timings, no invented plans, no fabricated screenshots.
- The final 2–3 page PDF is written **after** everything has run, from those real results.

---

## AI-use declaration

- An AI assistant drafted the first version of the scripts and documents from the CA brief.
- The kit was then tested in a Codespaces-like environment and fixed; every change is listed in `CHANGES.md`
  (problem found when run → fix → tested result).
- The student ran every portfolio in her own Codespace, checked the outputs and committed them. The full declaration
  (tool, purpose, how it was checked) is in the final documentation.
