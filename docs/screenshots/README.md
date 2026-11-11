# Screenshots to capture (from YOUR Codespace run)

Take each one from the real terminal output or log file after the run-all box has finished.
Name them `P1_row_counts.png`, `P1_constraint_tests.png`, and so on.

| # | Portfolio | What to capture | Where it is |
| --- | --- | --- | --- |
| 1 | P1 | Row-count table (60,000 enrolments) | `p1_output.log` |
| 2 | P1 | Constraint tests [1]–[15] ERROR lines + [16] UPDATE | `p1_output.log` |
| 3 | P1 | ER diagram rendered on GitHub | `portfolio-1-database-design/README.md` on github.com |
| 4 | P2 | Before/after summary table | `portfolio-2-query-optimisation/explain_summary.txt` |
| 5 | P2 | Q3 plan before (Seq Scan) and after (Index Scan using idx_session_start) | `explain_log_before.txt` / `explain_log_after.txt` |
| 6 | P3 | Part 1 overbooking 7/6 | `portfolio-3-transactions-concurrency/race_demos_output.log` |
| 7 | P3 | Part 3 (B BLOCKED → "is full") and Part 4 (40001 → retry refused) | `race_demos_output.log` |
| 8 | P3 | Deadlock detected | `race_demos_output.log` Part 6 or `p3_output.log` |
| 9 | P4 | Validator REJECTED lines + document count | `p4_output.log` |
| 10 | P4 | Index SUMMARY: COLLSCAN vs IXSCAN | `p4_output.log` |
| 11 | P5 | Partition pruning EXPLAIN (Subplans Removed) | `p5_output.log` |
| 12 | P5 | Replica: read-only error, row arriving, pg_stat_replication | `portfolio-5-distributed-cloud/replication_output.log` |
