// ============================================================================
// schema_validation.js — create the progress_notes collection with a
// $jsonSchema validator. SplashPoint Swim School (Portfolio 4, MIT 8103).
//
// Run:  mongosh splashpoint schema_validation.js
// ============================================================================

db = db.getSiblingDB('splashpoint');

// Drop & recreate so the script is idempotent
try { db.progress_notes.drop(); } catch (e) {}

db.createCollection("progress_notes", {
  validator: {
    $jsonSchema: {
      bsonType: "object",
      required: ["note_id", "swimmer_id", "session_id", "instructor_id",
                 "lesson_date", "level", "skills", "instructor_comment",
                 "safety_incidents"],
      properties: {
        _id:               { bsonType: "objectId" },   // needed because additionalProperties is false
        note_id:           { bsonType: "int", description: "unique note id (= PostgreSQL enrolment_id)" },
        swimmer_name:      { bsonType: "string", description: "copied from PostgreSQL swimmer for display" },
        swimmer_id:        { bsonType: "int", description: "must match swimmer.swimmer_id in PostgreSQL" },
        session_id:        { bsonType: "int", description: "must match lesson_session.session_id in PostgreSQL" },
        instructor_id:     { bsonType: "int" },
        lesson_date:       { bsonType: "date" },
        level:             { enum: ["Tadpole", "Beginner", "Intermediate", "Advanced", "Squad"] },
        skills: {
          bsonType: "array",
          minItems: 1,
          items: {
            bsonType: "object",
            required: ["name", "assessed", "score"],
            properties: {
              name:     { bsonType: "string" },
              assessed: { bsonType: "bool" },
              score:    { bsonType: "int", minimum: 1, maximum: 5 },
              comment:  { bsonType: "string", maxLength: 500 }
            }
          }
        },
        instructor_comment: { bsonType: "string", maxLength: 2000 },
        safety_incidents: {
          bsonType: "array",
          items: {
            bsonType: "object",
            required: ["type", "description", "severity"],
            properties: {
              type:        { enum: ["near_drowning", "slip_fall", "equipment_failure",
                                    "chemical_imbalance", "other"] },
              description: { bsonType: "string", maxLength: 1000 },
              severity:    { enum: ["low", "medium", "high", "critical"] },
              reported_at: { bsonType: "date" }
            }
          }
        },
        created_at: { bsonType: "date" }
      },
      additionalProperties: false
    }
  },
  validationLevel: "strict",
  validationAction: "error"
});

print("Collection progress_notes created with $jsonSchema validator.");
print("");
print("Verify:");
printjson(db.getCollectionInfos({ name: "progress_notes" })[0].options.validator.$jsonSchema.required);

// Prove the validator works: two bad documents must be rejected.
print("");
print("Validator test 1 (level 'Dolphin' is not in the enum) — must be REJECTED:");
try {
  db.progress_notes.insertOne({ note_id: 0, swimmer_id: 1, session_id: 1, instructor_id: 1,
    lesson_date: new Date(), level: "Dolphin", skills: [{ name: "x", assessed: true, score: 3 }],
    instructor_comment: "test", safety_incidents: [] });
  print("  !! accepted (unexpected)");
} catch (e) { print("  REJECTED: " + e.message); }
print("Validator test 2 (score 9 is above the maximum 5) — must be REJECTED:");
try {
  db.progress_notes.insertOne({ note_id: 0, swimmer_id: 1, session_id: 1, instructor_id: 1,
    lesson_date: new Date(), level: "Beginner", skills: [{ name: "x", assessed: true, score: 9 }],
    instructor_comment: "test", safety_incidents: [] });
  print("  !! accepted (unexpected)");
} catch (e) { print("  REJECTED: " + e.message); }
