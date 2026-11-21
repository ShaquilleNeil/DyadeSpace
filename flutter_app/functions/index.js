// DyadeSpace Cloud Functions (2nd gen).
//
// Jobs, per the lean spec (plus the notification follow-ups):
//  1. generateDayReport - every day at the time stored in
//     `settings/eodReport` (`time`, "HH:mm" Toronto time,
//     default 6:00 PM), aggregate the day's tasks into a
//     `dayReports` doc (same shape the app's ReportService
//     writes) and send a summary to the managers per the stored
//     channel in `settings/eodReport` ('push', 'email', or
//     'both'; missing doc means 'both'). The trigger runs every
//     15 minutes and sends at the first tick at or after the
//     configured time, once per day (`lastSentDate` guard).
//     Push goes to each admin/manager's personal 'user_<uid>'
//     topic (so per-user notification prefs are respected).
//     Email is queued as docs in the `mail` collection
//     (Firebase Trigger Email extension format) — it only
//     delivers once that extension is installed and configured
//     AND `settings/eodReport.emailTransportReady` is true
//     (see readEodSettings); until then the push leg carries
//     the report instead of silently dropping it.
//     All date comparisons in the report (done today, overdue,
//     report date / doc id) are Toronto calendar dates, not
//     server-local ones.
//  2. sendDayReportNow - when an admin writes a doc to
//     `eodSendRequests` (Reports screen "Send now"), verify the
//     requester is an admin, then build and send today's report
//     the same way as (1), and mark the request sent.
//  3. notifyBlocked - when a task's status changes TO blocked,
//     push an alert to the 'managers' topic right away.
//  4. notifyStopFailed - when a delivery stop changes TO failed
//     ("couldn't complete"), push an alert to the 'managers' topic.
//  5. notifyTaskAssigned / notifyTaskReassigned - when a task is
//     created with an assignee, or its assignee changes, push an
//     alert to the assignee's personal 'user_<uid>' topic.
//  6. notifyRunPublished / notifyRunChanged - when a delivery
//     run is created, or its driver changes / its stop set
//     changes, push an alert to the driver's 'user_<uid>' topic.
//     Personal alerts (5, 6) are worded in the recipient's
//     profile language (users/<uid>.language: 'fr', 'es' or
//     English — see languageForUser / pick).
//  7. notifyStopCompleted - when a delivery stop changes TO
//     completed, push an alert to the 'managers' topic.
//  8. notifyTaskUnlocked - when a task is marked done, push an
//     alert to the assignees of its hard dependents
//     (dependsOnTaskId == the done task, dependsSoft == false).
//  9. notifyTaskPausedResumed - when a task's status changes TO
//     paused, or OUT of paused, push an alert to its assignee.
// 10. notifyTaskRemoved - when a task is deleted, push an alert
//     to its (former) assignee.
// 11. notifyStageReady - when a task is marked done and its
//     stage reaches 100%, push an alert to the 'managers'
//     topic: the next stage is ready to start. Nothing
//     auto-starts — an admin must still start the next stage.
// 12. notifyStageStarted - when a stage's startedAt goes from
//     null to set, push an alert to the assignees of that
//     stage's tasks: their tasks are now live.
// 13. notifyMorningBriefing - every day at 7:00 AM America/Toronto,
//     push each worker their day's tasks (count + site names, in
//     their profile language). Workers with no tasks due today
//     get nothing. "Due today" mirrors TaskService.tasksForToday
//     (lib/services/task_service.dart) exactly.
// 14. notifyTaskComment - when a comment/update is added to a
//     task's updates thread, push an alert to the task's
//     assignee AND the managers, each in their profile
//     language. The author is never notified; with no
//     assignee, or when the author IS the assignee, the
//     managers alone are notified.
// 15. notifyChatMessage - when a chat message is posted, push
//     an alert to every other participant, each in their profile
//     language. The notification doc carries the conversation
//     id so tapping it opens the chat.
// 16. notifyDriverArrived - when a stop's arrivedAt goes from
//     null to set (the driver tapped "I'm here"), push an alert
//     to the managers and to the worker waiting on that stop's
//     materials (the linked task's assignee), each in their
//     profile language.
// 17. notifyStopDelayed - when a stop's delay is newly reported
//     or changed (Delayed 15 / 30), push an alert to the same
//     recipients as (16).
// 18. Material requests - when a worker asks for materials
//     (notifyMaterialRequestCreated), push an alert to the
//     managers; when a manager approves or denies it
//     (notifyMaterialRequestDecided), push the outcome to the
//     requester, in their profile language. Delivery is not a
//     separate function: completing a request-linked pickup
//     stop in (7) marks the request delivered and tells the
//     requester their materials arrived.
// 19. Clock-in / clock-out - when a worker clocks in
//     (notifyClockIn, on timeEntries create) or out
//     (notifyClockOut, on clockOutAt null -> set), push an
//     alert to the admins and managers, each in their profile
//     language. The worker is never notified about their own
//     clock-in/out. The notification doc carries the entry id,
//     worker, site and the GPS coordinates of the event
//     (clock-in coords for a clock-in, clock-out coords for a
//     clock-out; null when the app captured none).
// 20. Server-side hours verification - verifyClockEntry (on
//     timeEntries create) and verifyClockOut (on timeEntries
//     update) compute clockInVerified / clockOutVerified,
//     flagged / flagReason and hours on the server from the
//     site's stored coordinates (per-site radius, 100 m
//     default, haversine), overwriting whatever the phone
//     wrote. Hours are (clockOutAt - clockInAt) rounded to 2
//     decimals, null while the entry is open. An AUTO entry
//     closed less than 10 minutes after it opened is deleted
//     outright (entry + route breadcrumbs) — a drive-by, not
//     work; see isShortAutoEntry in clock_rules.js. See the
//     loop guard in verifyClockOut: it only recomputes when
//     clockOutAt actually changed, so its own writes never
//     re-trigger it.
// 21. blockBeforeUserCreated - Auth blocking function: sign-up
//     is refused unless a pending invite exists for the email
//     in `invites`. ONLY RUNS ONCE IDENTITY PLATFORM IS
//     ENABLED in the Firebase console (Authentication >
//     Get started); until then the app's in-app invite check
//     (AuthService.findInvite) is the only gate, and it is
//     kept as defense in depth either way.
// 22. autoCloseOpenEntries - every day at 23:59 Toronto time,
//     close any timeEntry still open whose Toronto date is
//     today or earlier: clockOutAt = 23:59 Toronto that day,
//     flagged, flagReason 'auto-closed', hours computed.
//     Open site visits on those entries are closed too
//     (leftAt = 23:59, duration from arrival). No push is sent
//     for auto-closes (notifyClockOut skips entries flagged
//     'auto-closed').
// 23. pruneOldNotifications - every day at 03:00 Toronto
//     time, delete `notifications` docs older than 30 days.
// 24. disableUser - admin-only callable: disables a Firebase
//     Auth user (updateUser disabled + revokeRefreshTokens)
//     AND deactivates the users/{uid} profile (active = false)
//     in the same call, so no caller can forget it. Raw
//     errors are logged, never returned.
// 25. notifyStillClockedIn - every day at 18:00 Toronto time,
//     nudge every worker whose entry opened today and is still
//     open ("Still clocked in"), and tell the admins/managers.
//     Notification type: `stillClockedIn` (tapping it opens
//     the entry's map, like a clock-out).
//
// Every push above also writes a matching doc to the
// `notifications` collection (one per recipient) so the app can
// show an in-app inbox: see writeNotification / notifyManagers /
// notifyUser below.
//
// Deploy:  firebase deploy --only functions
// Devices subscribe to the topics in the app (notification_service).

const { onSchedule } = require("firebase-functions/v2/scheduler");
const {
  onDocumentCreated,
  onDocumentDeleted,
  onDocumentUpdated,
} = require("firebase-functions/v2/firestore");
const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { beforeUserCreated } = require("firebase-functions/v2/identity");
const admin = require("firebase-admin");
// Pure clock-in rules (per-site radius, 10-minute auto-entry
// rule) — unit-tested with plain node, no emulator.
const {
  radiusForSite,
  timestampMs,
  isShortAutoEntry,
} = require("./clock_rules");

admin.initializeApp();
const db = admin.firestore();

// --- Toronto calendar helpers ---------------------------------
// The scheduler runs in America/Toronto but the server clock is
// UTC, so "today" and every task-date comparison below are done
// in Toronto time. There used to be a server-local sameDay /
// dateId pair here; both were wrong for this file (a task
// finished at 20:00 Toronto is 01:00 UTC the next day, so the
// 6 PM report counted it on the wrong day) and were removed
// when the end-of-day report was converted to Toronto dates.
function torontoParts(date) {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Toronto",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  });
  const parts = {};
  for (const p of fmt.formatToParts(date)) {
    if (p.type !== "literal") parts[p.type] = Number(p.value);
  }
  return { y: parts.year, m: parts.month, d: parts.day };
}

function torontoSameDay(ts, dayParts) {
  if (!ts || typeof ts.toDate !== "function") return false;
  const p = torontoParts(ts.toDate());
  return p.y === dayParts.y && p.m === dayParts.m && p.d === dayParts.d;
}

// Compare two Toronto calendar dates: negative / 0 / positive.
function compareTorontoDay(a, b) {
  if (a.y !== b.y) return a.y - b.y;
  if (a.m !== b.m) return a.m - b.m;
  return a.d - b.d;
}

// A Toronto wall-clock time (y, m, d, hh, mm) as a real Date.
// Built by guessing the UTC instant, reading Toronto's offset
// there, and correcting once — exact for times away from a DST
// jump (23:59 and midnight both are). Never use
// `new Date(y, m, d, ...)` here: that is server-local time,
// not Toronto time.
function torontoWallTimeToDate(y, m, d, hh, mm) {
  const guess = new Date(Date.UTC(y, m - 1, d, hh, mm));
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Toronto",
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(guess);
  const get = (t) => Number(parts.find((p) => p.type === t).value);
  const asUTC = Date.UTC(
    get("year"), get("month") - 1, get("day"),
    get("hour"), get("minute"), get("second")
  );
  const targetAsUTC = Date.UTC(y, m - 1, d, hh, mm);
  return new Date(guess.getTime() + (targetAsUTC - asUTC));
}

exports.generateDayReport = onSchedule(
  { schedule: "*/15 * * * *", timeZone: "America/Toronto" },
  async () => {
    await maybeSendScheduledDayReport(new Date());
  }
);

// Toronto "HH:mm" and "yyyy-MM-dd" for a Date. Built from
// formatToParts so locale ordering can never scramble the
// fields; hourCycle h23 so midnight reads "00", never "24".
function torontoTimeHm(date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Toronto",
    hourCycle: "h23",
    hour: "2-digit",
    minute: "2-digit",
  }).formatToParts(date);
  const get = (t) => parts.find((p) => p.type === t).value;
  return `${get("hour")}:${get("minute")}`;
}

