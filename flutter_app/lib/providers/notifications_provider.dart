import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/notification_item.dart';
import 'auth_provider.dart';

/// The signed-in user's notifications, newest first, capped at
/// 50. Server-side `orderBy('createdAt')` + `limit(50)`: the
/// list no longer downloads every notification ever written
/// and sorts in Dart. Needs the composite index
/// (notifications: userId ASC, createdAt DESC) in
/// firestore.indexes.json — deploy indexes before relying on
/// this query. Gated on sign-in so signing out stays silent.
final notificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection('notifications')
      .where('userId', isEqualTo: me.id)
      .orderBy('createdAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) => snap.docs.map(AppNotification.fromFirestore).toList());
});

/// Marks one notification read.
Future<void> markNotificationRead(String id) {
  return FirebaseFirestore.instance
      .collection('notifications')
      .doc(id)
      .update({'read': true});
}

/// Marks every unread notification of [userId] read, in one
/// batch. Equality-only filters, so no composite index is needed.
/// Capped at 500: a batch holds at most 500 writes, so an
/// unbounded read could hand the commit more than it can take;
/// any unread past the cap simply stays unread for next time.
Future<void> markAllNotificationsRead(String userId) async {
  final snap = await FirebaseFirestore.instance
      .collection('notifications')
      .where('userId', isEqualTo: userId)
      .where('read', isEqualTo: false)
      .limit(500)
      .get();
  if (snap.docs.isEmpty) return;
  final batch = FirebaseFirestore.instance.batch();
  for (final doc in snap.docs) {
    batch.update(doc.reference, {'read': true});
  }
  await batch.commit();
}
