// DyadeSpace Firestore + Storage rules tests (audit tasks 2-7).
//
// Run with: npm test   (from functions/ — boots the Firestore and
// Storage emulators and runs this file with node --test).
// Uses Node's built-in node:test + assert, no extra runner.
//
// NOTE: @firebase/rules-unit-testing v6 hands out COMPAT SDK
// instances (context.firestore() / .storage()), so all calls
// below use the compat API (db.collection(..).doc(..).get(),
// .set(), .update(), .delete()) — the modular doc()/getDoc()
// from 'firebase/firestore' reject compat instances.
//
// NOTE: run via `npm test`, which sets
// JDK_JAVA_OPTIONS=-Djava.net.preferIPv4Stack=true for the
// emulators. Without it the Firestore emulator's internal
// gRPC fails on this VM's IPv6 loopback and every request
// answers 503 "Network closed for unknown reason".
//
// Personas seeded before every test (users docs):
//   admin-uid      role admin,   active true
//   manager-uid    role manager, active true
//   worker-uid     role worker,  active true  (email worker@test.local)
//   worker2-uid    role worker,  active true
//   deactivated-uid   role worker, active false
//   dead-admin-uid    role admin,  active false
// A "fresh" account (fresh-uid, newbie@test.local) has an Auth
// identity but NO users doc yet — the sign-up state.

import { test, before, beforeEach, after } from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} from '@firebase/rules-unit-testing';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const RULES_PATH = path.join(__dirname, '..', '..', 'firestore.rules');
const RULES = fs.readFileSync(RULES_PATH, 'utf8');
const STORAGE_RULES_PATH = path.join(__dirname, '..', '..', 'storage.rules');
const STORAGE_RULES = fs.readFileSync(STORAGE_RULES_PATH, 'utf8');

const ADMIN = { uid: 'admin-uid', email: 'admin@test.local' };
const MANAGER = { uid: 'manager-uid', email: 'manager@test.local' };
const WORKER = { uid: 'worker-uid', email: 'worker@test.local' };
const WORKER2 = { uid: 'worker2-uid', email: 'worker2@test.local' };
const DEACTIVATED = { uid: 'deactivated-uid', email: 'deactivated@test.local' };
const DEAD_ADMIN = { uid: 'dead-admin-uid', email: 'dead-admin@test.local' };
const FRESH = { uid: 'fresh-uid', email: 'newbie@test.local' };

let testEnv;

function dbFor(user) {
  return testEnv.authenticatedContext(user.uid, { email: user.email }).firestore();
}
function dbUnauthenticated() {
  return testEnv.unauthenticatedContext().firestore();
}
function storageFor(user) {
  return testEnv.authenticatedContext(user.uid, { email: user.email }).storage();
}
function storageUnauthenticated() {
  return testEnv.unauthenticatedContext().storage();
}
// Compat Storage API (what rules-unit-testing returns): ref(path).put(bytes, {contentType}).
function putBytes(storage, path, contentType = 'image/jpeg') {
  return storage.ref(path).put(new Uint8Array([1, 2, 3]), { contentType });
}

function validEntry(overrides = {}) {
  return {
    userId: WORKER.uid,
    userName: 'Worker',
    siteId: 'site-1',
    siteName: 'Maple Court',
    date: '2026-11-14',
    clockInAt: new Date(),
    clockInVerified: false,
    flagged: false,
    clockOutAt: null,
    ...overrides,
  };
}

