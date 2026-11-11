# EXPLAIN ANALYZE — Before / After Indexes

**Student:** Fatima Toko Ali · 2026/A/MIT/0873
**Portfolio:** 2 — Query Processing and Optimisation

> **Honesty rule:** every number for this portfolio comes from the student's own run in Codespaces.
> `run_p2.sh` writes the real numbers to `explain_summary.txt`. Nothing in this file is a measured result.

## How to reproduce

```bash
bash portfolio-2-query-optimisation/run_p2.sh
```

The runner makes the comparison fair: it **drops** the P2 indexes, runs `ANALYZE`, captures every plan
(`explain_log_before.txt`), creates the indexes from `indexes.sql`, runs `ANALYZE` again and captures the
plans a second time (`explain_log_after.txt`). It then prints a table (`explain_summary.txt`) with the
`Execution Time` of each query before and after, and how `lesson_session` and `enrolment` were read.

## Before / after table

Copy the rows from **`explain_summary.txt`** (your own run) into the documentation.

| Query | What it asks | Index added for it |
| --- | --- | --- |
| Q1 | Free lanes at SplashPoint Ikoyi tomorrow 10:00–10:45 | none needed — see below |
| Q2 | Instructor 7's lessons per month, last 12 months | `idx_session_instructor_start (instructor_id, start_time)` |
| Q3 | Revenue per pool, last 30 days | `idx_session_start (start_time)`, partial `idx_payment_status_paid` |
| Q4 | Lane utilisation %, last 730 days | `idx_session_lane_start` (expected NOT to be used) |
| Q5 | Distinct swimmers who attended each lesson type | partial `idx_enrolment_attended` (expected NOT to be used) |
| Q6 | No-show rate per instructor, last 90 days | `idx_session_start`, `idx_enrolment_session_status` |

## How to read the plans (explained honestly)

- **Q1** is already fast *before* any P2 index: the two P1 exclusion constraints are backed by GiST indexes
  on `(lane_id, during)` and `(instructor_id, during)`, and the planner uses one of them (which one depends on its
  estimates) to find sessions overlapping the time window. Good defence point: the integrity constraint doubles as
  the lookup index, so the P2 B-tree indexes don't change Q1.
- **Q2** filters one instructor and a date range. Before, the planner can only use the GiST index of
  `excl_instructor_overlap` (instructor match, then filters dates). After, the B-tree
  `(instructor_id, start_time)` matches both conditions, so far fewer rows are fetched.
- **Q3 / Q6** filter the last 30 / 90 days. After the index, `lesson_session` is read with an
  *Index Scan on idx_session_start* instead of a Seq Scan of all sessions. `enrolment` may **still** be read
  with a Seq Scan + Hash Join: with ~60k narrow rows, hashing the whole table is cheaper for the planner
  than thousands of index probes. That is a correct cost-based decision, not a failure.
- **Q4 / Q5** aggregate the whole two-year history. Reading (nearly) every row is cheapest with a
  sequential scan, so the planner ignores the indexes and timings stay about the same. Indexes help
  selective queries, not full-table aggregates. Faster options here would be a materialised view
  or a summary table refreshed nightly.
- Timings under ~1 ms vary from run to run (cache, Codespaces CPU); compare plan shapes, not just ms.