function torontoDateId(date) {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: "America/Toronto",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(date);
  const get = (t) => parts.find((p) => p.type === t).value;
  return `${get("year")}-${get("month")}-${get("day")}`;
}

// The whole `settings/eodReport` doc: channel, time,
// lastSentDate, emailTransportReady. Anything missing or
// unexpected falls back to the previous behaviour (channel
// 'both', time "18:00"). `emailTransportReady` defaults to
// false: the email leg only runs once a human has installed
// the Firebase Trigger Email extension AND set
// `settings/eodReport.emailTransportReady = true` in the
// console — until then the report falls back to push so it is
// never silently dropped (see buildAndSendDayReport).
async function readEodSettings() {
  const out = { channel: "both", time: "18:00", lastSentDate: null, emailTransportReady: false };
  try {
    const snap = await db.collection("settings").doc("eodReport").get();
    if (!snap.exists) return out;
    const data = snap.data();
    if (data.channel === "push" ||
        data.channel === "email" ||
        data.channel === "both") {
      out.channel = data.channel;
    }
    if (typeof data.time === "string" &&
        /^\d{2}:\d{2}$/.test(data.time)) {
      out.time = data.time;
    }
    if (typeof data.lastSentDate === "string") {
      out.lastSentDate = data.lastSentDate;
    }
    if (data.emailTransportReady === true) {
      out.emailTransportReady = true;
    }
  } catch (_) {
    // Firestore read failed: fall through to the defaults.
  }
  return out;
}

// The scheduled end-of-day report: sends at the first tick at
// or after the configured time, once per day — `lastSentDate`
// (Toronto yyyy-MM-dd) is the guard. The guard is claimed
// inside a transaction (read the doc, set the date, commit)
// so two concurrent ticks cannot both pass the check and
// double-send; a failed send releases the claim again so the
// next tick retries instead of skipping the day. A missed tick
// (function down at the configured time) sends at the next
// tick instead of never. "Send now" bypasses this entirely
// (it calls buildAndSendDayReport directly).
async function maybeSendScheduledDayReport(now) {
  const settings = await readEodSettings();
  const today = torontoDateId(now);
  if (settings.lastSentDate === today) return;
  if (torontoTimeHm(now) < settings.time) return;
  const settingsRef = db.collection("settings").doc("eodReport");
  let claimed = false;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(settingsRef);
    const prev = snap.exists ? snap.data().lastSentDate : null;
    if (prev === today) return; // another tick claimed it first
    tx.set(settingsRef, { lastSentDate: today }, { merge: true });
    claimed = true;
  });
  if (!claimed) return;
  try {
    await buildAndSendDayReport(now);
  } catch (err) {
    // Release the claim so the next tick retries.
    await settingsRef.set(
      { lastSentDate: settings.lastSentDate || null },
      { merge: true }
    );
    throw err;
  }
}

// (readEodChannel was removed: buildAndSendDayReport reads the
// whole settings doc now, because the email leg also needs
// emailTransportReady.)

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

// Email leg of the end-of-day report: one `mail` doc per admin /
// manager with an email address, in the Firebase Trigger Email
// extension's format ({ to, message: { subject, html } }). The
// extension is what actually delivers them; buildAndSendDayReport
// only calls this once emailTransportReady is set, so without
// the extension no `mail` docs are queued at all and push
// carries the report instead.
async function sendEodEmail(summary, blocked) {
  const snap = await db
    .collection("users")
    .where("role", "in", ["admin", "manager"])
    .get();
  const blockedRows = blocked
    .map(
      (t) =>
        `<li>${escapeHtml(t.title || "A task")} — ${escapeHtml(
          t.blockedReason || "other"
        )}${t.blockedNote ? `: ${escapeHtml(t.blockedNote)}` : ""}</li>`
    )
    .join("");
  const html =
    `<p>${escapeHtml(summary)}</p>` +
    (blockedRows ? `<p>Blocked:</p><ul>${blockedRows}</ul>` : "");
  await Promise.all(
    snap.docs.map(async (doc) => {
      const email = (doc.data().email || "").trim();
      if (!email) return;
      // A manager who turned the end-of-day report off in
      // Settings gets no email either (same pref as the push).
      if (!(await notifEnabled(doc.id, "dayReport"))) return;
      return db.collection("mail").add({
        to: email,
        message: {
          subject: "DyadeSpace - End of day",
          html,
        },
      });
    })
  );
}

// Shared by the 6 PM schedule (1) and "Send now" (12): aggregate
// the day's tasks, write the dayReports doc, then send the
// summary on the stored channel.
async function buildAndSendDayReport(now) {
  const snap = await db.collection("tasks").get();
  const tasks = snap.docs.map((doc) => ({ id: doc.id, ...doc.data() }));

  // All comparisons below are Toronto calendar dates: the
  // server runs on UTC, so a server-local "today" would put a
  // task finished at 20:00 Toronto (01:00 UTC next day) on the
  // wrong day's report.
  const today = torontoParts(now);
  const done = tasks.filter(
    (t) => t.status === "done" && torontoSameDay(t.finishedAt, today)
  );
  const inProgress = tasks.filter(
    (t) => t.status === "inProgress" || t.status === "toConfirm"
  );
  const blocked = tasks.filter((t) => t.status === "blocked");
  const overdue = tasks.filter((t) => {
    if (t.status === "done" || !t.dueDate) return false;
    // Overdue = the due date's Toronto calendar day is before today.
    return compareTorontoDay(torontoParts(t.dueDate.toDate()), today) < 0;
  });

  const blockedReasons = {};
  for (const t of blocked) {
    blockedReasons[t.id] = `${t.blockedReason || "other"}: ${t.blockedNote || ""}`;
  }

  const report = {
    date: admin.firestore.Timestamp.fromDate(
      torontoWallTimeToDate(today.y, today.m, today.d, 0, 0)
    ),
    generatedAt: admin.firestore.FieldValue.serverTimestamp(),
    doneCount: done.length,
    inProgressCount: inProgress.length,
    blockedCount: blocked.length,
    overdueCount: overdue.length,
    doneTaskIds: done.map((t) => t.id),
    inProgressTaskIds: inProgress.map((t) => t.id),
    overdueTaskIds: overdue.map((t) => t.id),
    blockedReasons,
  };

  // Doc id is the Toronto date, matching the app's own
  // ReportService.buildAndSaveReport (device-local yyyy-MM-dd).
  const reportId = torontoDateId(now);
  await db.collection("dayReports").doc(reportId).set(report);

  const summary =
    `Done: ${done.length} · In progress: ${inProgress.length} · Blocked: ${blocked.length} · Overdue: ${overdue.length}`;
  const settings = await readEodSettings();
  const channel = settings.channel;
  const wantEmail = channel === "email" || channel === "both";
  const wantPush = channel === "push" || channel === "both";
  // Email leg runs only once the Trigger Email extension is
  // installed AND emailTransportReady is set (see
  // readEodSettings). If the channel asks for email but the
  // transport is not ready, push carries the report instead —
  // the report is never silently dropped.
  if (wantPush || (wantEmail && !settings.emailTransportReady)) {
    // Per-recipient pushes (not the shared 'managers' topic)
    // so a manager who turned the end-of-day report off in
    // Settings is skipped — notifyUser enforces the pref.
    const managers = await db
      .collection("users")
      .where("role", "in", ["admin", "manager"])
      .get();
    await Promise.all(
      managers.docs.map((doc) =>
        notifyUser(
          doc.id,
          "DyadeSpace - End of day",
          summary,
          "dayReport",
          { reportId }
        )
      )
    );
  }
  if (wantEmail && settings.emailTransportReady) {
    await sendEodEmail(summary, blocked);
  }
}