async function seed() {
  // withSecurityRulesDisabled returns nothing and destroys the
  // context when the callback returns, so all seeding writes
  // must happen inside the callback.
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await db.collection('users').doc(ADMIN.uid).set({
      name: 'Sam', email: ADMIN.email, role: 'admin', active: true,
    });
    await db.collection('users').doc(MANAGER.uid).set({
      name: 'Alex', email: MANAGER.email, role: 'manager', active: true,
    });
    await db.collection('users').doc(WORKER.uid).set({
      name: 'Worker', email: WORKER.email, role: 'worker', active: true,
    });
    await db.collection('users').doc(WORKER2.uid).set({
      name: 'Worker2', email: WORKER2.email, role: 'worker', active: true,
    });
    await db.collection('users').doc(DEACTIVATED.uid).set({
      name: 'Deactivated', email: DEACTIVATED.email, role: 'worker', active: false,
    });
    await db.collection('users').doc(DEAD_ADMIN.uid).set({
      name: 'Dead Admin', email: DEAD_ADMIN.email, role: 'admin', active: false,
    });
    await db.collection('sites').doc('site-1').set({ name: 'Maple Court' });
    await db.collection('teams').doc('team-1').set({ memberIds: [WORKER.uid] });
    await db.collection('invites').doc('invite-newbie').set({
      email: FRESH.email, status: 'pending', role: 'worker',
    });
    await db.collection('invites').doc('invite-worker').set({
      email: WORKER.email, status: 'pending', role: 'worker',
    });
    await db.collection('invites').doc('invite-other').set({
      email: 'other@test.local', status: 'pending', role: 'worker',
    });
    await db.collection('timeEntries').doc('entry-open').set(validEntry());
    await db.collection('timeEntries').doc('entry-closed').set(validEntry({
      clockOutAt: new Date(),
    }));
    await db.collection('timeEntries').doc('entry-worker2-open').set(validEntry({
      userId: WORKER2.uid,
    }));
    await db.collection('conversations').doc('dm-worker-uid-worker2-uid').set({
      type: 'dm', participantIds: [WORKER.uid, WORKER2.uid],
    });
    await db.collection('tasks').doc('task-1').set({
      assigneeId: WORKER.uid, status: 'todo', materialsOnSite: false,
    });
    await db.collection('tasks').doc('task-2').set({
      assigneeIds: [WORKER.uid, WORKER2.uid], status: 'todo',
      title: 'Paint the hallway', dueDate: new Date('2026-11-20'),
      stageId: 'stage-1', dependsOnTaskId: null, unitId: 'unit-1',
      notes: 'Two coats', materialsOnSite: false,
    });
    await db.collection('tasks').doc('task-3').set({
      assigneeIds: [WORKER2.uid], status: 'todo', materialsOnSite: false,
    });
    await db.collection('tasks').doc('task-4').set({
      assigneeIds: [], status: 'todo', materialsOnSite: false,
    });
    await db.collection('materialRequests').doc('req-requested').set({
      requesterId: WORKER.uid, requesterName: 'Worker', siteId: 'site-1',
      item: 'Cement', quantity: 2, status: 'requested', createdAt: new Date(),
    });
    await db.collection('materialRequests').doc('req-approved').set({
      requesterId: WORKER.uid, requesterName: 'Worker', siteId: 'site-1',
      item: 'Paint', quantity: 1, status: 'approved', createdAt: new Date(),
    });
    await db.collection('materialRequests').doc('req-worker2').set({
      requesterId: WORKER2.uid, requesterName: 'Worker2', siteId: 'site-1',
      item: 'Nails', quantity: 5, status: 'requested', createdAt: new Date(),
    });
    await db.collection('roadmap_templates').doc('tpl-worker').set({
      name: 'Worker template', createdBy: WORKER.uid, createdAt: new Date(),
      stages: [{ name: 'Foundation', order: 1, tasks: [] }],
    });
    await db.collection('roadmap_templates').doc('tpl-admin').set({
      name: 'Admin template', createdBy: ADMIN.uid, createdAt: new Date(),
      stages: [{ name: 'Foundation', order: 1, tasks: [] }],
    });
    await db.collection('runs').doc('run-1').set({
      driverId: WORKER.uid, date: '2026-11-14',
      stops: [{ id: 'stop-1', status: 'pending' }],
      odometerStart: null, odometerEnd: null,
    });
    await db.collection('notifications').doc('notif-worker').set({
      userId: WORKER.uid, read: false, title: 'Task unlocked',
    });
    await db.collection('notifications').doc('notif-worker2').set({
      userId: WORKER2.uid, read: false, title: 'Task unlocked',
    });
    await db.collection('settings').doc('eodReport').set({
      channel: 'both', time: '18:00', emailTransportReady: false,
    });
  });
}

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: 'dyadespace-rules-test',
    firestore: { rules: RULES },
    storage: { rules: STORAGE_RULES },
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
  await testEnv.clearStorage();
  await seed();
});

after(async () => {
  await testEnv.cleanup();
});

// ---------------------------------------------------------------- [2] isMember
test('[2] fresh account (no users doc) cannot read a site', async () => {
  await assertFails(dbFor(FRESH).collection('sites').doc('site-1').get());
});

test('[2] fresh account cannot read another user profile', async () => {
  await assertFails(dbFor(FRESH).collection('users').doc(ADMIN.uid).get());
});

test('[2] unauthenticated read is denied', async () => {
  await assertFails(dbUnauthenticated().collection('sites').doc('site-1').get());
});

test('[2] active worker can read a site and another member profile', async () => {
  await assertSucceeds(dbFor(WORKER).collection('sites').doc('site-1').get());
  await assertSucceeds(dbFor(WORKER).collection('users').doc(ADMIN.uid).get());
});

test('[2] deactivated worker cannot read or write anything', async () => {
  await assertFails(dbFor(DEACTIVATED).collection('sites').doc('site-1').get());
  await assertFails(dbFor(DEACTIVATED).collection('materialRequests').doc('req-x').set({
    requesterId: DEACTIVATED.uid,
    requesterName: 'Deactivated',
    siteId: 'site-1',
    item: 'plaster',
    quantity: 1,
    status: 'requested',
    createdAt: new Date(),
  }));
});

test('[2] deactivated admin loses admin powers', async () => {
  await assertFails(dbFor(DEAD_ADMIN).collection('sites').doc('site-1').get());
  await assertFails(dbFor(DEAD_ADMIN).collection('invites').get());
});

test('[2] fresh account can create its own users doc, but no one else\'s', async () => {
  await assertSucceeds(dbFor(FRESH).collection('users').doc(FRESH.uid).set({
    name: 'Newbie', email: FRESH.email, role: 'worker', active: true,
  }));
  await assertFails(dbFor(FRESH).collection('users').doc('someone-else').set({
    name: 'Nope', email: 'nope@test.local', role: 'worker', active: true,
  }));
});

test('[2] missing-DM probe still works for a member, not for a stranger', async () => {
  // dm_worker-uid_fresh-uid does not exist; worker-uid is in its id.
  // (Real DM ids are dm_<uidA>_<uidB> — '_' separators; the uids
  // themselves contain '-' but never '_', so the split is exact.)
  await assertSucceeds(
    dbFor(WORKER).collection('conversations').doc('dm_worker-uid_fresh-uid').get(),
  );
  await assertFails(
    dbFor(WORKER2).collection('conversations').doc('dm_worker-uid_fresh-uid').get(),
  );
});

test('[2] missing team-channel probe still works for a team member only', async () => {
  // team_team-1 conversation does not exist; worker-uid is on teams/team-1.
  await assertSucceeds(
    dbFor(WORKER).collection('conversations').doc('team_team-1').get(),
  );
  await assertFails(
    dbFor(WORKER2).collection('conversations').doc('team_team-1').get(),
  );
});

