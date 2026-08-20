import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';
import 'auth_providers.dart';
import 'firebase_providers.dart';

/// Registers this device's FCM token against the signed-in employee's doc
/// (so Cloud Functions can push to it) and keeps it fresh on rotation.
/// Watched once at the app root — see `main.dart`.
final fcmSyncProvider = Provider<void>((ref) {
  final uid = ref.watch(currentEmployeeProvider.select((async) => async.value?.id));
  if (uid == null) return;

  final notificationService = ref.watch(notificationServiceProvider);
  final firestore = ref.watch(firestoreServiceProvider);

  Future<void>(() async {
    await notificationService.requestPermission();
    final token = await notificationService.getToken();
    if (token != null) await firestore.addFcmToken(uid, token);
  });

  final sub = notificationService.onTokenRefresh.listen((token) {
    firestore.addFcmToken(uid, token);
  });
  ref.onDispose(sub.cancel);
});

final myNotificationsProvider = StreamProvider<List<AppNotification>>((ref) {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  if (uid == null) return Stream.value(const []);
  return ref.watch(firestoreServiceProvider).watchMyNotifications(uid);
});

final unreadNotificationCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(myNotificationsProvider).value ?? const [];
  return notifications.where((n) => !n.read).length;
});

final notificationControllerProvider =
    Provider<NotificationController>((ref) => NotificationController(ref));

class NotificationController {
  NotificationController(this._ref);

  final Ref _ref;

  Future<void> markRead(String notificationId) {
    return _ref.read(firestoreServiceProvider).markNotificationRead(notificationId);
  }

  Future<void> markAllRead(List<String> notificationIds) {
    return _ref.read(firestoreServiceProvider).markAllNotificationsRead(notificationIds);
  }

  Future<void> delete(String notificationId) {
    return _ref.read(firestoreServiceProvider).deleteNotification(notificationId);
  }
}
