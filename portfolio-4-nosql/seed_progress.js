// ============================================================================
// seed_progress.js — generate 40,000+ progress-note documents.
// SplashPoint Swim School (Portfolio 4, MIT 8103).
//
// Each note records ONE attended lesson's skill assessments for ONE swimmer,
// built from the real attended enrolments in PostgreSQL (exported by run_p4.sh
// to pg_attended.jsonl). Different levels have different skill checklists.
//
// Run:  via run_p4.sh (it exports pg_attended.jsonl first)
// ============================================================================

db = db.getSiblingDB('splashpoint');

// --- Skill checklists per level ---------------------------------------------
const SKILL_CHECKLISTS = {
  Tadpole: [
    "comfortable putting face in water",
    "kicking with float",
    "blowing bubbles",
    "entering pool safely"
  ],
  Beginner: [
    "floating on front",
    "floating on back",
    "kicking 5m unaided",
    "submerging and retrieving object",
    "safe pool exit"
  ],
  Intermediate: [
    "freestyle 10m",
    "backstroke 10m",
    "rhythmic breathing",
    "treading water 30s",
    "somersault underwater",
    "dive from poolside"
  ],
  Advanced: [
    "freestyle 50m under 45s",
    "backstroke 50m under 50s",
    "breaststroke 25m",
    "butterfly 15m",
    "flip turn",
    "dive from starting block",
    "treading water 2min",
    "rescue tow"
  ],
  Squad: [
    "freestyle 100m under 70s",
    "backstroke 100m under 80s",
    "breaststroke 100m under 95s",
    "butterfly 50m under 35s",
    "individual medley 200m",
    "relay changeover",
    "race pace 50m freestyle",
    "race dive",
    "endurance 800m freestyle",
    "post-race recovery routine"
  ]
};
const LEVELS = ["Tadpole", "Beginner", "Intermediate", "Advanced", "Squad"];

// --- Instructor comments (rotate through these) -----------------------------
const POSITIVE_COMMENTS = [
  "Excellent progress today. Swimmer is confident and responding well to feedback.",
  "Good effort. Maintained technique throughout the lesson.",
  "Strong performance on the harder drills. Keep it up.",
  "Solid session. Swimmer is ready to advance to the next level.",
  "Great attitude and focus. Technique is improving steadily."
];
const MIXED_COMMENTS = [
  "Decent session but lost focus in the second half. Need to work on concentration.",
  "Good on kicking but struggled with breathing coordination. Will revisit next lesson.",
  "Started well but tired towards the end. Need to build endurance.",
  "Understands the theory but execution needs more practice.",
  "Some improvement on form but still hesitates on the dive."
];
const STRUGGLING_COMMENTS = [
  "Foundational skills need reinforcement. Recommend repeating this level next term.",
  "Struggled with the new skill today. Will break it down into smaller steps next lesson.",
  "Confidence in deep water still lacking. Continue supervised practice.",
  "Difficulty coordinating breathing and stroke. Extra practice recommended.",
  "Fatigued quickly today. Suggest a shorter session next time."
];

const SAFETY_TYPES = ["near_drowning", "slip_fall", "equipment_failure", "chemical_imbalance", "other"];
const SAFETY_DESCRIPTIONS = {
  near_drowning: "Swimmer briefly struggled to surface after a dive; instructor intervened immediately.",
  slip_fall: "Swimmer slipped on pool deck near lane 2; no injury.",
  equipment_failure: "Kickboard strap broke during drill; replaced.",
  chemical_imbalance: "Chlorine reading slightly high; pool operator adjusted.",
  other: "Distracted sibling ran near pool; reminded family of pool rules."
};

// --- Source data: the REAL attended lessons from PostgreSQL (Portfolio 1) ---
// run_p4.sh exports them to pg_attended.jsonl first, so every note matches a
// real enrolment: same swimmer, same session, same instructor, same date.
const fs = require('fs');
const path = require('path');
const SRC = path.join(__dirname, 'pg_attended.jsonl');
if (!fs.existsSync(SRC)) {
  throw new Error("pg_attended.jsonl not found — run run_p4.sh (it exports the attended lessons from PostgreSQL first)");
}
const lessons = fs.readFileSync(SRC, 'utf8').split('\n').filter(l => l.trim()).map(l => JSON.parse(l));
print(`Read ${lessons.length} attended lessons exported from PostgreSQL.`);