// ---------------------------------------------------------------- [3] users update
test('[3] worker self-update keeping role+active unchanged succeeds', async () => {
  await assertSucceeds(
    dbFor(WORKER).collection('users').doc(WORKER.uid).update({ name: 'Worker Renamed' }),
  );
});

test('[3] worker cannot make themselves admin', async () => {
  await assertFails(
    dbFor(WORKER).collection('users').doc(WORKER.uid).update({ role: 'admin' }),
  );
});

test('[3] worker cannot flip their own active flag', async () => {
  await assertFails(
    dbFor(WORKER).collection('users').doc(WORKER.uid).update({ active: false }),
  );
});

test('[3] deactivated worker cannot flip their own active back to true', async () => {
  await assertFails(
    dbFor(DEACTIVATED).collection('users').doc(DEACTIVATED.uid).update({ active: true }),
  );
});

test('[3] admin can still change a worker role', async () => {
  await assertSucceeds(
    dbFor(ADMIN).collection('users').doc(WORKER.uid).update({ role: 'manager' }),
  );
});

// ------------------------------------------------- [3b] users delete
// Self-service account deletion: a member may delete their OWN
// users doc (and only their own). Deleting it locks oneself
// out (isMember() goes false) but touches nobody else.
test('[3b] worker can delete their own users doc', async () => {
  await assertSucceeds(
    dbFor(WORKER).collection('users').doc(WORKER.uid).delete(),
  );
});

test('[3b] worker cannot delete another worker\'s doc', async () => {
  await assertFails(
    dbFor(WORKER).collection('users').doc(WORKER2.uid).delete(),
  );
});

test('[3b] deactivated worker cannot delete their own doc', async () => {
  await assertFails(
    dbFor(DEACTIVATED).collection('users').doc(DEACTIVATED.uid).delete(),
  );
});

test('[3b] admin can still delete a worker\'s doc (offboarding)', async () => {
  await assertSucceeds(
    dbFor(ADMIN).collection('users').doc(WORKER.uid).delete(),
  );
});

test('[3b] unauthenticated cannot delete a users doc', async () => {
  await assertFails(
    dbUnauthenticated().collection('users').doc(WORKER.uid).delete(),
  );
});

// ------------------------------------------------------------- [4] timeEntries
test('[4] owner can create a valid entry (verified/flagged false, no hours)', async () => {
  await assertSucceeds(
    dbFor(WORKER).collection('timeEntries').doc('entry-new').set(validEntry()),
  );
});

test('[4] clock-in 9 minutes ago is accepted (window, not strict equality)', async () => {
  await assertSucceeds(dbFor(WORKER).collection('timeEntries').doc('entry-9min').set(validEntry({
    clockInAt: new Date(Date.now() - 9 * 60 * 1000),
  })));
});

// Offline clock-in (P0-9): the client writes `queuedAt` (the
// client time of the tap) on every create, and the create is
// accepted when clockInAt is within 2 minutes of queuedAt,
// queuedAt is not in the future, and queuedAt is at most 24
// hours before the server time — so a tap made with no signal
// that syncs later is not rejected by the 10-minute window.
test('[4] offline queued clock-in (25 minutes ago, queuedAt at tap) is accepted', async () => {
  await assertSucceeds(dbFor(WORKER).collection('timeEntries').doc('entry-queued').set(validEntry({
    clockInAt: new Date(Date.now() - 25 * 60 * 1000),
    queuedAt: new Date(Date.now() - 25 * 60 * 1000),
  })));
});

test('[4] offline queued clock-in older than 24 hours is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-x').set(validEntry({
    clockInAt: new Date(Date.now() - 25 * 60 * 60 * 1000),
    queuedAt: new Date(Date.now() - 25 * 60 * 60 * 1000),
  })));
});

test('[4] queued clock-in with clockInAt more than 2 minutes before queuedAt is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-x').set(validEntry({
    clockInAt: new Date(Date.now() - 30 * 60 * 1000),
    queuedAt: new Date(Date.now() - 5 * 60 * 1000),
  })));
});

test('[4] queued clock-in with queuedAt in the future is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-x').set(validEntry({
    clockInAt: new Date(),
    queuedAt: new Date(Date.now() + 5 * 60 * 1000),
  })));
});

test('[4] forged entry with clockInVerified=true is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-x').set(validEntry({
    clockInVerified: true,
  })));
});

test('[4] forged entry with flagged=true is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-x').set(validEntry({
    flagged: true,
  })));
});

test('[4] forged entry carrying hours is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-x').set(validEntry({
    hours: 8,
  })));
});

test('[4] backdated entry (1 hour ago) is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-x').set(validEntry({
    clockInAt: new Date(Date.now() - 60 * 60 * 1000),
  })));
});

test('[4] future clock-in is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-x').set(validEntry({
    clockInAt: new Date(Date.now() + 60 * 1000),
  })));
});

test('[4] entry for another user is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-x').set(validEntry({
    userId: WORKER2.uid,
  })));
});

test('[4] owner clock-out changes ONLY clockOutAt on an open entry', async () => {
  await assertSucceeds(dbFor(WORKER).collection('timeEntries').doc('entry-open').update({
    clockOutAt: new Date(),
  }));
});

test('[4] owner clock-out touching another field is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-open').update({
    clockOutAt: new Date(),
    flagged: true,
  }));
});

test('[4] owner cannot clock out an already-closed entry', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-closed').update({
    clockOutAt: new Date(),
  }));
});

// [4] (audit fix) admin/manager corrections are restricted to the
// site and the times — hours / verified / flagged are computed
// server-side and can no longer be set from the client.
test('[4] admin can NO LONGER set hours/verified directly from the client', async () => {
  await assertFails(dbFor(ADMIN).collection('timeEntries').doc('entry-open').update({
    hours: 7.5,
    clockInVerified: true,
  }));
  await assertFails(dbFor(ADMIN).collection('timeEntries').doc('entry-open').update({
    userId: WORKER2.uid,
  }));
});

