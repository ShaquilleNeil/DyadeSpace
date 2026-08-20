import * as admin from "firebase-admin";

const db = () => admin.firestore();
const messaging = () => admin.messaging();

export interface NotificationInput {
  recipientId: string;
  type: string;
  title: string;
  body: string;
  deepLink?: string;
}

/**
 * Writes an in-app notification doc and best-effort pushes it via FCM to
 * every token on the recipient's employee doc. Invalid/expired tokens are
 * pruned from the employee doc when the push fails on them.
 */
export async function notify(input: NotificationInput): Promise<void> {
  await db().collection("notifications").add({
    recipientId: input.recipientId,
    type: input.type,
    title: input.title,
    body: input.body,
    deepLink: input.deepLink ?? null,
    read: false,
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const employeeSnap = await db().collection("employees").doc(input.recipientId).get();
  const tokens: string[] = employeeSnap.get("fcmTokens") ?? [];
  if (tokens.length === 0) return;

  const response = await messaging().sendEachForMulticast({
    tokens,
    notification: { title: input.title, body: input.body },
    data: input.deepLink ? { deepLink: input.deepLink } : {},
  });

  const staleTokens = response.responses
    .map((r, i) => (!r.success && isUnregistered(r.error) ? tokens[i] : null))
    .filter((t): t is string => t !== null);

  if (staleTokens.length > 0) {
    await employeeSnap.ref.update({
      fcmTokens: admin.firestore.FieldValue.arrayRemove(...staleTokens),
    });
  }
}

function isUnregistered(error?: admin.FirebaseError): boolean {
  return (
    error?.code === "messaging/registration-token-not-registered" ||
    error?.code === "messaging/invalid-registration-token"
  );
}

/** Fan out the same notification to several recipients. */
export async function notifyMany(
  recipientIds: string[],
  rest: Omit<NotificationInput, "recipientId">
): Promise<void> {
  const uniqueIds = [...new Set(recipientIds)];
  await Promise.all(uniqueIds.map((recipientId) => notify({ recipientId, ...rest })));
}

/** Every manager assigned to [projectId], plus every admin. */
export async function projectOverseerIds(projectId: string): Promise<string[]> {
  const [managers, admins] = await Promise.all([
    db()
      .collection("employees")
      .where("role", "==", "manager")
      .where("projectIds", "array-contains", projectId)
      .get(),
    db().collection("employees").where("role", "==", "admin").get(),
  ]);
  return [...managers.docs, ...admins.docs].map((d) => d.id);
}
