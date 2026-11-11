# Brief Summary — MIT 8103 Advanced Database Systems CA

**Student:** Fatima Toko Ali
**Matric number:** 2026/A/MIT/0873
**Programme:** Master of Information Technology, Miva Open University
**Course:** MIT 8103 Advanced Database Systems (2026/2027 First Semester)
**Case study:** Swimming Lesson Booking for **SplashPoint Swim School** (simulated), with pools in Abuja (Wuse, Maitama) and Lagos (Ikoyi, Lekki).

---

## A. What the CA requires (read straight from the brief)

| Item | Requirement |
| --- | --- |
| **Type** | Individual Practical Database Portfolio — *not* a written essay. Practical evidence + supporting documentation. |
| **Weight** | 40 marks (Continuous Assessment). |
| **Platform** | Submission on LMS + a private GitHub repository. The GitHub link must work for the assessor before LMS submission. |
| **Case study** | Each student picks one realistic organisation (real, simulated, or scenario) and uses it **consistently** across all 5 portfolios. Must be stated clearly at the start of the documentation. |
| **Portfolios (5)** | P1 Database Design & Modelling (7), P2 Query Processing & Optimisation (7), P3 Transactions & Concurrency (7), P4 NoSQL & Advanced Data Models (7), P5 Distributed & Cloud Database Exercise (6). |
| **Final Documentation** | 2–3 page summary, GitHub link, screenshots/evidence, individual reflection, references, AI-use declaration (6 marks). Submitted through the LMS. |
| **Repo structure (suggested in brief)** | `advanced-database-portfolio/{portfolio-1-database-design, portfolio-2-query-optimisation, portfolio-3-transactions-concurrency, portfolio-4-nosql, portfolio-5-distributed-cloud}/README.md`. |
| **Repo must contain** | SQL scripts, schemas, ER diagrams, NoSQL implementations, execution plans/results, screenshots/config/test results, technical documentation and README files. |
| **Progressive commits** | Brief warns: "Waiting until the deadline to upload all files may reduce the evidence of continuous portfolio development." |
| **Individual work** | Discussion allowed; submitted work must be individual. Tools, docs, textbooks, online resources and **AI tools are permitted as learning aids** — but the student remains responsible for understanding, verifying, and explaining everything. |
| **AI-use declaration** | Must state (i) the AI tool used, (ii) what it was used for, (iii) how the output was reviewed, corrected, tested, or verified by the student. |
| **Academic integrity** | Acknowledge all sources, code, datasets, libraries, docs. AI does not remove responsibility for accuracy/originality/understanding. |
| **Verification** | No compulsory viva. Verification relies on submitted evidence, structured documentation, progressive GitHub activity. Lecturer may sample students for a short technical discussion; unclear/copied/inaccessible/suspicious submissions may be invited to verification. |
| **Marking rubric (40)** | Technical correctness 8 · Design quality 6 · Practical implementation 8 · Query & performance analysis 5 · Advanced concepts 5 · Documentation & GitHub organisation 5 · Reflection/evidence of individual understanding 3. |
| **Naming / page limit** | The submission form asks for a folder `Ali_Fatima_2026AMIT0873` containing files named `Ali_Fatima_<DocumentType>`; this portfolio uses the suggested folder names plus a final PDF named `Ali_Fatima_Documentation.pdf` (2–3 pages, deferred until after the student has run everything and captured real results). |

---

## B. Map of the 5 portfolios to the course-note study sessions

The course notes for MIT 8103 cover the standard advanced-database syllabus. The table below maps each portfolio to the study sessions whose concepts are exercised by that portfolio. (Where a concept spans several sessions, all relevant sessions are listed.)