test('[4] admin CAN still correct an entry\'s site and times', async () => {
  await assertSucceeds(dbFor(ADMIN).collection('timeEntries').doc('entry-open').update({
    siteId: 'site-1',
    siteName: 'Maple Court',
    date: '2026-11-14',
    clockInAt: new Date(),
    clockOutAt: new Date(),
  }));
  await assertSucceeds(dbFor(MANAGER).collection('timeEntries').doc('entry-open').update({
    date: '2026-11-15',
    clockInAt: new Date(Date.now() - 60 * 1000),
  }));
});

test('[4] time entry delete stays denied for everyone', async () => {
  await assertFails(dbFor(ADMIN).collection('timeEntries').doc('entry-open').delete());
});

test('[4] entry with auto:true (auto clock-in) creates OK', async () => {
  await assertSucceeds(
    dbFor(WORKER).collection('timeEntries').doc('entry-auto').set(validEntry({
      auto: true,
    })),
  );
});

test('[4] owner clock-out may record the clock-out coordinates', async () => {
  await assertSucceeds(dbFor(WORKER).collection('timeEntries').doc('entry-open').update({
    clockOutAt: new Date(),
    clockOutLat: 45.00,
    clockOutLng: -73.00,
  }));
});

// ------------------------------------------------------- [4b] breadcrumbs
// Route trail: one GPS point per open entry, written by the
// foreground tracking service while clocked in.
test('[4b] owner can add a breadcrumb to their own OPEN entry', async () => {
  await assertSucceeds(dbFor(WORKER).collection('timeEntries').doc('entry-open').collection('breadcrumbs').add({
    lat: 45.00, lng: -73.00, at: new Date(),
  }));
});

test('[4b] owner cannot add a breadcrumb to a CLOSED entry', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-closed').collection('breadcrumbs').add({
    lat: 45.00, lng: -73.00, at: new Date(),
  }));
});

test('[4b] worker cannot add a breadcrumb to another worker\'s entry', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-worker2-open').collection('breadcrumbs').add({
    lat: 45.00, lng: -73.00, at: new Date(),
  }));
});

test('[4b] breadcrumb without coordinates is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-open').collection('breadcrumbs').add({
    lng: -73.00, at: new Date(),
  }));
});

test('[4b] admin can read any worker\'s breadcrumbs, worker cannot read another\'s', async () => {
  const ref = dbFor(WORKER).collection('timeEntries').doc('entry-open').collection('breadcrumbs');
  const snap = await assertSucceeds(ref.add({
    lat: 45.00, lng: -73.00, at: new Date(),
  }));
  await assertSucceeds(dbFor(ADMIN).collection('timeEntries').doc('entry-open').collection('breadcrumbs').doc(snap.id).get());
  await assertFails(dbFor(WORKER2).collection('timeEntries').doc('entry-open').collection('breadcrumbs').doc(snap.id).get());
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-open').collection('breadcrumbs').doc(snap.id).update({ lat: 0 }));
  await assertFails(dbFor(ADMIN).collection('timeEntries').doc('entry-open').collection('breadcrumbs').doc(snap.id).delete());
});

// ------------------------------------------------------- [4c] siteVisits
// Site visits: one doc per site stayed at during an entry
// (10 continuous minutes inside the fence). Owner-only
// create while the entry is open, close-only update, never
// deleted.
function validVisit(overrides = {}) {
  return {
    siteId: 'site-1',
    siteName: 'Maple Court',
    arrivedAt: new Date(),
    leftAt: null,
    durationMinutes: null,
    ...overrides,
  };
}

test('[4c] owner can add a visit to their own OPEN entry', async () => {
  await assertSucceeds(dbFor(WORKER).collection('timeEntries').doc('entry-open').collection('siteVisits').add(validVisit()));
});

test('[4c] owner cannot add a visit to a CLOSED entry', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-closed').collection('siteVisits').add(validVisit()));
});

test('[4c] worker cannot add a visit to another worker\'s entry', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-worker2-open').collection('siteVisits').add(validVisit()));
});

test('[4c] visit with a departure already set at create is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-open').collection('siteVisits').add(validVisit({
    leftAt: new Date(),
  })));
});

test('[4c] owner can close their own open visit, nothing else', async () => {
  const ref = dbFor(WORKER).collection('timeEntries').doc('entry-open').collection('siteVisits');
  const snap = await assertSucceeds(ref.add(validVisit()));
  const now = new Date();
  await assertSucceeds(ref.doc(snap.id).update({ leftAt: now, durationMinutes: 42 }));
  // Already closed: a second close is refused.
  await assertFails(ref.doc(snap.id).update({ leftAt: now, durationMinutes: 43 }));
  // Changing the arrival is refused.
  await assertFails(ref.doc(snap.id).update({ arrivedAt: now }));
});

test('[4c] admin can read any worker\'s visits, worker cannot read another\'s, nobody deletes', async () => {
  const ref = dbFor(WORKER).collection('timeEntries').doc('entry-open').collection('siteVisits');
  const snap = await assertSucceeds(ref.add(validVisit()));
  await assertSucceeds(dbFor(ADMIN).collection('timeEntries').doc('entry-open').collection('siteVisits').doc(snap.id).get());
  await assertFails(dbFor(WORKER2).collection('timeEntries').doc('entry-open').collection('siteVisits').doc(snap.id).get());
  await assertFails(dbFor(ADMIN).collection('timeEntries').doc('entry-open').collection('siteVisits').doc(snap.id).delete());
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-open').collection('siteVisits').doc(snap.id).delete());
});

