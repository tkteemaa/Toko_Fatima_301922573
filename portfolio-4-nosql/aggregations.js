// ============================================================================
// aggregations.js — three aggregation pipelines on progress_notes.
// SplashPoint Swim School (Portfolio 4, MIT 8103).
//
// Run:  mongosh splashpoint aggregations.js
// ============================================================================

db = db.getSiblingDB('splashpoint');

print("====================================================================");
print("AGGREGATION 1: Average number of lessons to pass each level");
print("====================================================================");
print("(Per swimmer and level: lessons up to and including the FIRST lesson where");
print(" every skill on the checklist was passed. Then the average per level.)");
print("");

const agg1 = db.progress_notes.aggregate([
  { $sort: { swimmer_id: 1, lesson_date: 1 } },
  { $project: {
      swimmer_id: 1, level: 1,
      all_passed: { $allElementsTrue: [ { $map: { input: "$skills", as: "s", in: "$$s.assessed" } } ] }
  }},
  { $group: { _id: { swimmer: "$swimmer_id", level: "$level" }, results: { $push: "$all_passed" } } },
  { $project: { level: "$_id.level", first_pass: { $indexOfArray: ["$results", true] } } },
  { $match: { first_pass: { $gte: 0 } } },                 // swimmers who have passed this level
  { $group: { _id: "$level",
              swimmers_passed: { $sum: 1 },
              avg_lessons_to_pass: { $avg: { $add: ["$first_pass", 1] } },
              max_lessons_to_pass: { $max: { $add: ["$first_pass", 1] } } } },
  { $project: { _id: 0, level: "$_id", swimmers_passed: 1, max_lessons_to_pass: 1,
                avg_lessons_to_pass: { $round: ["$avg_lessons_to_pass", 2] } } },
  { $addFields: { order: { $indexOfArray: [["Tadpole","Beginner","Intermediate","Advanced","Squad"], "$level"] } } },
  { $sort: { order: 1 } },
  { $project: { order: 0 } }
]).toArray();
printjson(agg1);

print("");
print("====================================================================");
print("AGGREGATION 2: Common struggle areas");
print("(For each skill, % of notes where assessed=false. Top 10.)");
print("====================================================================");
print("");

const agg2 = db.progress_notes.aggregate([
  { $unwind: "$skills" },
  { $group: {
      _id: "$skills.name",
      total_notes: { $sum: 1 },
      failed_notes: { $sum: { $cond: [{ $eq: ["$skills.assessed", false] }, 1, 0] } }
  }},
  { $project: {
      skill: "$_id",
      total_notes: 1,
      failed_notes: 1,
      failure_rate_pct: { $round: [{ $multiply: [{ $divide: ["$failed_notes", "$total_notes"] }, 100] }, 2] }
  }},
  { $match: { total_notes: { $gte: 100 } } },  // ignore skills with too few samples
  { $sort: { failure_rate_pct: -1 } },
  { $limit: 10 }
]).toArray();
printjson(agg2);

print("");
print("====================================================================");
print("AGGREGATION 3: Progress per instructor");
print("(Per instructor: lessons taught, average skill score, % of skills passed, safety incidents)");
print("====================================================================");
print("");

const agg3 = db.progress_notes.aggregate([
  { $project: {
      instructor_id: 1,
      n_skills: { $size: "$skills" },
      n_passed: { $size: { $filter: { input: "$skills", as: "s", cond: "$$s.assessed" } } },
      score_sum: { $sum: "$skills.score" },
      n_incidents: { $size: "$safety_incidents" }
  }},
  { $group: {
      _id: "$instructor_id",
      lessons: { $sum: 1 },
      skills_assessed: { $sum: "$n_skills" },
      skills_passed: { $sum: "$n_passed" },
      score_total: { $sum: "$score_sum" },
      safety_incidents: { $sum: "$n_incidents" }
  }},
  { $project: {
      _id: 0, instructor_id: "$_id", lessons: 1, safety_incidents: 1,
      avg_skill_score: { $round: [{ $divide: ["$score_total", "$skills_assessed"] }, 2] },
      pass_rate_pct:   { $round: [{ $multiply: [{ $divide: ["$skills_passed", "$skills_assessed"] }, 100] }, 1] }
  }},
  { $sort: { pass_rate_pct: -1 } }
]).toArray();
print("Top 5 instructors by skill pass rate:");
printjson(agg3.slice(0, 5));
print("Bottom 3 instructors by skill pass rate:");
printjson(agg3.slice(-3));
print(`(${agg3.length} instructors total)`);

print("");
print("====================================================================");
print("AGGREGATION 3b: Safety incidents per instructor (summary)");
print("====================================================================");
print("");

const agg3b = db.progress_notes.aggregate([
  { $unwind: "$safety_incidents" },
  { $group: {
      _id: "$instructor_id",
      total_incidents: { $sum: 1 },
      critical_incidents: { $sum: { $cond: [{ $eq: ["$safety_incidents.severity", "critical"] }, 1, 0] } },
      high_incidents:     { $sum: { $cond: [{ $eq: ["$safety_incidents.severity", "high"] }, 1, 0] } }
  }},
  { $sort: { total_incidents: -1 } }
]).toArray();
printjson(agg3b);

print("");
print("====================================================================");
print("DONE.");
print("====================================================================");