// "Send now" from the Reports screen (admin only). The request
// doc carries requestedBy (the admin's uid, enforced by the
// Firestore rules on create); the role is re-checked here
// because rules alone cannot be trusted for a send. A denied or
// failed request is marked, never retried silently.
exports.sendDayReportNow = onDocumentCreated(
  "eodSendRequests/{requestId}",
  async (event) => {
    const req = event.data && event.data.data();
    const reqRef = db.collection("eodSendRequests").doc(event.params.requestId);
    if (!req || !req.requestedBy) {
      await reqRef.update({ status: "denied" });
      return;
    }
    try {
      const userSnap = await db.collection("users").doc(req.requestedBy).get();
      if (!userSnap.exists || userSnap.data().role !== "admin") {
        await reqRef.update({ status: "denied" });
        return;
      }
      await buildAndSendDayReport(new Date());
      await reqRef.update({
        status: "sent",
        sentAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    } catch (err) {
      await reqRef.update({
        status: "failed",
        error: String((err && err.message) || err),
      });
    }
  }
);

// --- 7:00 AM morning push -------------------------------------
// Mirror of StageIndex.isVisibleToday (lib/models/stage.dart): a
// task counts as today's work only when its stage is Active
// (started) or Completed - or it has no stage. Stage status is
// derived from the stage docs and the task list, in (siteId,
// order) order, exactly as the app derives it.
function visibleStageIds(stages, tasks) {
  const bySite = new Map();
  for (const s of [...stages].sort((a, b) => {
    const c = String(a.siteId || "").localeCompare(String(b.siteId || ""));
    if (c !== 0) return c;
    const o = (a.order ?? 0) - (b.order ?? 0);
    if (o !== 0) return o;
    return String(a.id).localeCompare(String(b.id));
  })) {
    if (!bySite.has(s.siteId)) bySite.set(s.siteId, []);
    bySite.get(s.siteId).push(s);
  }
  const tasksByStage = new Map();
  for (const t of tasks) {
    if (!t.stageId) continue;
    if (!tasksByStage.has(t.stageId)) tasksByStage.set(t.stageId, []);
    tasksByStage.get(t.stageId).push(t);
  }
  const statusOf = (stage) => {
    if (stage.skipped === true) return "skipped";
    const ts = tasksByStage.get(stage.id) || [];
    if (ts.length > 0 && ts.every((t) => t.status === "done")) {
      return "completed";
    }
    if (stage.startedAt) return "inProgress";
    const list = bySite.get(stage.siteId) || [];
    const i = list.findIndex((s) => s.id === stage.id);
    if (i <= 0) return "ready";
    const prev = statusOf(list[i - 1]);
    return prev === "completed" || prev === "skipped" ? "ready" : "locked";
  };
  const visible = new Set();
  for (const s of stages) {
    const st = statusOf(s);
    if (st === "inProgress" || st === "completed") visible.add(s.id);
  }
  return visible;
}

// Mirror of TaskService.tasksForToday
// (lib/services/task_service.dart), evaluated in Toronto time:
// due today, overdue, in progress, blocked, paused, finished
// today, or inside a multi-day start..due window. Overdue here
// means the due date's Toronto calendar day is before today.
function isTaskForToday(task, today, visibleStages) {
  if (task.stageId && !visibleStages.has(task.stageId)) return false;
  if (task.status === "done") {
    return torontoSameDay(task.finishedAt, today);
  }
  if (torontoSameDay(task.dueDate, today)) return true;
  if (task.dueDate && typeof task.dueDate.toDate === "function") {
    if (
      compareTorontoDay(torontoParts(task.dueDate.toDate()), today) < 0
    ) {
      return true; // overdue
    }
  }
  if (
    task.status === "inProgress" ||
    task.status === "blocked" ||
    task.status === "paused"
  ) {
    return true;
  }
  if (task.startDate && typeof task.startDate.toDate === "function") {
    if (torontoSameDay(task.startDate, today)) return true;
    if (task.dueDate && typeof task.dueDate.toDate === "function") {
      const start = torontoParts(task.startDate.toDate());
      const due = torontoParts(task.dueDate.toDate());
      if (
        compareTorontoDay(start, today) <= 0 &&
        compareTorontoDay(today, due) <= 0
      ) {
        return true;
      }
    }
  }
  return false;
}

// Every day at 7:00 AM America/Toronto, each worker with tasks
// due today gets one push (plus the matching in-app notification
// doc) with the count and the site names, worded in their
// profile language. Workers with no tasks due today get
// nothing. Any assignee with today's tasks is notified,
// whatever their role - the push is about their own day's work.
exports.notifyMorningBriefing = onSchedule(
  { schedule: "0 7 * * *", timeZone: "America/Toronto" },
  async () => {
    const today = torontoParts(new Date());
    const [tasksSnap, sitesSnap, stagesSnap] = await Promise.all([
      db.collection("tasks").get(),
      db.collection("sites").get(),
      db.collection("stages").get(),
    ]);
    const tasks = tasksSnap.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));
    const stages = stagesSnap.docs.map((doc) => ({
      id: doc.id,
      ...doc.data(),
    }));
    const siteNames = new Map(
      sitesSnap.docs.map((doc) => [doc.id, (doc.data().name || "").trim()])
    );
    const visibleStages = visibleStageIds(stages, tasks);

    const byAssignee = new Map(); // uid -> today's tasks
    for (const task of tasks) {
      if (!isTaskForToday(task, today, visibleStages)) continue;
      // Multi-assignee tasks brief every assignee, not just
      // the legacy single assigneeId (assigneeIdsOf falls back
      // to assigneeId for old docs).
      for (const assigneeId of assigneeIdsOf(task)) {
        if (!byAssignee.has(assigneeId)) {
          byAssignee.set(assigneeId, []);
        }
        byAssignee.get(assigneeId).push(task);
      }
    }

    for (const [uid, dayTasks] of byAssignee) {
      const lang = await languageForUser(uid);
      const count = dayTasks.length;
      const names = [];
      for (const t of dayTasks) {
        const name = siteNames.get(t.siteId) || "";
        if (name && !names.includes(name)) names.push(name);
      }
      // Push bodies stay short: at most 4 site names, then a
      // "+ N more" tail. Tasks whose site doc is missing or
      // unnamed are counted but add no name.
      const shown = names.slice(0, 4);
      const extra = names.length - shown.length;
      let sitePart = shown.join(", ");
      if (extra > 0) {
        sitePart += pick(
          lang,
          ` + ${extra} autre${extra > 1 ? "s" : ""}`,
          ` + ${extra} más`,
          ` + ${extra} more`
        );
      }
      const taskWord = pick(
        lang,
        count === 1 ? "tâche" : "tâches",
        count === 1 ? "tarea" : "tareas",
        count === 1 ? "task" : "tasks"
      );
      const body = pick(
        lang,
        sitePart
          ? `Vous avez ${count} ${taskWord} aujourd'hui à ${sitePart}`
          : `Vous avez ${count} ${taskWord} aujourd'hui`,
        sitePart
          ? `Tienes ${count} ${taskWord} hoy en ${sitePart}`
          : `Tienes ${count} ${taskWord} hoy`,
        sitePart
          ? `You have ${count} ${taskWord} today at ${sitePart}`
          : `You have ${count} ${taskWord} today`
      );
      await notifyUser(
        uid,
        pick(
          lang,
          "Votre journée DyadeSpace",
          "Tu día en DyadeSpace",
          "Your day at DyadeSpace"
        ),
        body,
        "morningBriefing",
        {}
      );
    }
  }
);

exports.notifyBlocked = onDocumentUpdated("tasks/{taskId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after || before.status === after.status) return;
  if (after.status !== "blocked") return;

  await notifyManagers(
    "Task blocked",
    `${after.title || "A task"} - ${after.blockedReason || "other"}${after.blockedNote ? `: ${after.blockedNote}` : ""}`,
    "blocked",
    { taskId: event.params.taskId }
  );
});

// --- Personal alerts (jobs 4 and 5) ---------------------------
// The recipient's profile language decides the wording:
// 'fr' -> French, 'es' -> Spanish (neutral Latin American),
// anything else - including a missing profile - English.
// Functions cannot read the app's string table, so the three
// variants are hardcoded here, kept short on purpose. Every
// user-facing string the functions send must have all three;
// pick() below is the enforcement point — never build a
// two-way fr/en choice for a push title or body.

async function languageForUser(uid) {
  if (!uid) return "en";
  try {
    const snap = await db.collection("users").doc(uid).get();
    if (!snap.exists) return "en";
    const lang = snap.data().language;
    if (lang === "fr" || lang === "es") return lang;
    return "en";
  } catch (_) {
    return "en";
  }
}

// One of three wordings by profile language: pick(lang, fr, es,
// en). Use it for every push title/body so no language is ever
// left blank or silently falls back to English.
function pick(lang, fr, es, en) {
  if (lang === "fr") return fr;
  if (lang === "es") return es;
  return en;
}

// Notification prefs, stored on the user doc as `notifPrefs`
// (Settings screen; all on by default). Maps a notification
// `type` to its pref key — null means the type has no toggle
// and is always sent.
const notifPrefKeyForType = {
  taskAssigned: "taskAssigned",
  clockIn: "clockInOut",
  clockOut: "clockInOut",
  chatMessage: "chatMessages",
  dayReport: "eodReport",
};

function prefKeyForType(type) {
  return notifPrefKeyForType[type] || null;
}

// Reads one user's notifPrefs map ({} when the doc or the map
// is missing — everything on). A missing key reads as ON, so
// users who never opened Settings keep every notification.
async function prefsForUser(uid) {
  if (!uid) return {};
  try {
    const snap = await db.collection("users").doc(uid).get();
    if (!snap.exists) return {};
    return snap.data().notifPrefs || {};
  } catch (_) {
    return {};
  }
}

// True unless the user explicitly turned this type off.
async function notifEnabled(uid, type) {
  const key = prefKeyForType(type);
  if (key == null) return true;
  const prefs = await prefsForUser(uid);
  return prefs[key] !== false;
}

// A site's display name for material-request pushes.
async function siteNameFor(siteId) {
  if (!siteId) return "";
  try {
    const snap = await db.collection("sites").doc(siteId).get();
    if (!snap.exists) return "";
    return snap.data().name || "";
  } catch (_) {
    return "";
  }
}

// A Timestamp as a plain yyyy-MM-dd date, in Toronto time
// (due dates and run dates are Toronto calendar dates; the
// server-local date would be a day off for evening times).
function plainDate(ts) {
  if (!ts || typeof ts.toDate !== "function") return null;
  const p = torontoParts(ts.toDate());
  const m = String(p.m).padStart(2, "0");
  const day = String(p.d).padStart(2, "0");
  return `${p.y}-${m}-${day}`;
}

// --- Notification docs ----------------------------------------
// Every push also lands in the `notifications` collection so the
// app can show an in-app inbox. One doc per recipient, unread
// until the app marks it read. `extra` carries the push data
// fields (taskId / runId / stopId / reportId / conversationId /
// materialRequestId); only the id fields are stored on the doc, the rest travel in
// the push only. Clock-in/out notifications additionally carry
// the entry id, worker, site and the GPS coordinates of the
// event (timeEntryId / userName / siteId / siteName / lat /
// lng); every other notification stores those as null.
async function writeNotification({ userId, title, body, type, taskId, runId, stopId, reportId, materialRequestId, conversationId, timeEntryId, userName, siteId, siteName, lat, lng }) {
  await db.collection("notifications").add({
    userId,
    title,
    body,
    type,
    taskId: taskId ?? null,
    runId: runId ?? null,
    stopId: stopId ?? null,
    reportId: reportId ?? null,
    materialRequestId: materialRequestId ?? null,
    conversationId: conversationId ?? null,
    timeEntryId: timeEntryId ?? null,
    userName: userName ?? null,
    siteId: siteId ?? null,
    siteName: siteName ?? null,
    lat: lat ?? null,
    lng: lng ?? null,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    read: false,
  });
}

// Push to the 'managers' topic AND write one notification doc per
// user with role admin or manager. The topic push cannot be
// filtered per user; the doc loop below skips users who turned
// the type off. (No gated type uses this helper today — the
// end-of-day report goes per-recipient via notifyUser — but
// the filter keeps the docs honest if one ever does.)
async function notifyManagers(title, body, type, extra) {
  const ids = extra || {};
  await admin.messaging().send({
    topic: "managers",
    notification: { title, body },
    data: { type, ...ids },
  });
  const snap = await db
    .collection("users")
    .where("role", "in", ["admin", "manager"])
    .get();
  await Promise.all(
    snap.docs.map(async (doc) => {
      if (!(await notifEnabled(doc.id, type))) return;
      await writeNotification({
        userId: doc.id,
        title,
        body,
        type,
        taskId: ids.taskId,
        runId: ids.runId,
        stopId: ids.stopId,
        reportId: ids.reportId,
        materialRequestId: ids.materialRequestId,
        conversationId: ids.conversationId,
      });
    })
  );
}

// Push to one user's personal topic AND write their doc.
// Skips both when the user turned this type off in Settings
// (all types without a toggle always send). FCM data values
// must be strings, so the extra fields are stringified and
// nulls dropped for the push; the doc keeps the original
// values (numbers stay numbers for lat / lng).
async function notifyUser(uid, title, body, type, extra) {
  if (!(await notifEnabled(uid, type))) return;
  const ids = extra || {};
  const data = { type };
  for (const [key, value] of Object.entries(ids)) {
    if (value == null) continue;
    data[key] = String(value);
  }
  await admin.messaging().send({
    topic: `user_${uid}`,
    notification: { title, body },
    data,
  });
  await writeNotification({
    userId: uid,
    title,
    body,
    type,
    taskId: ids.taskId,
    runId: ids.runId,
    stopId: ids.stopId,
    reportId: ids.reportId,
    materialRequestId: ids.materialRequestId,
    conversationId: ids.conversationId,
    timeEntryId: ids.timeEntryId,
    userName: ids.userName,
    siteId: ids.siteId,
    siteName: ids.siteName,
    lat: ids.lat,
    lng: ids.lng,
  });
}

