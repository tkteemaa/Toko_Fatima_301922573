# Portfolio 2 — Query Processing and Optimisation

**Student:** Fatima Toko Ali · 2026/A/MIT/0873
**Case study:** SplashPoint Swim School (simulated).
**Study sessions covered:** SQL for analytics, query execution plans, indexing & access methods, performance tuning.

## What this portfolio demonstrates

Six analytical SQL queries against the SplashPoint data loaded in Portfolio 1 (60,000 enrolments):

1. **Free lanes** at SplashPoint Ikoyi tomorrow, 10:00–10:45 (booking screen).
2. **Instructor workload**: instructor 7's lessons per month, last 12 months.
3. **Revenue per pool** (₦, paid payments), last 30 days.
4. **Lane utilisation %**: booked minutes ÷ open minutes (14 h/day), last 730 days.
5. **Distinct swimmers who attended** each lesson type.
6. **Attendance / no-show rate** per instructor, last 90 days.

Each query is run with `EXPLAIN (ANALYZE, BUFFERS)` **before** and **after** the indexes in `indexes.sql`.

## Files

| File | Purpose |
| --- | --- |
| `queries.sql` | The 6 queries; each prints its real answer, then its EXPLAIN ANALYZE plan. Dates are relative to today (Lagos time). |
| `indexes.sql` | The indexes added between the two runs (B-tree, composite and partial indexes). |
| `run_p2.sh` | Drops the P2 indexes + ANALYZE (fair baseline) → BEFORE run → indexes + ANALYZE → AFTER run → summary table. |
| `explain_log_before.txt`, `explain_log_after.txt` | Full plans from your run (created by `run_p2.sh`). |
| `explain_summary.txt` | Before/after `Execution Time` per query and how each table was read (created by `run_p2.sh`). |
| `explain_results.md` | How to read the plans, explained honestly (which queries an index helps and which it can't). |

## Run it (Codespaces)

```bash
bash portfolio-2-query-optimisation/run_p2.sh 2>&1 | tee p2_output.log
```

## What to screenshot

1. `explain_summary.txt` (the before/after table).
2. Q3 BEFORE vs AFTER in the logs: `Seq Scan on lesson_session` → `Index Scan using idx_session_start`.
3. Q2 BEFORE vs AFTER: `Bitmap Index Scan on excl_instructor_overlap` → `... on idx_session_instructor_start`.
4. Q4 or Q5 AFTER, still a `Seq Scan` — and explain why (full-table aggregate).

## Plain-English explanation

The planner chooses a plan from table statistics. An index pays off when a query needs a **small slice** of a
table (one instructor, the last 30 days). It does not pay off when the query reads almost every row (all two
years of lane bookings, 83% of enrolments): then a sequential scan is cheaper, and PostgreSQL correctly ignores
the index. Q1 shows a third case: the P1 exclusion constraint already created a GiST index on `(lane_id, during)`,
so the free-lane check is fast even before any P2 index. The real numbers are in `explain_summary.txt`.
