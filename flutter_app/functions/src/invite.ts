import * as admin from "firebase-admin";
import { HttpsError, onCall } from "firebase-functions/v2/https";

const INVITABLE_ROLES = ["employee", "manager", "admin"];

interface InviteStaffRequest {
  email: string;
  firstName: string;
  lastName: string;
  role: string;
  projectIds?: string[];
}

/** Admin-only: creates a staff account (Auth user + `employees/{uid}` doc)
 *  server-side, bypassing the self-signup rule that only ever allows a user
 *  to create their own doc as a plain client. The invitee sets their own
 *  password afterward via Firebase's hosted password-reset email, triggered
 *  client-side once this call succeeds. */
export const inviteStaff = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "You must be signed in to invite staff.");
  }

  const callerDoc = await admin.firestore().collection("employees").doc(request.auth.uid).get();
  if (callerDoc.data()?.role !== "admin") {
    throw new HttpsError("permission-denied", "Only an admin can invite staff.");
  }

  const data = request.data as Partial<InviteStaffRequest>;
  const email = data.email?.trim();
  const firstName = data.firstName?.trim();
  const lastName = data.lastName?.trim();
  const role = data.role;
  const projectIds = data.projectIds ?? [];

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpsError("invalid-argument", "Please provide a valid email address.");
  }
  if (!firstName) {
    throw new HttpsError("invalid-argument", "Please provide a first name.");
  }
  if (!role || !INVITABLE_ROLES.includes(role)) {
    throw new HttpsError("invalid-argument", "Please provide a valid role.");
  }
  if (!Array.isArray(projectIds) || projectIds.some((id) => typeof id !== "string")) {
    throw new HttpsError("invalid-argument", "Invalid project selection.");
  }

  let uid: string;
  // True once we know an Auth user for this email already existed before
  // this call — either a genuine duplicate (rejected below) or an orphan
  // left behind by a previous invite whose Firestore write failed. Only a
  // freshly-created user gets rolled back if the write below fails.
  let isNewAuthUser = true;
  try {
    const userRecord = await admin.auth().createUser({
      email,
      displayName: [firstName, lastName].filter(Boolean).join(" "),
    });
    uid = userRecord.uid;
  } catch (error) {
    const code = (error as { code?: string }).code;
    if (code !== "auth/email-already-exists") {
      throw new HttpsError("internal", "Could not create the account. Please try again.");
    }
    const existingUser = await admin.auth().getUserByEmail(email);
    const existingDoc = await admin.firestore().collection("employees").doc(existingUser.uid).get();
    if (existingDoc.exists) {
      throw new HttpsError("already-exists", "An account already exists for that email.");
    }
    // The Auth account exists but its employees doc doesn't — a previous
    // invite for this email must have failed partway through. Finish it
    // now instead of leaving the account permanently orphaned.
    uid = existingUser.uid;
    isNewAuthUser = false;
  }

  const batch = admin.firestore().batch();
  batch.set(admin.firestore().collection("employees").doc(uid), {
    firstName,
    lastName: lastName || null,
    email,
    role,
    projectIds,
    fcmTokens: [],
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });
  for (const projectId of projectIds) {
    batch.update(admin.firestore().collection("projects").doc(projectId), {
      memberIds: admin.firestore.FieldValue.arrayUnion(uid),
    });
  }
  try {
    await batch.commit();
  } catch (error) {
    if (isNewAuthUser) {
      // Roll back the just-created Auth user so the invite can be retried
      // cleanly, rather than leaving an orphaned account behind.
      await admin.auth().deleteUser(uid).catch(() => undefined);
    }
    throw new HttpsError("internal", "Could not create the account. Please try again.");
  }

  return { uid, email };
});
