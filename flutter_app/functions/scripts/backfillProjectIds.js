// One-time backfill: derive employees/{id}.projectIds from the existing
// projects/{id}.memberIds (the pre-existing source of truth) for every
// employee doc that predates the projectIds field. Must run before the new
// firestore.rules go live, since manager/worker scoping reads that field.
//
// Usage:
//   node scripts/backfillProjectIds.js            # dry run, prints the plan
//   node scripts/backfillProjectIds.js --apply     # actually writes

const admin = require("firebase-admin");

const APPLY = process.argv.includes("--apply");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: "dyadespace",
});

const db = admin.firestore();

async function main() {
  const [projectsSnap, employeesSnap] = await Promise.all([
    db.collection("projects").get(),
    db.collection("employees").get(),
  ]);

  // employeeId -> [projectId, ...], derived from each project's memberIds.
  const derived = new Map();
  for (const doc of projectsSnap.docs) {
    const memberIds = doc.data().memberIds || [];
    for (const employeeId of memberIds) {
      if (!derived.has(employeeId)) derived.set(employeeId, []);
      derived.get(employeeId).push(doc.id);
    }
  }

  console.log(`Found ${projectsSnap.size} projects, ${employeesSnap.size} employees.`);

  let toUpdate = 0;
  let alreadyCorrect = 0;
  const batch = db.batch();
  let batchCount = 0;
  const commits = [];

  for (const doc of employeesSnap.docs) {
    const current = doc.data().projectIds;
    const next = derived.get(doc.id) || [];
    const currentSorted = Array.isArray(current) ? [...current].sort() : null;
    const nextSorted = [...next].sort();

    if (currentSorted !== null && JSON.stringify(currentSorted) === JSON.stringify(nextSorted)) {
      alreadyCorrect++;
      continue;
    }

    toUpdate++;
    const name = `${doc.data().firstName || ""} ${doc.data().lastName || ""}`.trim() || doc.id;
    console.log(
      `  ${name} (${doc.id}): ${JSON.stringify(current ?? "<missing>")} -> ${JSON.stringify(next)}`
    );

    if (APPLY) {
      const fields = { projectIds: next };
      if (!Array.isArray(doc.data().fcmTokens)) fields.fcmTokens = [];
      batch.update(doc.ref, fields);
      batchCount++;
      if (batchCount === 400) {
        commits.push(batch.commit());
        batchCount = 0;
      }
    }
  }
  if (APPLY && batchCount > 0) commits.push(batch.commit());
  if (APPLY) await Promise.all(commits);

  console.log(
    `\n${toUpdate} employee doc(s) ${APPLY ? "updated" : "would be updated"}, ${alreadyCorrect} already correct.`
  );
  if (!APPLY && toUpdate > 0) {
    console.log("Dry run only — re-run with --apply to write.");
  }
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