| Portfolio | Title | Marks | Primary course-note study sessions applied |
| --- | --- | --- | --- |
| **P1** | Database Design and Modelling | 7 | **Session: Entity-Relationship Modelling** (entities, attributes, relationships, cardinalities, ER diagrams). **Session: Relational Model & Mapping** (ER → relations, primary/foreign keys, candidate keys). **Session: Normalisation** (1NF, 2NF, 3NF, BCNF; functional dependencies; transitive dependencies). **Session: Integrity Constraints & Triggers** (domain, key, referential; CHECK; triggers; exclusion constraints; `tstzrange` + `btree_gist`). **Session: Physical Design Basics** (data types, sequence vs identity, indexes overview). |
| **P2** | Query Processing and Optimisation | 7 | **Session: SQL for Analytics** (joins, GROUP BY, CTEs, window functions, date/time math). **Session: Query Execution Plans** (`EXPLAIN`, `EXPLAIN ANALYZE`, sequential vs index scan, nested loop vs hash join). **Session: Indexing & Access Methods** (B-tree, GiST, partial indexes, composite indexes, when an index is *not* used). **Session: Performance Tuning** (statistics, ANALYZE, index-only scans, query rewriting, before/after benchmarking). |
| **P3** | Transactions and Concurrency | 7 | **Session: ACID & Transactions** (BEGIN/COMMIT/ROLLBACK, savepoints, deferred constraints). **Session: Isolation Levels** (READ UNCOMMITTED, READ COMMITTED, REPEATABLE READ, SERIALIZABLE; phenomena each prevents). **Session: Locking & MVCC** (row locks, table locks, `SELECT ... FOR UPDATE`, deadlocks, lock wait). **Session: Concurrency Problems** (lost update, dirty read, non-repeatable read, phantom, write skew; overbooking as a phantom/lost-update case). **Session: Serialisability & Snapshot Isolation** (SSI, retry patterns). |
| **P4** | NoSQL and Advanced Data Models | 7 | **Session: NoSQL Foundations & CAP** (document, key-value, column-family, graph; BASE vs ACID). **Session: MongoDB Document Modelling** (embedding vs referencing, schema design, schema validation with `$jsonSchema`). **Session: Aggregation Framework** (`$match`, `$group`, `$unwind`, `$lookup`, `$facet`; pipeline optimisation). **Session: Indexing in MongoDB** (single, compound, ESR rule; `explain()` COLLSCAN vs IXSCAN). **Session: SQL vs NoSQL** (when to pick which; consistency, joins, scaling). |
| **P5** | Distributed and Cloud Database Exercise | 6 | **Session: Partitioning & Sharding** (range, list, hash; declarative partitioning in PostgreSQL; pruning). **Session: Replication** (physical/streaming, synchronous vs asynchronous, primary + read replica; `pg_basebackup`; read-only replica behaviour). **Session: Distributed Transactions & 2PC** (background; why we don't use `postgres_fdw` here). **Session: CAP Theorem & Consistency Models** (CP/AP, eventual consistency, sync vs async replication trade-offs). **Session: Cloud Databases & Data Sovereignty** (managed PostgreSQL/MongoDB, NDPA 2023, residency in Nigeria, extra protection for children's personal data). |
| **Final Documentation** | 2–3 page summary + reflection + AI-use declaration | 6 | **Session: Technical Writing & Documentation** (readme, evidence, references) and **Session: Professional Ethics & AI Use** (academic integrity, AI-use declaration). |

> Note: many concepts overlap (e.g. indexing appears in P2 and P4; CAP appears in P4 and P5). The table lists the *primary* sessions each portfolio demonstrates.

---

## C. Case-study statement (used identically across all 5 portfolios)