// The assignees of a task: the new `assigneeIds` list when
// present, the old single `assigneeId` string as a fallback
// (old docs), empty when unassigned.
function assigneeIdsOf(task) {
  if (!task) return [];
  if (Array.isArray(task.assigneeIds) && task.assigneeIds.length > 0) {
    return task.assigneeIds.filter(
      (id) => typeof id === 'string' && id.length > 0
    );
  }
  return task.assigneeId ? [task.assigneeId] : [];
}

async function sendTaskAssigned(taskId, task, onlyIds) {
  const ids = onlyIds || assigneeIdsOf(task);
  for (const assigneeId of ids) {
    const lang = await languageForUser(assigneeId);
    const title = task.title || pick(lang, "Une tâche", "Una tarea", "A task");
    const due = plainDate(task.dueDate);
    const body = due
      ? pick(
          lang,
          `${title} - à faire pour le ${due}`,
          `${title} - para el ${due}`,
          `${title} - due ${due}`
        )
      : title;
    await notifyUser(
      assigneeId,
      pick(lang, "Nouvelle tâche assignée", "Nueva tarea asignada", "New task assigned"),
      body,
      "taskAssigned",
      { taskId }
    );
  }
}

exports.notifyTaskAssigned = onDocumentCreated(
  "tasks/{taskId}",
  async (event) => {
    const task = event.data && event.data.data();
    if (!task) return;
    await sendTaskAssigned(event.params.taskId, task);
  }
);

// Only newly ADDED assignees notify - and only them. Status /
// photo / etc. updates to the same task stay silent, and so do
// people who were already assigned.
exports.notifyTaskReassigned = onDocumentUpdated(
  "tasks/{taskId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!after) return;
    const beforeIds = new Set(assigneeIdsOf(before));
    const added = assigneeIdsOf(after).filter((id) => !beforeIds.has(id));
    if (added.length === 0) return;
    await sendTaskAssigned(event.params.taskId, after, added);
  }
);

async function sendRunPublished(runId, run) {
  const driverId = run && run.driverId;
  if (!driverId) return;
  const lang = await languageForUser(driverId);
  const date = plainDate(run.date);
  const count = (run.stops || []).length;
  const body = pick(
    lang,
    `Tournée${date ? ` du ${date}` : ""} - ${count} arrêt(s)`,
    `Recorrido${date ? ` del ${date}` : ""} - ${count} parada(s)`,
    `Delivery run${date ? ` for ${date}` : ""} - ${count} stop(s)`
  );
  await notifyUser(
    driverId,
    pick(lang, "Nouvelle tournée de livraison", "Nuevo recorrido de entrega", "New delivery run"),
    body,
    "runPublished",
    { runId }
  );
}

exports.notifyRunPublished = onDocumentCreated(
  "runs/{runId}",
  async (event) => {
    const run = event.data && event.data.data();
    if (!run) return;
    await sendRunPublished(event.params.runId, run);
  }
);

// The driver updates his own run all day (stop statuses, photos,
// checklist ticks) - none of that may notify. Only two changes
// do: a new driver (notify the NEW driver) or a different set of
// stop ids (stops added/removed by the manager).
// A driver change keeps the generic "New delivery run" message.
// A stop-set change names the change instead: one push per change
// type detected (added and/or removed), naming the first added /
// removed stop's title when it can be identified (removed stops
// are read from the BEFORE snapshot, since they are gone after).
exports.notifyRunChanged = onDocumentUpdated(
  "runs/{runId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!after || !after.driverId) return;
    if (!before || before.driverId !== after.driverId) {
      await sendRunPublished(event.params.runId, after);
      return;
    }
    const beforeStops = (before && before.stops) || [];
    const afterStops = after.stops || [];
    const beforeIds = new Set(beforeStops.map((s) => s.id));
    const afterIds = new Set(afterStops.map((s) => s.id));
    const changed =
      beforeIds.size !== afterIds.size ||
      [...afterIds].some((id) => !beforeIds.has(id));
    if (!changed) return;

    const lang = await languageForUser(after.driverId);
    const added = afterStops.filter((s) => !beforeIds.has(s.id));
    const removed = beforeStops.filter((s) => !afterIds.has(s.id));
    if (added.length > 0) {
      const first = added[0];
      const title = first.title || null;
      await notifyUser(
        after.driverId,
        pick(lang, "Arrêt ajouté à votre tournée", "Parada agregada a tu recorrido", "Stop added to your run"),
        title
          ? pick(
              lang,
              `${title} ajouté à votre tournée`,
              `${title} agregada a tu recorrido`,
              `${title} added to your run`
            )
          : pick(lang, "Arrêt ajouté à votre tournée", "Parada agregada a tu recorrido", "Stop added to your run"),
        "stopAdded",
        { runId: event.params.runId, stopId: first.id || "" }
      );
    }
    if (removed.length > 0) {
      const first = removed[0];
      const title = first.title || null;
      await notifyUser(
        after.driverId,
        pick(lang, "Arrêt retiré de votre tournée", "Parada eliminada de tu recorrido", "Stop removed from your run"),
        title
          ? pick(
              lang,
              `${title} retiré de votre tournée`,
              `${title} eliminada de tu recorrido`,
              `${title} removed from your run`
            )
          : pick(lang, "Arrêt retiré de votre tournée", "Parada eliminada de tu recorrido", "Stop removed from your run"),
        "stopRemoved",
        { runId: event.params.runId, stopId: first.id || "" }
      );
    }
  }
);

// Stops live inside the run doc as an embedded array, so compare
// stop by stop (matched by id): fire only on the transition INTO
// failed, never on later edits to an already-failed stop.
exports.notifyStopFailed = onDocumentUpdated("runs/{runId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after) return;

  const beforeById = new Map(
    ((before && before.stops) || []).map((s) => [s.id, s])
  );
  for (const stop of after.stops || []) {
    if (stop.status !== "failed") continue;
    const prev = beforeById.get(stop.id);
    if (prev && prev.status === "failed") continue; // already failed

    await notifyManagers(
      "Delivery stop not completed",
      `${stop.title || "A stop"} - ${stop.failReason || "other"}${stop.failNote ? `: ${stop.failNote}` : ""}`,
      "stopFailed",
      { runId: event.params.runId, stopId: stop.id || "" }
    );
  }
});

// Mirror of notifyStopFailed, but for the transition INTO
// completed: fire only for stops that were not completed before.
exports.notifyStopCompleted = onDocumentUpdated("runs/{runId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after) return;

  const beforeById = new Map(
    ((before && before.stops) || []).map((s) => [s.id, s])
  );
  for (const stop of after.stops || []) {
    if (stop.status !== "completed") continue;
    const prev = beforeById.get(stop.id);
    if (prev && prev.status === "completed") continue; // already completed

    await notifyManagers(
      "Stop completed",
      `${stop.title || "A stop"} completed`,
      "stopCompleted",
      { runId: event.params.runId, stopId: stop.id || "" }
    );

    // A request-linked pickup: completing it means the
    // materials are in hand, so the request is delivered and
    // the requester is told where they arrived. Guarded on
    // status so a re-run of the same completion never
    // double-notifies. The request's task id travels in the
    // push extra so tapping the notification opens the task
    // (site-level requests have none and open nothing).
    if (stop.materialRequestId) {
      const requestRef = db
        .collection("materialRequests")
        .doc(stop.materialRequestId);
      const requestSnap = await requestRef.get();
      if (requestSnap.exists) {
        const request = requestSnap.data();
        if (request.status !== "delivered") {
          await requestRef.update({ status: "delivered" });
          const requesterId = request.requesterId || null;
          if (requesterId) {
            const lang = await languageForUser(requesterId);
            const siteName = await siteNameFor(request.siteId);
            const where = siteName
              ? pick(lang, ` à ${siteName}`, ` en ${siteName}`, ` at ${siteName}`)
              : "";
            await notifyUser(
              requesterId,
              pick(lang, "Matériaux livrés", "Materiales entregados", "Materials delivered"),
              pick(
                lang,
                `Vos matériaux (${request.quantity} × ${request.item}) sont arrivés${where}.`,
                `Tus materiales (${request.quantity} × ${request.item}) llegaron${where}.`,
                `Your materials (${request.quantity} × ${request.item}) arrived${where}.`
              ),
              "materialDelivered",
              {
                taskId: request.taskId || null,
                materialRequestId: stop.materialRequestId,
              }
            );
          }
        }
      }
    }
  }
});

// The worker waiting on a stop's materials: the first assignee
// of the task the stop is linked to (multi-assignee tasks notify
// the first assignee here; the arrival/delay push is per stop,
// not per assignee). Null when the stop has no task, the task
// is gone, or it is unassigned.
async function waitingWorkerIdForStop(stop) {
  if (!stop || !stop.taskId) return null;
  try {
    const snap = await db.collection("tasks").doc(stop.taskId).get();
    if (!snap.exists) return null;
    return assigneeIdsOf(snap.data())[0] || null;
  } catch (_) {
    return null;
  }
}

// A user's display name for arrival/delay pushes.
async function userName(uid) {
  if (!uid) return null;
  try {
    const snap = await db.collection("users").doc(uid).get();
    if (!snap.exists) return null;
    return snap.data().name || null;
  } catch (_) {
    return null;
  }
}

// When the driver taps "I'm here" on a stop (arrivedAt goes from
// null to set): the managers get the arrival, and so does the
// worker waiting on that stop's materials (the linked task's
// assignee), each in their profile language. The driver is never
// notified about their own arrival.
exports.notifyDriverArrived = onDocumentUpdated("runs/{runId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after) return;

  const beforeById = new Map(
    ((before && before.stops) || []).map((s) => [s.id, s])
  );
  const driverName = (await userName(after.driverId)) || "The driver";
  for (const stop of after.stops || []) {
    if (!stop.arrivedAt) continue;
    const prev = beforeById.get(stop.id);
    if (prev && prev.arrivedAt) continue; // already arrived
    const site = stop.title || "a site";
    await notifyManagers(
      "Driver arrived",
      `${driverName} arrived at ${site}`,
      "driverArrived",
      { runId: event.params.runId, stopId: stop.id || "" }
    );
    const waitingId = await waitingWorkerIdForStop(stop);
    if (waitingId && waitingId !== after.driverId) {
      const lang = await languageForUser(waitingId);
      await notifyUser(
        waitingId,
        pick(lang, "Livreur arrivé", "Conductor llegó", "Driver arrived"),
        pick(
          lang,
          `${driverName} est arrivé à ${site}.`,
          `${driverName} llegó a ${site}.`,
          `${driverName} arrived at ${site}.`
        ),
        "driverArrived",
        { runId: event.params.runId, stopId: stop.id || "" }
      );
    }
  }
});