// ---------------------------------------------------------------- [4d] tasks: multi-assignee updates
test('[4d] worker in assigneeIds can update their task', async () => {
  await assertSucceeds(dbFor(WORKER).collection('tasks').doc('task-2').update({ status: 'inProgress' }));
  await assertSucceeds(dbFor(WORKER2).collection('tasks').doc('task-2').update({ status: 'inProgress' }));
});

test('[4d] worker NOT in assigneeIds cannot update the task', async () => {
  await assertFails(dbFor(WORKER).collection('tasks').doc('task-3').update({ status: 'inProgress' }));
});

test('[4d] old-style single assigneeId still lets that worker update', async () => {
  await assertSucceeds(dbFor(WORKER).collection('tasks').doc('task-1').update({ status: 'inProgress' }));
  await assertFails(dbFor(WORKER2).collection('tasks').doc('task-1').update({ status: 'inProgress' }));
});

test('[4d] nobody but admin/manager can update an unassigned task', async () => {
  await assertFails(dbFor(WORKER).collection('tasks').doc('task-4').update({ status: 'inProgress' }));
  await assertFails(dbFor(WORKER2).collection('tasks').doc('task-4').update({ status: 'inProgress' }));
  await assertSucceeds(dbFor(ADMIN).collection('tasks').doc('task-4').update({ status: 'inProgress' }));
});

// ---------------------------------------------------------------- [4e] material request deletes
test('[4e] admin can delete any material request', async () => {
  await assertSucceeds(dbFor(ADMIN).collection('materialRequests').doc('req-approved').delete());
});

test('[4e] manager can delete any material request', async () => {
  await assertSucceeds(dbFor(MANAGER).collection('materialRequests').doc('req-requested').delete());
});

test('[4e] requester can delete their own still-requested request', async () => {
  await assertSucceeds(dbFor(WORKER).collection('materialRequests').doc('req-requested').delete());
});

test('[4e] requester cannot delete their own decided request', async () => {
  await assertFails(dbFor(WORKER).collection('materialRequests').doc('req-approved').delete());
});

test('[4e] worker cannot delete another worker’s request', async () => {
  await assertFails(dbFor(WORKER).collection('materialRequests').doc('req-worker2').delete());
});

test('[4e] unauthenticated cannot delete a material request', async () => {
  await assertFails(dbUnauthenticated().collection('materialRequests').doc('req-requested').delete());
});

// ---------------------------------------------------------------- [4f] roadmap templates
test('[4f] active worker can read a roadmap template', async () => {
  await assertSucceeds(dbFor(WORKER).collection('roadmap_templates').doc('tpl-admin').get());
});

test('[4f] unauthenticated cannot read a roadmap template', async () => {
  await assertFails(dbUnauthenticated().collection('roadmap_templates').doc('tpl-admin').get());
});

test('[4f] deactivated worker cannot read a roadmap template', async () => {
  await assertFails(dbFor(DEACTIVATED).collection('roadmap_templates').doc('tpl-admin').get());
});

test('[4f] worker cannot create a roadmap template', async () => {
  await assertFails(dbFor(WORKER).collection('roadmap_templates').doc('tpl-new').set({
    name: 'New', createdBy: WORKER.uid, createdAt: new Date(), stages: [],
  }));
});

test('[4f] admin can create a roadmap template', async () => {
  await assertSucceeds(dbFor(ADMIN).collection('roadmap_templates').doc('tpl-new').set({
    name: 'New', createdBy: ADMIN.uid, createdAt: new Date(), stages: [],
  }));
});

test('[4f] manager can create a roadmap template', async () => {
  await assertSucceeds(dbFor(MANAGER).collection('roadmap_templates').doc('tpl-new').set({
    name: 'New', createdBy: MANAGER.uid, createdAt: new Date(), stages: [],
  }));
});

test('[4f] template cannot be updated, even by an admin', async () => {
  await assertFails(dbFor(ADMIN).collection('roadmap_templates').doc('tpl-admin').update({
    name: 'Renamed',
  }));
});

test('[4f] admin can delete any roadmap template', async () => {
  await assertSucceeds(dbFor(ADMIN).collection('roadmap_templates').doc('tpl-worker').delete());
});

test('[4f] worker who created a template can delete it', async () => {
  await assertSucceeds(dbFor(WORKER).collection('roadmap_templates').doc('tpl-worker').delete());
});

test('[4f] worker cannot delete another member’s template', async () => {
  await assertFails(dbFor(WORKER).collection('roadmap_templates').doc('tpl-admin').delete());
});

// ---------------------------------------------------------------- [7] invites
test('[7] worker cannot list the invite list', async () => {
  await assertFails(dbFor(WORKER).collection('invites').get());
});

test('[7] admin can list the invite list', async () => {
  const snap = await assertSucceeds(dbFor(ADMIN).collection('invites').get());
  assert.equal(snap.size, 3);
});

test('[7] fresh account can run the sign-up lookup query for its own email', async () => {
  const snap = await assertSucceeds(dbFor(FRESH).collection('invites')
    .where('email', '==', FRESH.email)
    .where('status', '==', 'pending')
    .get());
  assert.equal(snap.size, 1);
});

test('[7] fresh account cannot list invites unfiltered', async () => {
  await assertFails(dbFor(FRESH).collection('invites').get());
});

test('[7] fresh account can get its own matching invite, not someone else\'s', async () => {
  await assertSucceeds(dbFor(FRESH).collection('invites').doc('invite-newbie').get());
  await assertFails(dbFor(FRESH).collection('invites').doc('invite-other').get());
});

