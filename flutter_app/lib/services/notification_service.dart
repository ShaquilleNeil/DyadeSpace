import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';

/// Push-notification wiring (FCM). Two kinds of topics:
/// - 'managers': the Cloud Functions (notifyBlocked,
///   notifyStopFailed, the day-report push) publish here -
///   admin/manager devices only.
/// - 'user_<uid>': personal topic for crew assignment alerts
///   (notifyTaskAssigned / notifyRunPublished) - every signed-in
///   user subscribes to their own.
/// Sync rules:
/// - sign-in (any role) -> request permission, join own topic,
///   and join 'managers' too when admin/manager.
/// - worker/delivery -> make sure NOT on 'managers'.
/// - sign-out -> leave both topics.
/// Calls are deduplicated by (uid, role), so the sync hook in
/// notification_provider.dart can fire on every profile change
/// without re-prompting or re-subscribing.
class NotificationService {
  static const String managersTopic = 'managers';

  static String personalTopic(String uid) => 'user_$uid';

  final FirebaseMessaging _messaging;

  /// The session state the subscriptions were last synced to.
  /// Null uid = synced to signed-out.
  String? _syncedUid;
  bool? _syncedAsManager;

  /// Consecutive failed sync attempts, for backoff. Reset on
  /// success. A failed sync is retried (up to 3 times, then
  /// again on the next profile change) — the old code marked
  /// the session synced BEFORE attempting, so a failure was
  /// never retried and the device silently stayed off its
  /// topics.
  int _syncFailures = 0;

  NotificationService({FirebaseMessaging? messaging})
      : _messaging = messaging ?? FirebaseMessaging.instance;

  /// Syncs the topic subscriptions with the signed-in session.
  /// [uid] null means signed out (same as [unsubscribe]).
  /// Never throws - notification setup must not break the app.
  /// The synced state is only recorded AFTER a successful
  /// sync, so a failure leaves the session unsynced and the
  /// next profile change (or the scheduled retry below) tries
  /// again.
  Future<void> syncSession({
    required String? uid,
    required bool isManager,
  }) async {
    if (uid == _syncedUid && isManager == _syncedAsManager) return;
    final previousUid = _syncedUid;
    try {
      // A different account signed in on this device: leave the
      // previous account's personal topic first.
      if (previousUid != null && previousUid != uid) {
        await _messaging.unsubscribeFromTopic(personalTopic(previousUid));
      }
      if (uid == null) {
        await _messaging.unsubscribeFromTopic(managersTopic);
      } else {
        final settings = await _messaging.requestPermission();
        final allowed =
            settings.authorizationStatus == AuthorizationStatus.authorized ||
                settings.authorizationStatus == AuthorizationStatus.provisional;
        if (allowed) {
          await _messaging.subscribeToTopic(personalTopic(uid));
        }
        if (isManager) {
          if (allowed) {
            await _messaging.subscribeToTopic(managersTopic);
          }
        } else {
          await _messaging.unsubscribeFromTopic(managersTopic);
        }
      }
      _syncedUid = uid;
      _syncedAsManager = isManager;
      _syncFailures = 0;
    } catch (_) {
      // Permission/topic calls can fail on unsupported platforms
      // or when Play services are missing. Nothing user-facing
      // depends on this succeeding — but it IS retried: backoff
      // 5s, 20s, 45s, then the next profile change re-syncs
      // (the synced state above was never recorded).
      _syncFailures++;
      if (_syncFailures <= 3) {
        final delay = Duration(seconds: 5 * _syncFailures * _syncFailures);
        Future.delayed(delay, () {
          if (uid == _syncedUid && isManager == _syncedAsManager) return;
          unawaited(syncSession(uid: uid, isManager: isManager));
        });
      }
    }
  }

  /// Leaves both topics (sign-out). Never throws.
  Future<void> unsubscribe() async {
    final uid = _syncedUid;
    _syncedUid = null;
    _syncedAsManager = false;
    try {
      await _messaging.unsubscribeFromTopic(managersTopic);
      if (uid != null) {
        await _messaging.unsubscribeFromTopic(personalTopic(uid));
      }
    } catch (_) {
      // Same reasoning as above: teardown must not fail loudly.
    }
  }
}
