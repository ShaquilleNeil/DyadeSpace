import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';
import 'auth_provider.dart';

final notificationServiceProvider =
    Provider<NotificationService>((ref) => NotificationService());

/// Keeps the FCM topic subscriptions in sync with the signed-in
/// profile for the whole session. Watched once from the app
/// root (app.dart), so it re-evaluates on EVERY profile/role
/// change, not just cold start:
/// - profile arrives -> permission + own 'user_<uid>' topic,
///   plus the 'managers' topic for admin/manager.
/// - profile arrives as worker/delivery -> own topic only.
/// - profile becomes null (sign-out) -> leave both topics. This
///   is also the sign-out hook: home_shell's button only calls
///   AuthService.signOut(), and the resulting null emission here
///   is what takes the device off the topics.
/// Loading/error transitions are ignored (the profile stream
/// can flicker during auth changes); only settled values sync.
final notificationSyncProvider = Provider<void>((ref) {
  final service = ref.watch(notificationServiceProvider);
  ref.listen(currentUserProvider, (previous, next) {
    if (next is! AsyncData) return;
    final user = next.value;
    if (user == null) {
      service.unsubscribe();
    } else {
      service.syncSession(
        uid: user.id,
        isManager: user.isAdminOrManager,
      );
    }
  }, fireImmediately: true);
});