test('[7] worker can query only their own email, not another invite', async () => {
  const snap = await assertSucceeds(dbFor(WORKER).collection('invites')
    .where('email', '==', WORKER.email)
    .get());
  assert.equal(snap.size, 1);
  await assertFails(dbFor(WORKER).collection('invites').doc('invite-other').get());
});

// ------------------------------------------------------------- [7] hoursAudit
test('[7] hoursAudit: admin can create and read, worker can do neither', async () => {
  await assertSucceeds(dbFor(ADMIN).collection('hoursAudit').doc('audit-1').set({
    entryId: 'entry-open',
    editedBy: ADMIN.uid,
    editedAt: new Date(),
    before: { hours: null },
    after: { hours: 7.5 },
  }));
  await assertSucceeds(dbFor(ADMIN).collection('hoursAudit').doc('audit-1').get());
  await assertFails(dbFor(WORKER).collection('hoursAudit').doc('audit-2').set({
    entryId: 'entry-open',
    editedBy: WORKER.uid,
    editedAt: new Date(),
    before: {},
    after: {},
  }));
  await assertFails(dbFor(WORKER).collection('hoursAudit').doc('audit-1').get());
});

test('[7] hoursAudit: update and delete are denied even for admin', async () => {
  await assertSucceeds(dbFor(ADMIN).collection('hoursAudit').doc('audit-1').set({
    entryId: 'entry-open',
    editedBy: ADMIN.uid,
    editedAt: new Date(),
    before: {},
    after: {},
  }));
  await assertFails(dbFor(ADMIN).collection('hoursAudit').doc('audit-1').update({
    after: { hours: 1 },
  }));
  await assertFails(dbFor(ADMIN).collection('hoursAudit').doc('audit-1').delete());
});

// ---------------------------------------------------------------- [6] storage
test('[6] real app paths still work: taskPhotos and runPhotos uploads', async () => {
  await assertSucceeds(putBytes(storageFor(WORKER), 'taskPhotos/task-1/123.jpg'));
  await assertSucceeds(putBytes(storageFor(WORKER), 'runPhotos/run-1/456.jpg'));
});

test('[6] upload to a random path fails (no catch-all)', async () => {
  await assertFails(putBytes(storageFor(WORKER), 'secrets/evil.jpg'));
  await assertFails(putBytes(storageFor(WORKER), 'random.jpg'));
  await assertFails(putBytes(storageFor(WORKER), 'taskPhotos/task-1/sub/123.jpg'));
});

test('[6] profile photo: own uid path works, another user\'s does not', async () => {
  await assertSucceeds(
    putBytes(storageFor(WORKER), `profilePhotos/${WORKER.uid}.jpg`),
  );
  await assertFails(
    putBytes(storageFor(WORKER), `profilePhotos/${WORKER2.uid}.jpg`),
  );
});

test('[6] task photos stay image-only', async () => {
  await assertFails(
    putBytes(storageFor(WORKER), 'taskPhotos/task-1/123.txt', 'text/plain'),
  );
});

test('[6] chatMedia accepts image/video/audio but not octet-stream', async () => {
  await assertSucceeds(
    putBytes(storageFor(WORKER), 'chatMedia/dm-a-b/1.jpg', 'image/jpeg'),
  );
  await assertSucceeds(
    putBytes(storageFor(WORKER), 'chatMedia/dm-a-b/2.mp4', 'video/mp4'),
  );
  await assertSucceeds(
    putBytes(storageFor(WORKER), 'chatMedia/dm-a-b/3.m4a', 'audio/mp4'),
  );
  await assertFails(
    putBytes(storageFor(WORKER), 'chatMedia/dm-a-b/4.bin', 'application/octet-stream'),
  );
});

test('[6] unauthenticated upload fails; signed-in read works', async () => {
  await assertFails(putBytes(storageUnauthenticated(), 'taskPhotos/task-1/1.jpg'));
  await assertSucceeds(putBytes(storageFor(WORKER), 'taskPhotos/task-1/1.jpg'));
  await assertSucceeds(
    storageFor(WORKER2).ref('taskPhotos/task-1/1.jpg').getDownloadURL(),
  );
});

// ---------------------------------------------------------------- [8] audit fixes (2026-11-21)
// Rules holes P0-1..P0-6, invites + emailTransportReady (P1), and the
// admin time-entry restriction + coordinate validation (P2).
// UNVERIFIED: the VM has no Java / Firebase CLI, so `npm test`
// could not be run here. Run `cd functions && npm test` on the Mac.

// ------------------------------------------------------- [8a] P0-1 users: manager cannot escalate
test('[8a] manager cannot promote themselves to admin', async () => {
  await assertFails(
    dbFor(MANAGER).collection('users').doc(MANAGER.uid).update({ role: 'admin' }),
  );
});

test('[8a] manager cannot promote another worker to admin', async () => {
  await assertFails(
    dbFor(MANAGER).collection('users').doc(WORKER.uid).update({ role: 'admin' }),
  );
});

test('[8a] manager cannot re-activate a deactivated user', async () => {
  await assertFails(
    dbFor(MANAGER).collection('users').doc(DEACTIVATED.uid).update({ active: true }),
  );
});

test('[8a] manager cannot deactivate an active user', async () => {
  await assertFails(
    dbFor(MANAGER).collection('users').doc(WORKER.uid).update({ active: false }),
  );
});

test('[8a] manager CAN still update a worker\'s name (role/active untouched)', async () => {
  await assertSucceeds(
    dbFor(MANAGER).collection('users').doc(WORKER.uid).update({ name: 'Worker Renamed' }),
  );
});

// ------------------------------------------------------- [8b] P0-2 tasks: worker field restriction
test('[8b] assignee cannot rewrite the task title', async () => {
  await assertFails(dbFor(WORKER).collection('tasks').doc('task-2').update({ title: 'Rewritten' }));
});

