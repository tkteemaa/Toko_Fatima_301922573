# Portfolio 5 — Distributed and Cloud Database Exercise

**Student:** Fatima Toko Ali · 2026/A/MIT/0873
**Case study:** SplashPoint Swim School (simulated).
**Study session covered:** Partitioning & sharding, replication, CAP theorem & consistency models, cloud databases & data sovereignty (NDPA 2023).

---

## What this portfolio demonstrates

1. **Declarative range partitioning** of `lesson_session` by month (`partition.sql`). The partition key is `start_time`. We create one parent table and monthly child partitions for the 2-year window the bulk generator covered, plus next month and the month after. The exclusion constraints from Portfolio 1 are re-applied to each child partition (PostgreSQL 16 does not allow them on the partitioned parent), a DEFAULT partition catches out-of-range dates, and the lost `enrolment → lesson_session` foreign key is replaced by a trigger (a FK to a partitioned table would need the full key `(session_id, start_time)`). We demonstrate **partition pruning** with `EXPLAIN` showing the planner scans only the relevant partition.

2. **Primary + streaming read replica** (`replica_setup.sh` + `replica_demo.sh`). Using `pg_basebackup`, we clone the primary into a second data directory, configure it as a hot standby, and start it on a different port. We show:
   - The replica accepts `SELECT` queries.
   - The replica **rejects** writes: `INSERT` raises `ERROR: cannot execute INSERT in a read-only transaction`.
   - New rows inserted on the primary arrive on the replica after a brief replication lag.

3. **Cloud architecture** (`cloud_architecture.md`). A SplashPoint cloud deployment keeping **all personal data inside Nigeria** per the Nigeria Data Protection Act 2023 (NDPA 2023), with:
   - Primary + sync replica in a Lagos Availability Zone.
   - Async replica in an Abuja AZ for disaster recovery.
   - Read replica for analytics.
   - MongoDB replica set with the same residency rules.
   - **Extra protection for children's personal data**: column-level encryption for guardian contact info, separate role-based access, audit logging, NDPA-compliant retention (e.g. minors' data deleted 3 years after their 18th birthday unless legal hold).
   - **CAP theorem** placement: CP for billing/scheduling (sync replica, strong consistency); AP for analytics (async replica, eventual consistency).
   - **Sync vs async replication** trade-offs discussed explicitly.

---

## Files

| File | Purpose |
| --- | --- |
| `partition.sql` | Converts `lesson_session` into a partitioned table by month, creates child partitions, re-applies constraints, demonstrates pruning. |
| `replica_setup.sh` | Uses `pg_basebackup` to clone the primary into a second data dir; configures the replica; starts it on port 5433. |
| `replica_demo.sh` | One script: who is who, write rejected on the replica, insert on the primary arrives on the replica, lag, `pg_stat_replication`. |
| `replica_demo.md` | The same demo as manual two-terminal steps. |
| `cloud_architecture.md` | The cloud architecture + NDPA 2023 + CAP + sync vs async + child-data protection write-up. |
| `run_p5.sh` | One-shot runner for the partitioning + replica demo. |

---

## Run it (Codespaces)

```bash
bash portfolio-5-distributed-cloud/run_p5.sh 2>&1 | tee p5_output.log
```

`run_p5.sh` runs `partition.sql` (conversion, row counts per partition, 0 rows in DEFAULT, pruning EXPLAIN,
two integrity checks), then `replica_setup.sh` (replica on port 5433), then `replica_demo.sh`, which switches between
the two servers itself and saves `replication_output.log`.

---

## What to screenshot

1. Rows copied / `rows_in_default = 0` and the rows-per-partition table.
2. The pruning EXPLAIN: `Subplans Removed: …` and only the current month's partition scanned.
3. The two integrity errors on the partitioned table (overlap, unknown session).
4. `replication_output.log`: `in_recovery` f/t, `cannot execute INSERT in a read-only transaction`,
   the new instructor appearing on the replica, and `pg_stat_replication` (`streaming`, `async`, lag).
5. The cloud architecture diagram in `cloud_architecture.md`.

---

## Git commit command

```bash
git add portfolio-5-distributed-cloud/
git commit -m "P5: monthly range partitioning + partition pruning, primary + streaming replica, Nigeria cloud architecture (NDPA 2023, CAP, sync vs async, child-data protection)"
git push
```

---

## Plain-English explanation

Two techniques make a database scale beyond a single node: **partitioning** (splitting one big table into smaller physical pieces) and **replication** (copying data to additional nodes).

**Partitioning** `lesson_session` by month means each month's sessions live in their own child table. When you query "sessions in November 2026", PostgreSQL's planner uses **partition pruning** to scan only the November child — the other monthly children are not touched. This makes date-range queries much faster on large tables. SplashPoint has about 30,000 sessions over two years (roughly 1,000–1,300 per month); at scale (10+ years, multiple pools per city) partitioning becomes essential.

**Replication** copies every write on the primary to one or more replicas. A **streaming replica** connects over the WAL (write-ahead log) stream and applies changes in real time. We use `pg_basebackup` to take a block-level copy of the primary, then start the copy as a **hot standby** that accepts read-only queries. Reads can be offloaded to the replica (analytics, reporting), and if the primary fails the replica can be promoted.

**Sync vs async replication:**

- **Synchronous** — primary waits for the replica to acknowledge each write before committing. Strong consistency (CP), but every write pays the network round-trip. Used for billing/scheduling where losing a transaction is unacceptable.
- **Asynchronous** — primary commits without waiting for the replica. Eventually consistent (closer to AP), faster writes, but the replica can lag and a primary failure can lose the last few transactions. Used for analytics replicas and cross-region DR.

**CAP theorem** says a distributed system can have at most two of {Consistency, Availability, Partition tolerance}. Since partitions *will* happen (networks fail), the real choice is C vs A:

- SplashPoint's booking system is **CP** — strong consistency, may refuse writes if the sync replica is unreachable.
- SplashPoint's analytics replica is **AP** — keep serving reads even if the primary is unreachable; tolerate stale data.

**Data sovereignty (NDPA 2023)** — the Nigeria Data Protection Act 2023 requires that personal data of Nigerians be stored and processed in Nigeria unless the data subject consents to transfer, or the destination country has adequate protection. For SplashPoint, this means primary + sync replica in Lagos, async DR replica in Abuja, and *no* cross-border replication of personal data without consent. Children's personal data has additional protection: parental consent for collection, minimisation, encryption, shorter retention, audit logging.