> **Organisation:** SplashPoint Swim School (simulated).
> **Business:** A swim school that operates four pools across two Nigerian cities — Wuse and Maitama in Abuja, and Ikoyi and Lekki in Lagos. Each pool has multiple lanes.
> **Users of the database:** front-desk staff (booking and payments), instructors (session delivery and progress notes), guardians/parents (booking for under-18s), adult swimmers (self-booking), and the operations manager (reporting and capacity planning).
> **Major data stored:** pools and lanes; instructors and their certifications; swimmers (with guardians for under-18s); lesson types (private, group, adult-beginner, etc.); lesson sessions (pool + lane + instructor + start/end time); enrolments; payments per lesson or per package; swimmer progress notes (per-session skill assessments and safety incidents) stored in MongoDB.
> **Key operations supported:** enrol a swimmer in a session (atomic with payment); record attendance and progress; report revenue per pool, lane utilisation, swimmers per skill level, instructor workload; ensure no lane is double-booked and no instructor teaches two overlapping sessions; guarantee group sessions never exceed capacity; keep children's personal data inside Nigeria per NDPA 2023.

---

## D. File-map of this portfolio

```
advanced-database-portfolio/
├── README.md                              (repo-level overview, [GitHub link] placeholder)
├── setup.sh                               (installs PostgreSQL 16 + MongoDB 8 in Codespaces)
├── docs/
│   └── 00_brief_summary.md                (this file)
├── portfolio-1-database-design/
│   ├── README.md
│   ├── run_p1.sh
│   ├── er_diagram.mmd                     (Mermaid ER diagram)
│   ├── schema.sql                         (9 tables, 3NF, all constraints, triggers, exclusion)
│   ├── normalisation.md                   (1NF→2NF→3NF walk-through)
│   ├── seed.sql                           (small hand-crafted seed)
│   ├── bulk_generate.py                   (50k+ enrolments, 2 years, realistic ₦ prices)
│   ├── bulk_load.sql                      (\copy loader for the CSVs)
│   └── constraints_test.sql               (every constraint, every test must FAIL)
├── portfolio-2-query-optimisation/
│   ├── README.md
│   ├── run_p2.sh
│   ├── queries.sql                        (6 queries)
│   ├── indexes.sql                        (indexes added AFTER the "before" run)
│   └── explain_results.md                 (how to read the before/after plans; numbers in explain_summary.txt)
├── portfolio-3-transactions-concurrency/
│   ├── README.md
│   ├── run_p3.sh
│   ├── enrol_swimmer.sql                  (enrol_swimmer() transactional function)
│   ├── commit_rollback_demo.sql           (COMMIT and ROLLBACK paths)
│   ├── race_condition_guide.md            (two-terminal guide: bug, fix1 FOR UPDATE, fix2 SERIALIZABLE)
│   ├── isolation_levels.sql               (READ COMMITTED vs REPEATABLE READ vs SERIALIZABLE)
│   └── deadlock_demo.sql                  (AB-BA deadlock)
├── portfolio-4-nosql/
│   ├── README.md
│   ├── run_p4.sh
│   ├── schema_validation.js               ($jsonSchema validator)
│   ├── seed_progress.js                   (40k+ progress-note documents)
│   ├── aggregations.js                    (avg lessons to pass level, struggle areas, per-instructor)
│   ├── indexes.js                         (COLLSCAN → IXSCAN demo)
│   └── sql_vs_nosql.md                    (short comparison)
├── portfolio-5-distributed-cloud/
│   ├── README.md
│   ├── run_p5.sh
│   ├── partition.sql                      (range partition lesson_session by month)
│   ├── replica_setup.sh                   (pg_basebackup + postgresql.conf + pg_hba.conf edits)
│   ├── replica_demo.md                    (replica rejects writes; new rows arrive)
│   └── cloud_architecture.md              (Nigeria residency, NDPA 2023, CAP, sync vs async)
└── (after running everything) Ali_Fatima_Documentation.pdf
```

---

## E. Honesty rules followed in this portfolio

- Every `EXPLAIN ANALYZE` output, timing, MongoDB `explain()` output and screenshot comes from the student's own run (the runners save them to log files).
- No simulated timings, no invented plans, no fabricated screenshots.
- The final 2–3 page PDF (`Ali_Fatima_Documentation.pdf`) is **not** written in this ZIP. It is produced *after* the student has run everything and collected real results.