test('[8b] assignee cannot change assigneeIds', async () => {
  await assertFails(dbFor(WORKER).collection('tasks').doc('task-2').update({ assigneeIds: [WORKER.uid] }));
});

test('[8b] assignee cannot change due date, stage, dependency, or unit', async () => {
  await assertFails(dbFor(WORKER).collection('tasks').doc('task-2').update({ dueDate: new Date('2026-12-01') }));
  await assertFails(dbFor(WORKER).collection('tasks').doc('task-2').update({ stageId: 'stage-9' }));
  await assertFails(dbFor(WORKER).collection('tasks').doc('task-2').update({ dependsOnTaskId: 'task-1' }));
  await assertFails(dbFor(WORKER).collection('tasks').doc('task-2').update({ unitId: 'unit-9' }));
  await assertFails(dbFor(WORKER).collection('tasks').doc('task-2').update({ notes: 'Rewritten notes' }));
});

test('[8b] assignee CAN still start / block / pause / complete their task', async () => {
  // startTask: status + startedAt + blockedReason + blockedNote.
  await assertSucceeds(dbFor(WORKER).collection('tasks').doc('task-2').update({
    status: 'inProgress', startedAt: new Date(), blockedReason: null, blockedNote: '',
  }));
  // blockTask: status + blockedReason + blockedNote.
  await assertSucceeds(dbFor(WORKER).collection('tasks').doc('task-2').update({
    status: 'blocked', blockedReason: 'waiting', blockedNote: 'Need plaster',
  }));
  // pauseTask / resumeTask: status + pausedFrom.
  await assertSucceeds(dbFor(WORKER).collection('tasks').doc('task-2').update({
    status: 'paused', pausedFrom: 'inProgress',
  }));
  // completeTask: status + finishedAt + photoUrls + photoPending.
  await assertSucceeds(dbFor(WORKER).collection('tasks').doc('task-2').update({
    status: 'done', finishedAt: new Date(),
    photoUrls: ['https://example.invalid/p.jpg'], photoPending: false,
  }));
});

test('[8b] manager CAN still edit a task title', async () => {
  await assertSucceeds(dbFor(MANAGER).collection('tasks').doc('task-2').update({ title: 'Manager retitle' }));
});

// ------------------------------------------------------- [8c] P0-3 conversations: membership/title
test('[8c] participant cannot rewrite participantIds', async () => {
  await assertFails(dbFor(WORKER).collection('conversations').doc('dm-worker-uid-worker2-uid').update({
    participantIds: [WORKER.uid],
  }));
  await assertFails(dbFor(WORKER).collection('conversations').doc('dm-worker-uid-worker2-uid').update({
    participantIds: [WORKER.uid, WORKER2.uid, 'outsider-uid'],
  }));
});

test('[8c] participant cannot retitle the conversation', async () => {
  await assertFails(dbFor(WORKER).collection('conversations').doc('dm-worker-uid-worker2-uid').update({
    title: 'Hijacked',
  }));
});

test('[8c] participant CAN still update preview / unread fields', async () => {
  await assertSucceeds(dbFor(WORKER).collection('conversations').doc('dm-worker-uid-worker2-uid').update({
    lastMessage: 'hello', lastSenderId: WORKER.uid,
    updatedAt: new Date(), unreadBy: [WORKER2.uid],
  }));
});

// ------------------------------------------------------- [8d] P0-4 notifications: no forging
test('[8d] user can mark their OWN notification read', async () => {
  await assertSucceeds(
    dbFor(WORKER).collection('notifications').doc('notif-worker').update({ read: true }),
  );
});

test('[8d] user cannot change their notification\'s userId', async () => {
  await assertFails(
    dbFor(WORKER).collection('notifications').doc('notif-worker').update({ userId: WORKER2.uid }),
  );
});

test('[8d] user cannot change userId even while marking read', async () => {
  await assertFails(
    dbFor(WORKER).collection('notifications').doc('notif-worker').update({ read: true, userId: WORKER2.uid }),
  );
});

test('[8d] user cannot read or update another user\'s notification', async () => {
  await assertFails(
    dbFor(WORKER).collection('notifications').doc('notif-worker2').get(),
  );
  await assertFails(
    dbFor(WORKER).collection('notifications').doc('notif-worker2').update({ read: true }),
  );
});

// ------------------------------------------------------- [8e] P0-5 storage: no client delete of shared media
test('[8e] non-owner cannot delete another user\'s chat/task/run media', async () => {
  await assertSucceeds(putBytes(storageFor(WORKER), 'chatMedia/dm-a-b/1.jpg'));
  await assertFails(storageFor(WORKER2).ref('chatMedia/dm-a-b/1.jpg').delete());
  await assertSucceeds(putBytes(storageFor(WORKER), 'taskPhotos/task-1/1.jpg'));
  await assertFails(storageFor(WORKER2).ref('taskPhotos/task-1/1.jpg').delete());
  await assertSucceeds(putBytes(storageFor(WORKER), 'runPhotos/run-1/1.jpg'));
  await assertFails(storageFor(WORKER2).ref('runPhotos/run-1/1.jpg').delete());
});

test('[8e] even the uploader cannot delete shared media from the client', async () => {
  await assertSucceeds(putBytes(storageFor(WORKER), 'chatMedia/dm-a-b/1.jpg'));
  await assertFails(storageFor(WORKER).ref('chatMedia/dm-a-b/1.jpg').delete());
  await assertSucceeds(putBytes(storageFor(WORKER), 'taskPhotos/task-1/1.jpg'));
  await assertFails(storageFor(WORKER).ref('taskPhotos/task-1/1.jpg').delete());
});

