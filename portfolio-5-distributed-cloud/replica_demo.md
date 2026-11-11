# Streaming Replica Demo — Step-by-Step

**Portfolio 5 — Distributed and Cloud Database Exercise**

> **Automated:** `replica_demo.sh` (run by `run_p5.sh`) does all of this in one script and saves `replication_output.log`.
> The manual two-terminal steps below are only for repeating it by hand.

After `replica_setup.sh` has finished, the primary runs on port **5432** and the streaming replica runs on port **5433**, both on the Unix socket `/var/run/postgresql`. This guide walks through the three things you must screenshot for the assessment:

1. **The replica rejects writes** (read-only transaction).
2. **The replica accepts reads**.
3. **New rows on the primary arrive on the replica** (replication lag).

Open **two terminals** in Codespaces.

---

## Terminal A — Primary (port 5432)

```bash
psql -h /var/run/postgresql -p 5432 -d splashpoint
```

## Terminal B — Replica (port 5433)

```bash
psql -h /var/run/postgresql -p 5433 -d splashpoint
```

---

## DEMO 1 — Replica rejects writes (read-only transaction)

In **Terminal B (replica)**, try to insert a row:

```sql
-- Terminal B
INSERT INTO pool (name, city, address, opening_time, closing_time)
VALUES ('Test Replica Write', 'Lagos', 'Nowhere', '06:00:00', '20:00:00');
```

**Expected output:**

```
ERROR:  cannot execute INSERT in a read-only transaction
```

This is the read-only guarantee: a streaming replica is in **hot standby** mode, which serves SELECTs but refuses any write. SplashPoint could safely point its analytics workload at this replica knowing it can never accidentally mutate data.

**Screenshot:** the `ERROR: cannot execute INSERT in a read-only transaction` line.

---

## DEMO 2 — Replica accepts reads

In **Terminal B (replica)**:

```sql
-- Terminal B
SELECT count(*) FROM pool;
SELECT count(*) FROM lesson_session;
SELECT count(*) FROM enrolment;
```

**Expected:** the same counts as on the primary (because `pg_basebackup` copied everything and the replica has been streaming since).

For comparison, in **Terminal A (primary)**:

```sql
-- Terminal A
SELECT count(*) FROM pool;
SELECT count(*) FROM lesson_session;
SELECT count(*) FROM enrolment;
```

**Expected:** identical counts.

**Screenshot:** the same counts on both terminals.

---

## DEMO 3 — New rows on the primary arrive on the replica

In **Terminal A (primary)**, insert a new pool and a new swimmer:

```sql
-- Terminal A
INSERT INTO pool (name, city, address, opening_time, closing_time)
VALUES ('SplashPoint Test Replica', 'Lagos', 'Replica Lane 1', '06:00:00', '20:00:00')
RETURNING pool_id;
\gset
SELECT count(*) AS pool_count_on_primary FROM pool;
```

In **Terminal B (replica)**, immediately after, query the count:

```sql
-- Terminal B
SELECT count(*) AS pool_count_on_replica FROM pool;
```

**Expected:** the count on the replica is **1 higher than before**, matching the primary. The replication lag is typically < 100ms on a single host.

If you want to **see the lag explicitly**:

```sql
-- Terminal A (primary): show replication status
SELECT application_name, state, sync_state,
       sent_lsn, write_lsn, flush_lsn, replay_lsn,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
  FROM pg_stat_replication;
```

```sql
-- Terminal B (replica): show how far behind we are
SELECT now() AS replica_now,
       pg_last_wal_receive_lsn() AS receive_lsn,
       pg_last_wal_replay_lsn()  AS replay_lsn,
       pg_wal_lsn_diff(pg_last_wal_receive_lsn(), pg_last_wal_replay_lsn()) AS lag_bytes;
```

**Screenshot:** the `lag_bytes` field. On a quiet single-host replica this will usually be 0 (caught up) but briefly non-zero immediately after the INSERT. Capture both states.

---

## DEMO 4 (optional) — Promote the replica

If the primary fails, the replica can be **promoted** to become a standalone primary that accepts writes. (Don't do this unless you mean it — promotion is irreversible.)

```bash
sudo runuser -u postgres -- /usr/lib/postgresql/16/bin/pg_ctl \
  -D /var/lib/postgresql/16/replica promote
```

After promotion, INSERTs on the replica succeed. The original primary can no longer be a primary for this replica without rebuilding it. We don't run this in the demo; it is documented here for completeness.

---

## DEMO 5 (optional) — Synchronous replication

To make the primary wait for the replica to acknowledge each write (synchronous replication, CP in CAP terms):

```sql
-- Terminal A (primary)
ALTER SYSTEM SET synchronous_standby_names = 'FIRST 1 (replica1)';
SELECT pg_reload_conf();
```

Then any write on the primary blocks until the replica has flushed it. If the replica is down, writes on the primary block (CP — choose consistency over availability). To revert:

```sql
ALTER SYSTEM SET synchronous_standby_names = '';
SELECT pg_reload_conf();
```

---

## What you have proven

1. The replica is **read-only** — write attempts fail with a clear error. This makes it safe for analytics offloading.
2. The replica is **up-to-date** — counts match the primary.
3. Replication is **streaming** — new writes appear on the replica within milliseconds.
4. (Optional) Synchronous mode trades write latency for strong consistency (CP).
5. (Optional) Promotion makes the replica a writable primary — the basis for high-availability failover.