// When the driver reports a delay on a stop (delayedAt newly set
// or changed): same recipients as an arrival. Re-tapping with a
// different delay fires again - the delay report is the event,
// not the delay value.
exports.notifyStopDelayed = onDocumentUpdated("runs/{runId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after) return;

  const beforeById = new Map(
    ((before && before.stops) || []).map((s) => [s.id, s])
  );
  const driverName = (await userName(after.driverId)) || "The driver";
  for (const stop of after.stops || []) {
    if (stop.delayedMinutes == null || !stop.delayedAt) continue;
    const prev = beforeById.get(stop.id);
    if (
      prev &&
      prev.delayedAt &&
      typeof prev.delayedAt.toMillis === "function" &&
      typeof stop.delayedAt.toMillis === "function" &&
      prev.delayedAt.toMillis() === stop.delayedAt.toMillis()
    ) {
      continue; // same delay report as before
    }
    const site = stop.title || "a site";
    const minutes = stop.delayedMinutes;
    await notifyManagers(
      "Stop delayed",
      `${driverName} reported a ${minutes} min delay for ${site}`,
      "stopDelayed",
      { runId: event.params.runId, stopId: stop.id || "" }
    );
    const waitingId = await waitingWorkerIdForStop(stop);
    if (waitingId && waitingId !== after.driverId) {
      const lang = await languageForUser(waitingId);
      await notifyUser(
        waitingId,
        pick(lang, "Arrêt retardé", "Parada retrasada", "Stop delayed"),
        pick(
          lang,
          `${driverName} a signalé un retard de ${minutes} min pour ${site}.`,
          `${driverName} reportó un retraso de ${minutes} min en ${site}.`,
          `${driverName} reported a ${minutes} min delay for ${site}.`
        ),
        "stopDelayed",
        { runId: event.params.runId, stopId: stop.id || "" }
      );
    }
  }
});

// When a task is marked done, its hard dependents become unlocked:
// single-predecessor model, so the just-completed task IS the
// predecessor. Only dependents with an assignee, not already done
// or paused, are notified (in the assignee's profile language).
exports.notifyTaskUnlocked = onDocumentUpdated("tasks/{taskId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after || before.status === "done" || after.status !== "done") return;

  const snap = await db
    .collection("tasks")
    .where("dependsOnTaskId", "==", event.params.taskId)
    .where("dependsSoft", "==", false)
    .get();
  for (const doc of snap.docs) {
    const dependent = doc.data();
    if (dependent.status === "done" || dependent.status === "paused") continue;
    // Every assignee of the unlocked task is told, not just the
    // legacy single assigneeId.
    for (const assigneeId of assigneeIdsOf(dependent)) {
      const lang = await languageForUser(assigneeId);
      const title = dependent.title || pick(lang, "Une tâche", "Una tarea", "A task");
      await notifyUser(
        assigneeId,
        pick(lang, "Tâche débloquée", "Tarea desbloqueada", "Task unlocked"),
        pick(
          lang,
          `${title} — vous pouvez commencer`,
          `${title} — puedes empezar`,
          `${title} — you can start`
        ),
        "taskUnlocked",
        { taskId: doc.id }
      );
    }
  }
});

// One export for both pause transitions: INTO paused notifies the
// assignee the task is paused; OUT of paused (to any other status
// except done — completing a paused task is not a resume) notifies
// them it is resumed. No assignee means no push/doc.
exports.notifyTaskPausedResumed = onDocumentUpdated("tasks/{taskId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after) return;
  if (before.status === after.status) return;

  // Every assignee is told, not just the legacy single one.
  const assigneeIds = assigneeIdsOf(after);
  if (assigneeIds.length === 0) return;

  for (const assigneeId of assigneeIds) {
    const lang = await languageForUser(assigneeId);
    const title =
      after.title || pick(lang, "Une tâche", "Una tarea", "A task");
    if (after.status === "paused" && before.status !== "paused") {
      await notifyUser(
        assigneeId,
        pick(lang, "Tâche mise en pause", "Tarea en pausa", "Task paused"),
        pick(lang, `${title} mise en pause`, `${title} en pausa`, `${title} paused`),
        "taskPaused",
        { taskId: event.params.taskId }
      );
    } else if (before.status === "paused" && after.status !== "paused" && after.status !== "done") {
      await notifyUser(
        assigneeId,
        pick(lang, "Tâche reprise", "Tarea reanudada", "Task resumed"),
        pick(lang, `${title} reprise`, `${title} reanudada`, `${title} resumed`),
        "taskResumed",
        { taskId: event.params.taskId }
      );
    }
  }
});

// A deleted task can no longer be read, so the assignee is
// notified from the deleted snapshot itself.
exports.notifyTaskRemoved = onDocumentDeleted("tasks/{taskId}", async (event) => {
  const task = event.data && event.data.data();
  if (!task) return;
  // Every assignee is told, not just the legacy single one.
  const assigneeIds = assigneeIdsOf(task);
  if (assigneeIds.length === 0) return;
  for (const assigneeId of assigneeIds) {
    const lang = await languageForUser(assigneeId);
    const title = task.title || pick(lang, "Une tâche", "Una tarea", "A task");
    await notifyUser(
      assigneeId,
      pick(lang, "Tâche supprimée", "Tarea eliminada", "Task removed"),
      pick(
        lang,
        `${title} a été supprimée`,
        `${title} fue eliminada`,
        `${title} was removed`
      ),
      "taskRemoved",
      { taskId: event.params.taskId }
    );
  }
});

// When a task is marked done and its stage reaches 100%, the
// NEXT stage is ready to start — admins are told, workers are
// not (their tasks only go live once an admin starts the next
// stage, which fires notifyStageStarted below).
//
// Duplicate guard: the function fires on every task update, so
// two tasks completing at nearly the same time could both see
// the stage at 100% and both notify. The stage doc carries a
// `readyNotifiedTaskIds` marker (the sorted list of done task
// ids at notify time, written by the Admin SDK — never by the
// app). A transaction checks it first: same done set as last
// time means this completion was already announced, so it
// stays silent. The marker only changes when the done set
// changes (a new task added to the stage, or one un-done and
// re-done with a different set), so a genuine re-completion
// still notifies.
exports.notifyStageReady = onDocumentUpdated("tasks/{taskId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after || !after.stageId) return;
  if (before.status === "done" || after.status !== "done") return;

  const stageRef = db.collection("stages").doc(after.stageId);
  const stageSnap = await stageRef.get();
  if (!stageSnap.exists) return;
  const stage = stageSnap.data();

  const stageTasksSnap = await db
    .collection("tasks")
    .where("stageId", "==", after.stageId)
    .get();
  const stageTasks = stageTasksSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
  if (stageTasks.length === 0) return;
  const doneIds = stageTasks
    .filter((t) => t.status === "done")
    .map((t) => t.id)
    .sort();
  if (doneIds.length !== stageTasks.length) return; // not 100% yet

  // The next stage: first stage after this one by order that is
  // not started, not skipped, and not already complete.
  const siteStagesSnap = await db
    .collection("stages")
    .where("siteId", "==", stage.siteId)
    .orderBy("order")
    .get();
  const siteStages = siteStagesSnap.docs.map((d) => ({ id: d.id, ...d.data() }));
  // Scope to this stage's own roadmap: a unit stage's "next" is
  // the next stage of the same unit, a site stage's is the next
  // site stage. Without this, completing a unit stage could
  // announce a stage from another unit (or the site roadmap)
  // as ready to start.
  const scopeStages = siteStages.filter(
    (s) => (s.unitId || null) === (stage.unitId || null)
  );
  const siteTasksSnap = await db
    .collection("tasks")
    .where("siteId", "==", stage.siteId)
    .get();
  const byStage = {};
  for (const doc of siteTasksSnap.docs) {
    const t = doc.data();
    if (!t.stageId) continue;
    (byStage[t.stageId] = byStage[t.stageId] || []).push(t);
  }
  const stageComplete = (s) => {
    const ts = byStage[s.id] || [];
    return ts.length > 0 && ts.every((t) => t.status === "done");
  };
  const idx = scopeStages.findIndex((s) => s.id === after.stageId);
  const next =
    scopeStages
      .slice(idx + 1)
      .find((s) => !s.startedAt && s.skipped !== true && !stageComplete(s)) ||
    null;

  const marker = doneIds.join(",");
  let shouldNotify = false;
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(stageRef);
    const data = snap.data() || {};
    const prevMarker = (data.readyNotifiedTaskIds || []).join(",");
    if (prevMarker === marker) return; // already announced
    tx.update(stageRef, { readyNotifiedTaskIds: doneIds });
    shouldNotify = true;
  });
  if (!shouldNotify) return;

  await notifyManagers(
    `Stage ${stage.name || "?"} complete`,
    next ? `${next.name} is ready to start` : "The roadmap is complete",
    "stageReady",
    { taskId: event.params.taskId }
  );
});

// When a stage is started (startedAt null -> set), its tasks go
// live: notify each distinct assignee of the stage's tasks, in
// their profile language. Tapping the notification opens one of
// their tasks in that stage. Skipping a stage clears startedAt,
// so un-skipping and re-starting notifies again — a genuine
// event, not a duplicate.
exports.notifyStageStarted = onDocumentUpdated("stages/{stageId}", async (event) => {
  const before = event.data.before.data();
  const after = event.data.after.data();
  if (!after) return;
  if (before.startedAt) return; // already started
  if (!after.startedAt) return; // not a start

  const tasksSnap = await db
    .collection("tasks")
    .where("stageId", "==", event.params.stageId)
    .get();
  const assignees = new Map(); // uid -> first task id in the stage
  for (const doc of tasksSnap.docs) {
    const t = doc.data();
    // Every assignee of every task in the stage, not just the
    // legacy single assigneeId.
    for (const assigneeId of assigneeIdsOf(t)) {
      if (!assignees.has(assigneeId)) assignees.set(assigneeId, doc.id);
    }
  }
  for (const [uid, taskId] of assignees) {
    const lang = await languageForUser(uid);
    await notifyUser(
      uid,
      pick(lang, "Étape démarrée", "Etapa iniciada", "Stage started"),
      pick(
        lang,
        `L'étape ${after.name || ""} a démarré — vos tâches sont actives`,
        `La etapa ${after.name || ""} comenzó — tus tareas están activas`,
        `Stage ${after.name || ""} started — your tasks are now live`
      ),
      "stageStarted",
      { taskId }
    );
  }
});

