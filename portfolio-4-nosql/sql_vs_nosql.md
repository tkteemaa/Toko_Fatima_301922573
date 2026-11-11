# SQL vs NoSQL — A Short Comparison for SplashPoint Swim School

**Portfolio 4 — MIT 8103 Advanced Database Systems**

This note compares when to use a relational database (PostgreSQL) vs a document database (MongoDB) for SplashPoint Swim School. Both are used in this portfolio — they are complementary, not competitors.

---

## 1. The two stores in this portfolio

| Concern | Store | Why |
| --- | --- | --- |
| Booking, enrolment, payment, scheduling, capacity, exclusion constraints | **PostgreSQL** | Strict relational integrity; exclusion constraints on `tstzrange`; ACID transactions; serialisable isolation; triggers; foreign keys. |
| Per-lesson skill assessments, instructor comments, safety incidents | **MongoDB** | Variable-shape documents (different skill checklist per level); embed arrays instead of JOINing; schema evolves with the curriculum. |

---

## 2. When SQL (PostgreSQL) is the right call

- **Strong integrity requirements.** SplashPoint must never double-book a lane, never overbook a group session, never store a payment with `amount <= 0`. Exclusion constraints, CHECKs, and triggers enforce these in the database — no application bug can violate them.
- **Multi-row transactions across tables.** Enrolling a swimmer touches `enrolment` AND `payment` atomically. ACID guarantees that.
- **Complex joins and analytics.** "Revenue per pool per month" joins 4 tables. SQL is built for this.
- **Mature ecosystem.** ORMs, BI tools, DBA tooling, replication, partitioning, point-in-time recovery, backups — all battle-tested.

**Cost:** schema is rigid; changing it means migrations; data that does not fit the schema is awkward (nullable columns, JOIN-heavy child tables).

---

## 3. When NoSQL (MongoDB) is the right call

- **Document-shaped data.** A progress note is a tree: skills (array of objects), instructor_comment (free text), safety_incidents (array, usually empty). In SQL you need 3 tables + JOINs; in MongoDB it is one document.
- **Schema varies by type.** A Tadpole lesson checks 4 skills; a Squad lesson checks 10 different skills. Encoding this in SQL needs either many nullable columns or a separate `skill` master table. In MongoDB each document just includes the relevant checklist.
- **Schema evolves quickly.** Adding a new skill to the Squad checklist is an application-side change; new documents include the skill, old documents do not. No migration.
- **Read pattern is "the whole document".** The instructor's dashboard reads the entire progress note at once. Embedding gives single-document reads — no JOINs.
- **Horizontal scale-out.** MongoDB sharding is built in. SplashPoint could shard by `swimmer_id` once the swimmer count grows past a single node.

**Cost:** no joins (you denormalise or do client-side joins); transactions across multiple documents are possible since 4.0 but slower than SQL; no exclusion constraints — overlap rules must be enforced in application code.

---

## 4. CAP theorem placement

| Store | Default consistency | Availability under partition | Notes |
| --- | --- | --- | --- |
| PostgreSQL (single primary) | **Strong (CP)** | single-node failure = no writes | ACID, no compromises |
| PostgreSQL primary + streaming replica (sync) | **Strong for writes** (sync replica ack) | reads from replica; writes need primary | Portfolio 5 sets this up |
| PostgreSQL primary + async replica | **Eventual for reads** | reads from replica may lag; writes need primary | common for read-heavy workloads |
| MongoDB replica set | **Strong for primary reads** (linearisable via `{readConcern:"linearizable"}`); eventual for secondary reads | majority-available writes if `writeConcern:"majority"` | sharding adds another axis |
| MongoDB sharded cluster | **Tunable per query** | survives shard failure if replica set has majority | shards are themselves replica sets |

For SplashPoint we keep children's personal data on **strongly-consistent, in-Nigeria** storage (PostgreSQL primary + sync replica). The progress notes (MongoDB) can tolerate eventual consistency on secondaries because they are not used for billing or safety-critical decisions — the *primary* progress note is still strongly consistent.

---

## 5. SQL ↔ MongoDB concept map

| SQL | MongoDB | Notes |
| --- | --- | --- |
| database | database | same term |
| table | collection | a collection is *not* required to have a schema, but we enforce one with `$jsonSchema` |
| row | document | a document is a JSON-like object |
| column | field | fields can vary per document |
| primary key | `_id` | MongoDB auto-creates an ObjectId if you don't supply one; we use int `note_id` |
| index | index | same B-tree concept; MongoDB also supports geospatial, text, hashed |
| JOIN | `$lookup` (aggregation stage) | MongoDB prefers embedding; `$lookup` is slower than a SQL join |
| transaction | transaction (4.0+) | multi-document ACID since MongoDB 4.0 |
| CHECK constraint | `$jsonSchema` validator | MongoDB validators are more flexible (can use `$expr`) |
| trigger | change stream / triggers (rare) | MongoDB prefers application-side logic |
| `EXPLAIN ANALYZE` | `db.coll.find().explain("executionStats")` | COLLSCAN = Seq Scan, IXSCAN = Index Scan |

---

## 6. The decision for SplashPoint

SplashPoint's **operational** data (the things that lose money if wrong — bookings, payments, scheduling, capacity) lives in **PostgreSQL**. SplashPoint's **observational** data (the things that grow and change shape — skill assessments, instructor comments, safety incidents) lives in **MongoDB**. The two are joined by stable integer keys (`swimmer_id`, `session_id`, `instructor_id`) that exist in both stores.

This is a **polyglot persistence** pattern (Martin Fowler's term): pick the right store for each data shape, integrate at the application layer. The trade-off is operational complexity (two databases to back up, monitor, upgrade) — but the benefit is that each store is doing what it is best at.

---

## 7. References

- PostgreSQL 16 documentation — https://www.postgresql.org/docs/16/
- MongoDB 8 manual — https://www.mongodb.com/docs/manual/
- Martin Fowler, *Polyglot Persistence* — https://martinfowler.com/bliki/PolyglotPersistence.html
- Eric Brewer, *CAP Theorem* — https://en.wikipedia.org/wiki/CAP_theorem