test('[8e] profile photo delete stays owner-gated (unchanged)', async () => {
  await assertSucceeds(putBytes(storageFor(WORKER), `profilePhotos/${WORKER.uid}.jpg`));
  await assertSucceeds(storageFor(WORKER).ref(`profilePhotos/${WORKER.uid}.jpg`).delete());
  await assertSucceeds(putBytes(storageFor(WORKER), `profilePhotos/${WORKER.uid}.jpg`));
  await assertFails(storageFor(WORKER2).ref(`profilePhotos/${WORKER.uid}.jpg`).delete());
});

// ------------------------------------------------------- [8f] P0-6 runs: driver field restriction
test('[8f] driver cannot change driverId', async () => {
  await assertFails(dbFor(WORKER).collection('runs').doc('run-1').update({ driverId: WORKER2.uid }));
});

test('[8f] driver cannot change the run date', async () => {
  await assertFails(dbFor(WORKER).collection('runs').doc('run-1').update({ date: '2026-11-15' }));
});

test('[8f] driver CAN update stops and odometer readings', async () => {
  await assertSucceeds(dbFor(WORKER).collection('runs').doc('run-1').update({
    stops: [{ id: 'stop-1', status: 'completed' }],
  }));
  await assertSucceeds(dbFor(WORKER).collection('runs').doc('run-1').update({
    odometerStart: 100, odometerEnd: 120,
  }));
});

test('[8f] non-driver worker cannot update the run at all', async () => {
  await assertFails(dbFor(WORKER2).collection('runs').doc('run-1').update({
    stops: [{ id: 'stop-1', status: 'completed' }],
  }));
});

test('[8f] admin CAN still reassign a run', async () => {
  await assertSucceeds(dbFor(ADMIN).collection('runs').doc('run-1').update({ driverId: WORKER2.uid }));
});

// ------------------------------------------------------- [8g] P1 invites: admin role is admin-only
test('[8g] manager cannot create an admin invite', async () => {
  await assertFails(dbFor(MANAGER).collection('invites').add({
    email: 'boss@test.local', role: 'admin', status: 'pending',
    invitedBy: MANAGER.uid, createdAt: new Date(),
  }));
});

test('[8g] manager CAN create a worker invite, admin CAN create an admin invite', async () => {
  await assertSucceeds(dbFor(MANAGER).collection('invites').add({
    email: 'crew@test.local', role: 'worker', status: 'pending',
    invitedBy: MANAGER.uid, createdAt: new Date(),
  }));
  await assertSucceeds(dbFor(ADMIN).collection('invites').add({
    email: 'boss@test.local', role: 'admin', status: 'pending',
    invitedBy: ADMIN.uid, createdAt: new Date(),
  }));
});

test('[8g] manager cannot flip an existing invite\'s role to admin', async () => {
  await assertFails(dbFor(MANAGER).collection('invites').doc('invite-worker').update({ role: 'admin' }));
});

test('[8g] admin CAN change an invite\'s role', async () => {
  await assertSucceeds(dbFor(ADMIN).collection('invites').doc('invite-worker').update({ role: 'manager' }));
});

test('[8g] invitee can accept their own invite but cannot rewrite its role', async () => {
  await assertFails(dbFor(WORKER).collection('invites').doc('invite-worker').update({
    status: 'accepted', role: 'admin',
  }));
  await assertSucceeds(dbFor(WORKER).collection('invites').doc('invite-worker').update({
    status: 'accepted', acceptedBy: WORKER.uid,
  }));
});

// ------------------------------------------------------- [8h] P1 settings: emailTransportReady is admin-only
test('[8h] manager CAN change the EOD channel but NOT emailTransportReady', async () => {
  await assertSucceeds(dbFor(MANAGER).collection('settings').doc('eodReport').update({ channel: 'email' }));
  await assertFails(dbFor(MANAGER).collection('settings').doc('eodReport').update({ emailTransportReady: true }));
  await assertFails(dbFor(MANAGER).collection('settings').doc('eodReport').update({
    channel: 'push', emailTransportReady: true,
  }));
});

test('[8h] admin CAN set emailTransportReady', async () => {
  await assertSucceeds(dbFor(ADMIN).collection('settings').doc('eodReport').update({ emailTransportReady: true }));
});

// ------------------------------------------------------- [8i] P2 coordinates: numbers, in range
test('[8i] clock-in with a non-numeric coordinate is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-x').set(validEntry({
    clockInLat: '45.00',
  })));
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-x').set(validEntry({
    clockInLng: 'many',
  })));
});

test('[8i] clock-in with an out-of-range coordinate is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-x').set(validEntry({
    clockInLat: 120, clockInLng: -73.00,
  })));
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-x').set(validEntry({
    clockInLat: 45.00, clockInLng: 200,
  })));
});

test('[8i] clock-in with valid (or null) coordinates is accepted', async () => {
  await assertSucceeds(dbFor(WORKER).collection('timeEntries').doc('entry-coords').set(validEntry({
    clockInLat: 45.00, clockInLng: -73.00,
  })));
  await assertSucceeds(dbFor(WORKER).collection('timeEntries').doc('entry-nocoords').set(validEntry({
    clockInLat: null, clockInLng: null,
  })));
});

test('[8i] breadcrumb with an out-of-range coordinate is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-open').collection('breadcrumbs').add({
    lat: 91, lng: -73.00, at: new Date(),
  }));
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-open').collection('breadcrumbs').add({
    lat: 45.00, lng: -181, at: new Date(),
  }));
});

test('[8i] clock-out with an out-of-range coordinate is rejected', async () => {
  await assertFails(dbFor(WORKER).collection('timeEntries').doc('entry-open').update({
    clockOutAt: new Date(), clockOutLat: -95, clockOutLng: -73.00,
  }));
});