// When a comment/update is added to a task's updates thread,
// the task's assignee AND the managers are told (push + in-app
// doc), each in their profile language. The author is never
// notified: with no assignee, or when the author IS the
// assignee, the managers alone are notified. Recipients are
// deduplicated, so a manager who is also the assignee gets
// exactly one notification.
//
// Managers are notified one by one via notifyUser (personal
// topic) rather than the shared 'managers' topic, because the
// topic carries a single wording and each manager's wording
// must follow their own profile language. Every signed-in user
// subscribes to their personal topic, so no manager is missed.
//
// The comment text is quoted in the body, truncated to 200
// characters so a long comment cannot blow the FCM payload
// limit; a photo-only update (empty text) names the commenter
// and the task instead.
exports.notifyTaskComment = onDocumentCreated(
  "tasks/{taskId}/updates/{updateId}",
  async (event) => {
    const update = event.data && event.data.data();
    if (!update) return;
    const taskId = event.params.taskId;

    const taskSnap = await db.collection("tasks").doc(taskId).get();
    if (!taskSnap.exists) return;
    const task = taskSnap.data();
    const authorId = update.authorId || null;
    const authorName = (update.authorName || "").trim();
    const commentText = (update.text || "").trim();

    const recipients = new Set();
    // Every assignee of the task, not just the legacy single
    // assigneeId; the author is never notified.
    for (const assigneeId of assigneeIdsOf(task)) {
      if (assigneeId !== authorId) recipients.add(assigneeId);
    }
    const managersSnap = await db
      .collection("users")
      .where("role", "in", ["admin", "manager"])
      .get();
    for (const doc of managersSnap.docs) {
      if (doc.id === authorId) continue; // never notify the author
      recipients.add(doc.id);
    }
    if (recipients.size === 0) return;

    for (const uid of recipients) {
      const lang = await languageForUser(uid);
      const title = task.title || pick(lang, "Une tâche", "Una tarea", "A task");
      const who = authorName || pick(lang, "Quelqu'un", "Alguien", "Someone");
      const quoted =
        commentText.length > 200
          ? `${commentText.slice(0, 200)}…`
          : commentText;
      const body = quoted
        ? pick(
            lang,
            `${who} sur ${title} : ${quoted}`,
            `${who} en ${title}: ${quoted}`,
            `${who} on ${title}: ${quoted}`
          )
        : pick(
            lang,
            `${who} a commenté ${title}`,
            `${who} comentó en ${title}`,
            `${who} commented on ${title}`
          );
      await notifyUser(
        uid,
        pick(lang, "Nouveau commentaire", "Nuevo comentario", "New comment"),
        body,
        "taskComment",
        { taskId }
      );
    }
  }
);

// Chat messages: notify every other participant, each in their
// profile language. Team channels are titled with the team
// name; DMs and broadcasts are titled with the sender's name.
// The author is never notified. The conversation id travels
// in the push data and on the notification doc so tapping it
// opens the chat.
exports.notifyChatMessage = onDocumentCreated(
  "conversations/{conversationId}/messages/{messageId}",
  async (event) => {
    const message = event.data && event.data.data();
    if (!message) return;
    const conversationId = event.params.conversationId;

    const convSnap = await db
      .collection("conversations")
      .doc(conversationId)
      .get();
    if (!convSnap.exists) return;
    const conv = convSnap.data();
    const senderId = message.senderId || null;
    const senderName = (message.senderName || "").trim();
    const text = (message.text || "").trim();
    // A media-only message has no text: push its label
    // ("[Photo]" / "[Video]" / "[Voice note]", in the
    // recipient's language) instead of an empty quote.
    const mediaLabel =
      message.mediaType === "video"
        ? "[Video]"
        : message.mediaType === "audio"
          ? "[Voice note]"
          : message.mediaType === "image"
            ? "[Photo]"
            : null;
    if (!text && !mediaLabel) return;

    // Deduplicated: a participant listed twice gets one push,
    // not two (the same dedupe the broadcast path applies).
    const recipients = [
      ...new Set(
        (conv.participantIds || []).filter((uid) => uid && uid !== senderId)
      ),
    ];
    if (recipients.length === 0) return;

    const quoted =
      text.length > 200 ? `${text.slice(0, 200)}…` : text;
    for (const uid of recipients) {
      const lang = await languageForUser(uid);
      const who = senderName || pick(lang, "Quelqu'un", "Alguien", "Someone");
      const title =
        conv.type === "team"
          ? conv.title ||
            pick(lang, "Discussion d'équipe", "Chat de equipo", "Team chat")
          : who;
      // Media-only: the label, localized (FR: [Photo] /
      // [Vidéo] / [Message vocal]; ES: [Photo] / [Video] /
      // [Mensaje de voz]); a captioned media keeps the text quote.
      const shown = text
        ? quoted
        : pick(
            lang,
            mediaLabel === "[Video]"
              ? "[Vidéo]"
              : mediaLabel === "[Voice note]"
                ? "[Message vocal]"
                : mediaLabel,
            mediaLabel === "[Voice note]" ? "[Mensaje de voz]" : mediaLabel,
            mediaLabel
          );
      const body = pick(lang, `${who} : ${shown}`, `${who}: ${shown}`, `${who}: ${shown}`);
      await notifyUser(
        uid,
        title,
        body,
        "chatMessage",
        { conversationId }
      );
    }
  }
);

// Material requests: a worker asks for materials (created on
// `materialRequests`) — the managers get the alert, in English
// like the other manager alerts, with the requester, item,
// quantity and site. The request's task id travels in the push
// extra so tapping it opens the task (site-level requests have
// none and open nothing).
exports.notifyMaterialRequestCreated = onDocumentCreated(
  "materialRequests/{requestId}",
  async (event) => {
    const request = event.data && event.data.data();
    if (!request) return;
    const siteName = await siteNameFor(request.siteId);
    const who = (request.requesterName || "").trim() || "Someone";
    const what = `${request.quantity} × ${request.item || "materials"}`;
    const where = siteName ? ` for ${siteName}` : "";
    await notifyManagers(
      "New material request",
      `${who} needs ${what}${where}`,
      "materialRequested",
      {
        taskId: request.taskId || null,
        materialRequestId: event.params.requestId,
      }
    );
  }
);

// Material requests: a manager approves or denies a request
// (status requested -> approved / denied) — the requester gets
// the outcome in their profile language, with the deny reason
// when denied. Only the requested -> approved / requested ->
// denied transitions notify; later status moves (approved ->
// onRun -> delivered) are covered by the queue screen and by
// notifyStopCompleted, so a request never double-notifies.
exports.notifyMaterialRequestDecided = onDocumentUpdated(
  "materialRequests/{requestId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!after) return;
    if ((before && before.status) !== "requested") return;
    const status = after.status;
    if (status !== "approved" && status !== "denied") return;
    const requesterId = after.requesterId || null;
    if (!requesterId) return;
    const lang = await languageForUser(requesterId);
    const what = `${after.quantity} × ${after.item || "materials"}`;
    const title =
      status === "approved"
        ? pick(lang, "Demande de matériaux approuvée", "Solicitud de materiales aprobada", "Material request approved")
        : pick(lang, "Demande de matériaux refusée", "Solicitud de materiales rechazada", "Material request denied");
    let body;
    if (status === "approved") {
      body = pick(
        lang,
        `Votre demande de ${what} a été approuvée. Elle sera ajoutée à une tournée.`,
        `Tu solicitud de ${what} fue aprobada. Se agregará a un recorrido.`,
        `Your request for ${what} was approved. It will be added to a delivery run.`
      );
    } else {
      const reason = (after.denyReason || "").trim();
      body = reason
        ? pick(
            lang,
            `Votre demande de ${what} a été refusée : ${reason}`,
            `Tu solicitud de ${what} fue rechazada: ${reason}`,
            `Your request for ${what} was denied: ${reason}`
          )
        : pick(
            lang,
            `Votre demande de ${what} a été refusée.`,
            `Tu solicitud de ${what} fue rechazada.`,
            `Your request for ${what} was denied.`
          );
    }
    await notifyUser(
      requesterId,
      title,
      body,
      status === "approved" ? "materialApproved" : "materialDenied",
      {
        taskId: after.taskId || null,
        materialRequestId: event.params.requestId,
      }
    );
  }
);

// --- Clock-in / clock-out (job 19) ----------------------------
// When a worker clocks in or out, every admin and manager is
// told, each in their profile language. Recipients are gathered
// the notifyTaskComment way — one notifyUser call per admin /
// manager — because the shared 'managers' topic carries a
// single wording and cannot vary it per recipient (notifyManagers
// is English-only). The worker is never notified about their
// own clock-in/out. The notification doc carries the entry id,
// worker, site and the GPS coordinates of THIS event (clock-in
// coords for a clock-in, clock-out coords for a clock-out;
// null when the app captured none — never invented).
async function sendClockEvent(entryId, entry, isClockOut) {
  const actorId = entry.userId || null;
  const managersSnap = await db
    .collection("users")
    .where("role", "in", ["admin", "manager"])
    .get();
  const recipients = new Set();
  for (const doc of managersSnap.docs) {
    if (doc.id === actorId) continue; // never notify the actor
    recipients.add(doc.id);
  }
  if (recipients.size === 0) return;

  const who = (entry.userName || "").trim() || "Someone";
  const site = (entry.siteName || "").trim();
  const lat = isClockOut
    ? (entry.clockOutLat ?? null)
    : (entry.clockInLat ?? null);
  const lng = isClockOut
    ? (entry.clockOutLng ?? null)
    : (entry.clockInLng ?? null);
  const type = isClockOut ? "clockOut" : "clockIn";
  for (const uid of recipients) {
    const lang = await languageForUser(uid);
    const where = site
      ? pick(lang, ` à ${site}`, ` en ${site}`, ` at ${site}`)
      : "";
    const title = isClockOut
      ? pick(lang, "Fin de journée", "Fin de jornada", "Clock-out")
      : pick(lang, "Début de journée", "Inicio de jornada", "Clock-in");
    const body = isClockOut
      ? pick(
          lang,
          `${who} a terminé sa journée${where}.`,
          `${who} terminó su jornada${where}.`,
          `${who} clocked out${where}.`
        )
      : pick(
          lang,
          `${who} a commencé sa journée${where}.`,
          `${who} comenzó su jornada${where}.`,
          `${who} clocked in${where}.`
        );
    await notifyUser(uid, title, body, type, {
      timeEntryId: entryId,
      userName: entry.userName || null,
      siteId: entry.siteId || null,
      siteName: entry.siteName || null,
      lat,
      lng,
    });
  }
}

// A new timeEntry IS a clock-in: notify the admins and managers.
exports.notifyClockIn = onDocumentCreated(
  "timeEntries/{entryId}",
  async (event) => {
    const entry = event.data && event.data.data();
    if (!entry) return;
    await sendClockEvent(event.params.entryId, entry, false);
  }
);

