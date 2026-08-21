import * as admin from "firebase-admin";
import { setGlobalOptions } from "firebase-functions/v2";
import {
  onDocumentCreated,
  onDocumentUpdated,
  onDocumentWritten,
} from "firebase-functions/v2/firestore";

import { adminIds, describeAssignees, notify, notifyMany, projectOverseerIds } from "./notify";

admin.initializeApp();
setGlobalOptions({ region: "us-central1", maxInstances: 10 });

/** New task assignments push a notification to each newly-added assignee. */
export const onTaskAssigneesChanged = onDocumentWritten("tasks/{taskId}", async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!after) return; // task deleted

  const beforeAssignees: string[] = before?.assigneeIds ?? [];
  const afterAssignees: string[] = after.assigneeIds ?? [];
  const newlyAssigned = afterAssignees.filter((id) => !beforeAssignees.includes(id));
  if (newlyAssigned.length === 0) return;

  await notifyMany(newlyAssigned, {
    type: "task_assigned",
    title: "New task assigned",
    body: after.title ? `You were assigned "${after.title}"` : "You were assigned a new task",
    deepLink: `/task/${event.params.taskId}`,
  });
});

/** A task moving to in-progress or done notifies the project's managers and
 *  admins (project-less quick-assigned tasks fall back to just admins) —
 *  not the assignee(s) whose own status change this is. */
export const onTaskStatusChanged = onDocumentUpdated("tasks/{taskId}", async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after) return;
  if (before.status === after.status) return;
  if (after.status !== "in-progress" && after.status !== "done") return;

  const assigneeIds: string[] = after.assigneeIds ?? [];
  const overseerIds = after.projectId
    ? await projectOverseerIds(after.projectId)
    : await adminIds();
  const recipients = overseerIds.filter((id) => !assigneeIds.includes(id));
  if (recipients.length === 0) return;

  const who = await describeAssignees(assigneeIds);
  const taskTitle = after.title ? `"${after.title}"` : "a task";
  const verb = after.status === "in-progress" ? "started" : "finished";

  await notifyMany(recipients, {
    type: "task_status_changed",
    title: after.status === "in-progress" ? "Task started" : "Task completed",
    body: `${who} ${verb} ${taskTitle}`,
    deepLink: `/task/${event.params.taskId}`,
  });
});

/** A submitted material request notifies the project's managers + admins. */
export const onMaterialRequestCreated = onDocumentCreated(
  "materialRequests/{requestId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const overseerIds = await projectOverseerIds(data.projectId);
    const recipients = overseerIds.filter((id) => id !== data.requestedById);
    if (recipients.length === 0) return;

    await notifyMany(recipients, {
      type: "material_request_submitted",
      title: "New material request",
      body: `${data.requestedByName ?? "Someone"} submitted a material request`,
      deepLink: `/material-requests/${event.params.requestId}`,
    });
  }
);

/** A status decision on a material request notifies the original requester. */
export const onMaterialRequestDecided = onDocumentUpdated(
  "materialRequests/{requestId}",
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;
    if (before.status === after.status) return;

    await notify({
      recipientId: after.requestedById,
      type: "material_request_decided",
      title: "Material request updated",
      body: `Your material request was marked ${after.status}`,
      deepLink: `/material-requests/${event.params.requestId}`,
    });
  }
);

/** A submitted daily report notifies the project's managers and every admin. */
export const onDailyReportCreated = onDocumentCreated(
  "dailyReports/{reportId}",
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const overseerIds = await projectOverseerIds(data.projectId);
    const recipients = overseerIds.filter((id) => id !== data.submittedById);
    if (recipients.length === 0) return;

    await notifyMany(recipients, {
      type: "daily_report_submitted",
      title: "New daily report",
      body: `${data.submittedByName ?? "Someone"} submitted a daily report`,
      deepLink: `/daily-reports/${event.params.reportId}`,
    });
  }
);

/** An admin changing someone's role or project assignment notifies them. */
export const onEmployeeAssignmentChanged = onDocumentUpdated(
  "employees/{uid}",
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();
    if (!before || !after) return;

    const roleChanged = before.role !== after.role;
    const projectsChanged =
      JSON.stringify([...(before.projectIds ?? [])].sort()) !==
      JSON.stringify([...(after.projectIds ?? [])].sort());
    if (!roleChanged && !projectsChanged) return;

    const parts: string[] = [];
    if (roleChanged) parts.push(`your role is now ${after.role}`);
    if (projectsChanged) parts.push("your project assignments were updated");

    await notify({
      recipientId: event.params.uid,
      type: "staff_assignment_changed",
      title: "Your assignment was updated",
      body: `An admin updated your account — ${parts.join(" and ")}.`,
    });
  }
);
