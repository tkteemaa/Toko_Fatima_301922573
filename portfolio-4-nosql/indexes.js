// ============================================================================
// indexes.js — COLLSCAN → IXSCAN demo on progress_notes.
// SplashPoint Swim School (Portfolio 4, MIT 8103).
//
// Query: "show me all progress notes for swimmer 1234 in the last 6 months,
// sorted by lesson_date descending."
//
// Run:  mongosh splashpoint indexes.js
//
// Output files (for your screenshot / paste):
//   index_explain_before.txt   — explain() BEFORE the index
//   index_explain_after.txt    — explain() AFTER the index
// ============================================================================

db = db.getSiblingDB('splashpoint');

// Start clean so re-runs really begin with NO index on these fields
db.progress_notes.dropIndexes();   // keeps the mandatory _id index

const SIX_MONTHS_AGO = new Date();
SIX_MONTHS_AGO.setMonth(SIX_MONTHS_AGO.getMonth() - 6);
// The swimmer with the most lessons in the last 6 months (a "parent opens the app" query)
const busiest = db.progress_notes.aggregate([
  { $match: { lesson_date: { $gte: SIX_MONTHS_AGO } } },
  { $group: { _id: "$swimmer_id", n: { $sum: 1 }, name: { $first: "$swimmer_name" } } },
  { $sort: { n: -1, _id: 1 } }, { $limit: 1 }
]).toArray()[0];
const SWIMMER_ID = busiest._id;
print(`Query: notes for swimmer ${SWIMMER_ID} (${busiest.name}) since ${SIX_MONTHS_AGO.toISOString().slice(0,10)}, newest first`);
print(`Collection size: ${db.progress_notes.countDocuments()} documents`);

// Walk the plan tree: "SORT <- COLLSCAN" or "FETCH <- IXSCAN"
function stages(st) { const out = []; while (st) { out.push(st.stage + (st.indexName ? `(${st.indexName})` : "")); st = st.inputStage; } return out.join(" <- "); }

const query = { swimmer_id: SWIMMER_ID, lesson_date: { $gte: SIX_MONTHS_AGO } };
const sort  = { lesson_date: -1 };

// ----------------------------------------------------------------------------
// BEFORE: no index on (swimmer_id, lesson_date) — expect COLLSCAN
// ----------------------------------------------------------------------------
print("====================================================================");
print("BEFORE: no index. Running explain('executionStats')...");
print("====================================================================");

const explainBefore = db.progress_notes
  .find(query)
  .sort(sort)
  .explain("executionStats");

const beforeStage = explainBefore.executionStats.executionStages;
print(`Plan: ${stages(beforeStage)}`);
print(`totalDocsExamined: ${explainBefore.executionStats.totalDocsExamined}`);
print(`nReturned: ${explainBefore.executionStats.nReturned}`);
print(`executionTimeMillis: ${explainBefore.executionStats.executionTimeMillis}`);

// Also dump the full plan to a file for the screenshot
const fs = require('fs');
const path = require('path');
fs.writeFileSync(
  path.join(__dirname, 'index_explain_before.txt'),
  JSON.stringify(explainBefore, null, 2)
);
print(`Wrote index_explain_before.txt`);

// ----------------------------------------------------------------------------
// Create the compound index — ESR rule: Equality, Sort, Range
//   swimmer_id  = equality
//   lesson_date = sort + range
// ----------------------------------------------------------------------------
print("");
print("====================================================================");
print("Creating index idx_swimmer_lesson_date on (swimmer_id, lesson_date)...");
print("====================================================================");

db.progress_notes.createIndex(
  { swimmer_id: 1, lesson_date: -1 },
  { name: "idx_swimmer_lesson_date" }
);
print("Index created.");

// ----------------------------------------------------------------------------
// AFTER: same query, now with the index — expect IXSCAN
// ----------------------------------------------------------------------------
print("");
print("====================================================================");
print("AFTER: index exists. Running explain('executionStats')...");
print("====================================================================");

const explainAfter = db.progress_notes
  .find(query)
  .sort(sort)
  .explain("executionStats");

const afterStage = explainAfter.executionStats.executionStages;
print(`Plan: ${stages(afterStage)}`);
print(`totalDocsExamined: ${explainAfter.executionStats.totalDocsExamined}`);
print(`nReturned: ${explainAfter.executionStats.nReturned}`);
print(`executionTimeMillis: ${explainAfter.executionStats.executionTimeMillis}`);

fs.writeFileSync(
  path.join(__dirname, 'index_explain_after.txt'),
  JSON.stringify(explainAfter, null, 2)
);
print(`Wrote index_explain_after.txt`);

// ----------------------------------------------------------------------------
// Summary
// ----------------------------------------------------------------------------
print("");
print("====================================================================");
print("SUMMARY (real numbers from this run):");
print("====================================================================");
const fmt = (e) => `plan=${stages(e.executionStats.executionStages)}  keysExamined=${e.executionStats.totalKeysExamined}  docsExamined=${e.executionStats.totalDocsExamined}  nReturned=${e.executionStats.nReturned}  timeMs=${e.executionStats.executionTimeMillis}`;
print(`BEFORE: ${fmt(explainBefore)}`);
print(`AFTER:  ${fmt(explainAfter)}`);

// A second index for the dashboard query in aggregations (struggling skills by level)
db.progress_notes.createIndex({ level: 1, lesson_date: -1 }, { name: "idx_level_date" });
print("");
print("Indexes now on progress_notes:");
db.progress_notes.getIndexes().forEach(ix => print(`  ${ix.name}  ${JSON.stringify(ix.key)}`));