// A clock-out is the clockOutAt null -> set transition only.
// Any other timeEntry update (time edits, site changes, flag
// changes) stays silent, and an entry that already has a
// clock-out never notifies again — the before/after check is
// the duplicate guard, the same pattern as notifyDriverArrived
// (arrivedAt) and notifyStageStarted (startedAt). Entries the
// 23:59 auto-close shut (flagReason 'auto-closed') never push:
// the close was the scheduler's doing, not a worker tapping out.
exports.notifyClockOut = onDocumentUpdated(
  "timeEntries/{entryId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!after) return;
    if (before && before.clockOutAt) return; // already clocked out
    if (!after.clockOutAt) return; // not a clock-out
    if (after.flagReason === "auto-closed") return; // scheduler close, no push
    // An AUTO entry closed <10 min after it opened is a
    // drive-by: verifyClockOut deletes it outright, so no push
    // may fire for it — the entry never reaches Hours or
    // payroll. The same check also covers the race where the
    // delete already landed: re-read, and stay silent when the
    // entry is gone.
    if (
      isShortAutoEntry(
        after.auto === true,
        timestampMs(after.clockInAt),
        timestampMs(after.clockOutAt)
      )
    ) {
      return;
    }
    const live = await db
      .collection("timeEntries")
      .doc(event.params.entryId)
      .get();
    if (!live.exists) return;
    await sendClockEvent(event.params.entryId, after, true);
  }
);

// --- Auth blocking: invite-only sign-up (job 21) ------------
// IMPORTANT — this function ONLY runs once Identity Platform
// is enabled in the Firebase console: Firebase console >
// Authentication > Get started (this enables Identity
// Platform). Until that step is done, sign-ups are NOT blocked
// by this function — do NOT claim invite-only sign-up works
// until Identity Platform is enabled. The app's in-app invite
// check (AuthService.findInvite, which marks the invite
// 'accepted' after sign-up) is kept as defense in depth and
// must NOT be removed.
exports.blockBeforeUserCreated = beforeUserCreated(async (event) => {
  const email = ((event.data && event.data.email) || "").trim();
  if (!email) {
    throw new HttpsError(
      "permission-denied",
      "No invite found for this email. Ask an admin to invite you first."
    );
  }
  const invites = db.collection("invites");
  // Invites are stored trimmed; bulk invites are lowercased,
  // single invites are not — try the exact email first, then
  // the lowercased form, so a differently-cased sign-up still
  // matches its invite.
  let inviteRef = null;
  const byExact = await invites
    .where("email", "==", email)
    .where("status", "==", "pending")
    .limit(1)
    .get();
  if (!byExact.empty) {
    inviteRef = byExact.docs[0].ref;
  } else {
    const lower = email.toLowerCase();
    if (lower !== email) {
      const byLower = await invites
        .where("email", "==", lower)
        .where("status", "==", "pending")
        .limit(1)
        .get();
      if (!byLower.empty) inviteRef = byLower.docs[0].ref;
    }
  }
  if (!inviteRef) {
    throw new HttpsError(
      "permission-denied",
      "No invite found for this email. Ask an admin to invite you first."
    );
  }
  // Consume the invite here, inside the blocking function: the
  // app marks it 'accepted' only via the app sign-up flow, so
  // a direct-Auth-API sign-up used to leave the invite pending
  // and reusable. Marking it now means one invite admits one
  // account, whichever sign-up path was used.
  await inviteRef.update({
    status: "accepted",
    acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
  });
});

// --- Server-side clock verification + hours (job 20) ---------
// The phone no longer computes anything: it writes
// clockInVerified=false, flagged=false, no hours at create,
// and only clockOutAt at close. These two functions compute
// the truth from the site's stored coordinates (sites/{siteId}
// lat/lng, per-site radius — 100 m default) and overwrite
// whatever an old client wrote, so hours and flags always
// come from the server.

// Haversine distance in metres between two lat/lng points.
function haversineMeters(lat1, lng1, lat2, lng2) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a =
    Math.sin(dLat / 2) * Math.sin(dLat / 2) +
    Math.cos(toRad(lat1)) *
      Math.cos(toRad(lat2)) *
      Math.sin(dLng / 2) *
      Math.sin(dLng / 2);
  return 2 * R * Math.asin(Math.sqrt(a));
}

// One GPS fix against the site. `outsideReason` is the
// flagReason when the fix is outside the radius
// ('outside-radius' at clock-in, 'clock-out-outside-radius'
// at clock-out — the codes AppStrings.flagReasonLabel maps).
// A fix is unverified when the site has no location, the fix
// is missing, or it is outside the site's radius (the stored
// radiusMeters, 100 m default — see clock_rules).
function verifyFix(lat, lng, site, outsideReason) {
  if (site == null || site.lat == null || site.lng == null) {
    return { verified: false, flagReason: "no-site-location" };
  }
  if (lat == null || lng == null) {
    return { verified: false, flagReason: "no-location" };
  }
  if (haversineMeters(lat, lng, site.lat, site.lng) <= radiusForSite(site)) {
    return { verified: true, flagReason: null };
  }
  return { verified: false, flagReason: outsideReason };
}

// Hours between two Firestore Timestamps, rounded to 2
// decimals (same rounding as the app's hoursSoFar). Null when
// either end is missing; never negative.
function hoursBetween(startTs, endTs) {
  if (!startTs || !endTs) return null;
  const ms = endTs.toMillis() - startTs.toMillis();
  if (ms <= 0) return 0;
  return Math.round((ms / 3600000) * 100) / 100;
}

// The site doc for an entry, or null when it cannot be read
// (verifyFix then reports 'no-site-location').
async function siteForEntry(entry) {
  if (!entry || !entry.siteId) return null;
  try {
    const snap = await db.collection("sites").doc(entry.siteId).get();
    return snap.exists ? snap.data() : null;
  } catch (_) {
    return null;
  }
}

// On create: verify the clock-in fix and force hours to null
// (the entry is still open). Overwrites clockInVerified /
// flagged / flagReason / hours even if an old client wrote
// its own values.
exports.verifyClockEntry = onDocumentCreated(
  "timeEntries/{entryId}",
  async (event) => {
    const entry = event.data && event.data.data();
    if (!entry) return;
    const site = await siteForEntry(entry);
    const check = verifyFix(
      entry.clockInLat,
      entry.clockInLng,
      site,
      "outside-radius"
    );
    await event.data.ref.update({
      clockInVerified: check.verified,
      flagged: !check.verified,
      flagReason: check.flagReason,
      hours: null,
    });
  }
);

// On update where clockOutAt changed (null -> set, or a time
// edit): recompute hours from clockInAt/clockOutAt and
// re-verify BOTH fixes, then write hours / clockInVerified /
// clockOutVerified / flagged / flagReason.
//
// LOOP GUARD: this function returns early whenever clockOutAt
// did not change. Its own writes never touch clockOutAt, so
// they can never re-trigger a recompute; neither can flag
// edits, site changes, or any other timeEntry update. The
// 'auto-closed' marker set by autoCloseOpenEntries is
// preserved: the entry stays flagged with that reason even
// though the GPS checks are still recomputed.
exports.verifyClockOut = onDocumentUpdated(
  "timeEntries/{entryId}",
  async (event) => {
    const before = event.data.before.data();
    const after = event.data.after.data();
    if (!after) return;
    const beforeOut = before && before.clockOutAt;
    const afterOut = after.clockOutAt;
    const outChanged =
      (beforeOut ? beforeOut.toMillis() : null) !==
      (afterOut ? afterOut.toMillis() : null);
    if (!outChanged) return; // own write or unrelated edit
    if (!afterOut) {
      // Clock-out cleared (a manager reopened the entry): the
      // completed-entry hours no longer apply. The client is
      // forbidden from clearing them under the new rules, so
      // the server does it here; they are recomputed at the
      // next clock-out. (This write does not change clockOutAt,
      // so the loop guard above stops it re-triggering.)
      await event.data.after.ref.update({ hours: null });
      return;
    }

    // Atto's 10-minute rule: an AUTO entry closed less than 10
    // minutes after it opened is a drive-by, not work — delete
    // it outright, entry and route breadcrumbs together.
    // Manual entries are never deleted this way. (A push may
    // still fire from notifyClockOut for the same update —
    // harmless: it reports a clock-out that happened, and the
    // short entry never reaches Hours or payroll.)
    if (
      isShortAutoEntry(
        after.auto === true,
        timestampMs(after.clockInAt),
        timestampMs(afterOut)
      )
    ) {
      const crumbs = await event.data.after.ref
        .collection("breadcrumbs")
        .get();
      const batch = db.batch();
      crumbs.docs.forEach((d) => batch.delete(d.ref));
      batch.delete(event.data.after.ref);
      await batch.commit();
      return;
    }

    const site = await siteForEntry(after);
    const inCheck = verifyFix(
      after.clockInLat,
      after.clockInLng,
      site,
      "outside-radius"
    );
    const outCheck = verifyFix(
      after.clockOutLat,
      after.clockOutLng,
      site,
      "clock-out-outside-radius"
    );
    const autoClosed = after.flagReason === "auto-closed";
    // The clock-out reason wins when the clock-out failed;
    // otherwise the clock-in reason stands; null when both
    // fixes verified.
    const flagReason = autoClosed
      ? "auto-closed"
      : !outCheck.verified
        ? outCheck.flagReason
        : inCheck.flagReason;
    await event.data.after.ref.update({
      clockInVerified: inCheck.verified,
      clockOutVerified: outCheck.verified,
      flagged: autoClosed ? true : !inCheck.verified || !outCheck.verified,
      flagReason,
      hours: hoursBetween(after.clockInAt, afterOut),
    });
  }
);