// --- Helpers ----------------------------------------------------------------
function pick(arr) { return arr[Math.floor(Math.random() * arr.length)]; }
function pickWeighted(items, weights) {
  const total = weights.reduce((a, b) => a + b, 0);
  let r = Math.random() * total;
  for (let i = 0; i < items.length; i++) {
    r -= weights[i];
    if (r <= 0) return items[i];
  }
  return items[items.length - 1];
}

// Starting level and highest level by lesson type and age group
function levelRange(lessonType, ageClass) {
  if (lessonType === 'Toddler Splash') return [0, 1];                       // Tadpole -> Beginner
  if (lessonType === 'Adult Beginner') return [1, 2];                       // Beginner -> Intermediate
  if (lessonType === 'Group Adult')    return [2, 3];                       // Intermediate -> Advanced
  if (lessonType === 'Group Children') return ageClass === 'Teen' ? [2, 4] : [1, 3];
  // Private 1-on-1
  if (ageClass === 'Child') return [1, 3];
  if (ageClass === 'Teen')  return [3, 4];
  return [1, 3];
}

// --- Generate one note per attended lesson ----------------------------------
// Lessons arrive ordered by swimmer, then date, so a swimmer's level rises
// one step roughly every 12 lessons (progression over time).
const BATCH = 2000;
let totalInserted = 0;
let batchDocs = [];
let prevSwimmer = null, k = 0;

for (const L of lessons) {
  if (L.swimmer_id !== prevSwimmer) { prevSwimmer = L.swimmer_id; k = 0; } else { k++; }
  const [lo, hi] = levelRange(L.lesson_type, L.age_class);
  const levelIdx = Math.min(lo + Math.floor(k / 12), hi);
  const level = LEVELS[levelIdx];
  const checklist = SKILL_CHECKLISTS[level];
  const lesson_date = new Date(L.start_time);

  // Each skill assessed independently; harder levels are passed less often,
  // and practice (k) helps a little.
  const passProb = Math.min(0.97, [0.90, 0.80, 0.72, 0.64, 0.56][levelIdx] + 0.01 * (k % 12));
  const skills = checklist.map(name => {
    const assessed = Math.random() < passProb;
    const score = assessed ? (3 + Math.floor(Math.random() * 3))   // 3..5 if passed
                           : (1 + Math.floor(Math.random() * 2));  // 1..2 if not yet
    return { name, assessed, score };
  });

  const passRate = skills.filter(s => s.assessed).length / skills.length;
  const comment = passRate >= 0.85 ? pick(POSITIVE_COMMENTS)
                : passRate >= 0.5  ? pick(MIXED_COMMENTS)
                                   : pick(STRUGGLING_COMMENTS);

  // Safety incidents: usually none; ~2% have one
  const safety_incidents = [];
  if (Math.random() < 0.02) {
    const t = pick(SAFETY_TYPES);
    safety_incidents.push({
      type: t,
      description: SAFETY_DESCRIPTIONS[t],
      severity: pickWeighted(["low","medium","high","critical"], [70, 24, 5, 1]),
      reported_at: lesson_date
    });
  }

  batchDocs.push({
    note_id: L.enrolment_id,
    swimmer_id: L.swimmer_id,
    swimmer_name: L.swimmer_name,
    session_id: L.session_id,
    instructor_id: L.instructor_id,
    lesson_date,
    level,
    skills,
    instructor_comment: comment,
    safety_incidents,
    created_at: new Date(lesson_date.getTime() + 2 * 3600 * 1000)   // written ~2h after the lesson
  });

  if (batchDocs.length >= BATCH) {
    db.progress_notes.insertMany(batchDocs, { ordered: true });
    totalInserted += batchDocs.length;
    if (totalInserted % 10000 === 0) print(`  inserted ${totalInserted} / ${lessons.length}`);
    batchDocs = [];
  }
}
if (batchDocs.length > 0) {
  db.progress_notes.insertMany(batchDocs, { ordered: true });
  totalInserted += batchDocs.length;
}

print(`Done. Total progress_notes documents: ${db.progress_notes.countDocuments()}`);
print(`Distinct swimmers: ${db.progress_notes.distinct("swimmer_id").length}`);
print(`Distinct instructors: ${db.progress_notes.distinct("instructor_id").length}`);
print(`Date range: ${db.progress_notes.find().sort({lesson_date:1}).limit(1).next().lesson_date.toISOString()}  to  ${db.progress_notes.find().sort({lesson_date:-1}).limit(1).next().lesson_date.toISOString()}`);
if (db.progress_notes.countDocuments() < 40000) {
  throw new Error("Fewer than 40,000 notes — run Portfolio 1 first so PostgreSQL has 50k+ enrolments.");
}
