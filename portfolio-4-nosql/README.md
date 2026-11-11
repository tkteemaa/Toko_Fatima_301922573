# Portfolio 4 — NoSQL and Advanced Data Models

**Student:** Fatima Toko Ali · 2026/A/MIT/0873
**Case study:** SplashPoint Swim School (simulated).
**Study session covered:** NoSQL foundations & CAP, MongoDB document modelling, aggregation framework, indexing in MongoDB, SQL vs NoSQL.

---

## What this portfolio demonstrates

MongoDB stores the **swimmer progress notes** — the unstructured / semi-structured data that does not fit cleanly in a relational schema. Each document records one lesson's skill assessments, instructor comments, and any safety incidents. Different swim levels have different skill checklists (e.g. a Toddler Splash lesson checks "comfortable putting face in water"; an Advanced lesson checks "freestyle 50m under 45 seconds").

Concretely:

1. **`schema_validation.js`** — a `$jsonSchema` validator (it also inserts two bad documents to prove they are rejected) on the `progress_notes` collection. Documents must have: `swimmer_id` (int), `session_id` (int), `instructor_id` (int), `lesson_date` (date), `level` (enum), `skills` (array of `{name, assessed, score, comment}`), `instructor_comment` (string), `safety_incidents` (array of `{type, description, severity}` — may be empty).

2. **`seed_progress.js`** — creates **one progress note per real attended lesson** in PostgreSQL (≈50,000). `run_p4.sh` first exports the attended enrolments (swimmer, session, instructor, date, lesson type) to `pg_attended.jsonl`, so every note matches a real booking from Portfolio 1 — no invented swimmers or sessions. A swimmer's level rises roughly every 12 lessons; each level has its own skill checklist.

3. **`aggregations.js`** — three aggregation pipelines:
   - **Average number of lessons to pass each level** — per swimmer and level, the lessons up to the first one where every skill was passed (`$allElementsTrue`, `$indexOfArray`), averaged per level.
   - **Common struggle areas** — for each skill, the % of notes where `assessed == false`. Sorted descending, top 10.
   - **Progress per instructor** — lessons taught, average skill score, % of skills passed, safety incidents (plus 3b: incidents by severity).

4. **`indexes.js`** — drops old indexes, runs "this swimmer's notes for the last 6 months, newest first" with NO index (`SORT <- COLLSCAN`), creates the compound index `(swimmer_id, lesson_date)` following the ESR rule, and re-runs it (`FETCH <- IXSCAN`). Prints docs examined and time for both and saves the full `explain()` to `index_explain_before.txt` / `index_explain_after.txt`.

5. **`sql_vs_nosql.md`** — a short comparison of when to pick SQL (PostgreSQL) vs NoSQL (MongoDB) for SplashPoint and similar businesses.

---

## Why MongoDB for swimmer progress notes?

- **Per-level skill checklists** — a Toddler Splash lesson checks ~3 skills; an Advanced lesson checks ~8 skills. A fixed SQL table needs either many nullable columns or a separate `skill_assessment` table with a JOIN. MongoDB embeds the skills array directly in the document.
- **Free-form instructor comments** — instructors write a paragraph per lesson. Storing this as TEXT in SQL is fine, but the *combination* of structured skills + free-form comments + variable-length safety incidents is naturally a document.
- **Schema evolution** — adding a new skill ("butterfly kick") to the Advanced checklist does not require an `ALTER TABLE`; just include it in new documents.
- **Read pattern** — the app almost always reads the **entire progress note** at once (instructor's dashboard). Embedding gives single-document reads, no JOINs.

---

## Files

| File | Purpose |
| --- | --- |
| `schema_validation.js` | Creates the `splashpoint.progress_notes` collection with a `$jsonSchema` validator. |
| `seed_progress.js` | One note per attended lesson exported from PostgreSQL (40,000+). |
| `aggregations.js` | Three aggregation pipelines. Run with `mongosh splashpoint aggregations.js`. |
| `indexes.js` | COLLSCAN → IXSCAN demo. Writes `index_explain_before.txt` and `index_explain_after.txt`. |
| `sql_vs_nosql.md` | Short SQL vs NoSQL comparison. |
| `run_p4.sh` | Starts mongod if needed, exports `pg_attended.jsonl` from PostgreSQL, then runs the four scripts. |

---

## Run it (Codespaces)

```bash
bash portfolio-4-nosql/run_p4.sh 2>&1 | tee p4_output.log
```

## What to screenshot

1. The two `REJECTED: Document failed validation` lines (validator works).
2. `Done. Total progress_notes documents: …` (40,000+).
3. Aggregation 1 and 2 output.
4. The index SUMMARY: `SORT <- COLLSCAN … docsExamined=…` vs `FETCH <- IXSCAN(idx_swimmer_lesson_date) …`.

---

## Plain-English explanation

PostgreSQL is great for the **booking and payment** side of SplashPoint (Portfolio 1–3) — those relationships are strict, transactional, and benefit from exclusion constraints. But the **progress notes** that instructors write after each lesson are different:

- Each swim level has a **different checklist** of skills. A toddler is assessed on "comfortable putting face in water" and "kicking with float"; a squad swimmer is assessed on "freestyle 50m under 45 seconds" and "backstroke flip turn". Encoding this in SQL needs either lots of nullable columns or a separate `skill_assessment` table that gets JOINed on every read.
- Each note has **free-form text** (the instructor's paragraph), a variable-length list of **safety incidents** (usually empty, occasionally several), and possibly attached media references in future.
- The read pattern is **always the whole document** — the instructor's dashboard shows the entire note.

This is the canonical case for a **document database**. We embed the skills array, the comments, and the safety incidents in a single MongoDB document. Adding a new skill to a level's checklist is a schema change in the *application*, not an `ALTER TABLE`.

The **aggregation framework** lets us ask business questions like "what do swimmers struggle with most?" (unwind `skills`, group by `skills.name`, % with `assessed == false`) without writing JOINs. Adding an **index** on `(swimmer_id, lesson_date)` turns a `COLLSCAN` (collection scan — read every document) into an `IXSCAN` (read only the index entries that match), giving the same kind of speedup we saw in Portfolio 2 with PostgreSQL indexes.