// --- Scheduled auto-close of open entries (job 22) -----------
// Every day at 23:59 Toronto time, close every timeEntry still
// open whose Toronto clock-in date is today or earlier.
// clockOutAt is 23:59 Toronto time ON THE ENTRY'S OWN DAY
// (built with torontoWallTimeToDate — never server-local
// midnight), flagged with reason 'auto-closed', hours computed
// from clockInAt. Verified flags are left exactly as the
// verification functions set them. No push is sent for
// auto-closes (notifyClockOut skips flagReason 'auto-closed').
// Entries with a future date (bad phone clock) are left alone.
exports.autoCloseOpenEntries = onSchedule(
  { schedule: "59 23 * * *", timeZone: "America/Toronto" },
  async () => {
    const todayId = torontoDateId(new Date());
    const snap = await db
      .collection("timeEntries")
      .where("clockOutAt", "==", null)
      .get();
    const open = snap.docs.filter((doc) => {
      const data = doc.data();
      // `date` is the Toronto yyyy-MM-dd clock-in date the app
      // wrote; a plain string compare IS a Toronto calendar
      // compare. Fall back to the clock-in timestamp when the
      // field is missing.
      const entryDate =
        typeof data.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(data.date)
          ? data.date
          : data.clockInAt
            ? torontoDateId(data.clockInAt.toDate())
            : null;
      return entryDate != null && entryDate <= todayId;
    });
    // Batch writes, 500 per batch (the Firestore batch limit).
    // Open site visits on each closed entry are closed in the
    // same pass (leftAt = the 23:59 close, duration from
    // arrival): the client only ever closes visits for entries
    // it watches, so without this an auto-closed day left its
    // visits open ("Here now") forever.
    const writes = []; // { ref, data } in entry order
    for (const doc of open) {
      const data = doc.data();
      const parts =
        typeof data.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(data.date)
          ? data.date.split("-").map(Number)
          : (() => {
              const p = torontoParts(data.clockInAt.toDate());
              return [p.y, p.m, p.d];
            })();
      const closeAt = admin.firestore.Timestamp.fromDate(
        torontoWallTimeToDate(parts[0], parts[1], parts[2], 23, 59)
      );
      writes.push({
        ref: doc.ref,
        data: {
          clockOutAt: closeAt,
          flagged: true,
          flagReason: "auto-closed",
          hours: hoursBetween(data.clockInAt, closeAt),
        },
      });
      const visitsSnap = await doc.ref
        .collection("siteVisits")
        .where("leftAt", "==", null)
        .get();
      for (const visit of visitsSnap.docs) {
        const v = visit.data();
        const arrivedMs =
          v.arrivedAt && typeof v.arrivedAt.toMillis === "function"
            ? v.arrivedAt.toMillis()
            : null;
        writes.push({
          ref: visit.ref,
          data: {
            leftAt: closeAt,
            durationMinutes:
              arrivedMs == null
                ? null
                : Math.max(
                    0,
                    Math.round(
                      (closeAt.toMillis() - arrivedMs) / 60000
                    )
                  ),
          },
        });
      }
    }
    for (let i = 0; i < writes.length; i += 500) {
      const batch = db.batch();
      for (const w of writes.slice(i, i + 500)) {
        batch.update(w.ref, w.data);
      }
      await batch.commit();
    }
  }
);

// --- Still-clocked-in reminder (job 25) ----------------------
// Every day at 18:00 Toronto time, nudge every worker whose
// time entry opened TODAY (Toronto date) and is still open:
// the worker gets a push + in-app notification ("Still clocked
// in" — tap opens the entry's map, like a clock-out), and the
// admins/managers are told the worker is still clocked in.
// Entries opened after 18:00 cannot exist at run time, and
// entries from earlier days are not today's shift, so neither
// is notified. Notification type: `stillClockedIn` (no pref
// toggle — it always sends, like the other clock event types
// the client routes by timeEntryId).
exports.notifyStillClockedIn = onSchedule(
  { schedule: "0 18 * * *", timeZone: "America/Toronto" },
  async () => {
    const todayId = torontoDateId(new Date());
    const snap = await db
      .collection("timeEntries")
      .where("clockOutAt", "==", null)
      .get();
    const stillOpen = snap.docs.filter((doc) => {
      const data = doc.data();
      const entryDate =
        typeof data.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(data.date)
          ? data.date
          : data.clockInAt
            ? torontoDateId(data.clockInAt.toDate())
            : null;
      return entryDate === todayId;
    });
    if (stillOpen.length === 0) return;
    const managersSnap = await db
      .collection("users")
      .where("role", "in", ["admin", "manager"])
      .get();
    const managerIds = managersSnap.docs.map((d) => d.id);
    for (const doc of stillOpen) {
      const entry = doc.data();
      const workerId = entry.userId || null;
      if (!workerId) continue;
      const who = (entry.userName || "").trim() || "Someone";
      const site = (entry.siteName || "").trim();
      // The worker's own nudge.
      const workerLang = await languageForUser(workerId);
      await notifyUser(
        workerId,
        pick(
          workerLang,
          "Toujours pointé",
          "Todavía registrado",
          "Still clocked in"
        ),
        pick(
          workerLang,
          "Vous êtes toujours pointé — pensez à pointer votre sortie.",
          "Todavía estás registrado — no olvides registrar tu salida.",
          "You're still clocked in — clock out?"
        ),
        "stillClockedIn",
        {
          timeEntryId: doc.id,
          userName: entry.userName || null,
          siteId: entry.siteId || null,
          siteName: entry.siteName || null,
          lat: entry.clockInLat ?? null,
          lng: entry.clockInLng ?? null,
        }
      );
      // The admins/managers, each in their own language
      // (never the worker about their own shift).
      for (const uid of managerIds) {
        if (uid === workerId) continue;
        const lang = await languageForUser(uid);
        const where = site
          ? pick(lang, ` à ${site}`, ` en ${site}`, ` at ${site}`)
          : "";
        await notifyUser(
          uid,
          pick(
            lang,
            "Toujours pointé",
            "Todavía registrado",
            "Still clocked in"
          ),
          pick(
            lang,
            `${who} est toujours pointé${where}.`,
            `${who} todavía está registrado${where}.`,
            `${who} is still clocked in${where}.`
          ),
          "stillClockedIn",
          {
            timeEntryId: doc.id,
            userName: entry.userName || null,
            siteId: entry.siteId || null,
            siteName: entry.siteName || null,
            lat: entry.clockInLat ?? null,
            lng: entry.clockInLng ?? null,
          }
        );
      }
    }
  }
);

// --- Notification retention (job 23) --------------------------
// Every day at 03:00 Toronto time, delete `notifications` docs
// with createdAt older than 30 days, in batches of 500. Docs
// without a createdAt (never written by writeNotification)
// are left alone.
exports.pruneOldNotifications = onSchedule(
  { schedule: "0 3 * * *", timeZone: "America/Toronto" },
  async () => {
    const cutoff = admin.firestore.Timestamp.fromDate(
      new Date(Date.now() - 30 * 24 * 60 * 60 * 1000)
    );
    let last = null;
    for (;;) {
      let query = db
        .collection("notifications")
        .where("createdAt", "<", cutoff)
        .orderBy("createdAt")
        .limit(500);
      if (last) query = query.startAfter(last);
      const snap = await query.get();
      if (snap.empty) break;
      const batch = db.batch();
      for (const doc of snap.docs) batch.delete(doc.ref);
      await batch.commit();
      last = snap.docs[snap.docs.length - 1];
      if (snap.size < 500) break;
    }
  }
);

// --- Admin-only user deactivation (extra) ---------------------
// Disables a Firebase Auth user and revokes their refresh
// tokens, so they are signed out everywhere and cannot sign
// back in. Only an admin (users/{uid}.role == 'admin') may
// call it. The profile is deactivated HERE (users/{uid}
// active = false) — callers used to be trusted to do it, and
// any caller that forgot left a disabled Auth account with a
// live profile. Raw errors are never returned: the client
// gets a generic message, and the detail goes to the logs.
exports.disableUser = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to disable a user.");
  }
  const callerSnap = await db
    .collection("users")
    .doc(request.auth.uid)
    .get();
  if (!callerSnap.exists || callerSnap.data().role !== "admin") {
    throw new HttpsError(
      "permission-denied",
      "Only an admin can disable a user."
    );
  }
  const targetUid = request.data && request.data.targetUid;
  if (typeof targetUid !== "string" || !targetUid.trim()) {
    throw new HttpsError(
      "invalid-argument",
      "targetUid must be a non-empty string."
    );
  }
  try {
    await admin.auth().updateUser(targetUid, { disabled: true });
    await admin.auth().revokeRefreshTokens(targetUid);
    // Deactivate the profile in the same call, so the account
    // is unusable from both sides even if the caller never
    // touches the users doc. Merge-set: a missing doc still
    // gets the flag rather than failing the whole call.
    await db.collection("users").doc(targetUid).set(
      { active: false },
      { merge: true }
    );
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("disableUser failed for", targetUid, e);
    throw new HttpsError("internal", "Could not disable the user.");
  }
  return { ok: true };
});

// --- Self-service account deletion ---------------------------
// A user deletes their OWN account (Settings → Account →
// Delete my account). Removes: the Firebase Auth user, the
// users/{uid} doc, the profile photo, the user's notification
// docs, their team memberships (teams memberIds) and their
// pending invites. Does NOT delete time entries (payroll
// records), tasks or chat messages — those are shared records
// and stay, with the name on them showing as "Former member".
// Chat/task photos are retained too (the original spec).
// The Auth user is deleted FIRST: if an earlier ordering
// deleted the profile doc and the Auth delete then failed, the
// user could still sign in with no profile (sign-in loop);
// with Auth gone first, any failure after it leaves only
// orphaned docs behind a login that no longer exists, and
// every later step is best-effort so one failure cannot abort
// the rest of the cleanup. FCM topics cannot be left
// server-side (no device tokens are stored); the client
// unsubscribes on sign-out, which always precedes a delete.
exports.deleteMyAccount = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to delete your account.");
  }
  const uid = request.auth.uid;
  let email = null;
  try {
    const record = await admin.auth().getUser(uid);
    email = (record.email || "").trim().toLowerCase() || null;
  } catch (e) {
    console.error("deleteMyAccount: could not read Auth user", uid, e);
  }
  try {
    // Auth user first — see the ordering note above.
    await admin.auth().deleteUser(uid);
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    console.error("deleteMyAccount: Auth delete failed", uid, e);
    throw new HttpsError("internal", "Could not delete the account.");
  }
  // Best-effort cleanup from here: the account is already
  // gone, so a failure must not fail the call — it is logged
  // and the rest still runs.
  const failures = [];
  const attempt = async (label, fn) => {
    try {
      await fn();
    } catch (e) {
      failures.push(label);
      console.error(`deleteMyAccount: ${label} failed for`, uid, e);
    }
  };
  await attempt("notifications", async () => {
    for (;;) {
      const snap = await db
        .collection("notifications")
        .where("userId", "==", uid)
        .limit(500)
        .get();
      if (snap.empty) break;
      const batch = db.batch();
      for (const doc of snap.docs) batch.delete(doc.ref);
      await batch.commit();
      if (snap.size < 500) break;
    }
  });
  await attempt("profile doc", async () => {
    await db.collection("users").doc(uid).delete();
  });
  await attempt("profile photo", async () => {
    try {
      await admin
        .storage()
        .bucket()
        .file(`profilePhotos/${uid}.jpg`)
        .delete();
    } catch (e) {
      if (e.code !== 404) throw e;
    }
  });
  await attempt("team memberships", async () => {
    const snap = await db
      .collection("teams")
      .where("memberIds", "array-contains", uid)
      .get();
    for (const doc of snap.docs) {
      await doc.ref.update({
        memberIds: admin.firestore.FieldValue.arrayRemove([uid]),
      });
    }
  });
  if (email) {
    await attempt("pending invites", async () => {
      const snap = await db
        .collection("invites")
        .where("email", "==", email)
        .where("status", "==", "pending")
        .get();
      for (const doc of snap.docs) await doc.ref.delete();
    });
  }
  return { ok: true, cleanupFailures: failures };
});
