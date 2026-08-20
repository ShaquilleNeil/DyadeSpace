import 'package:firebase_messaging/firebase_messaging.dart';

/// FCM permission + token registration. The token itself is stored on the
/// employee doc by whoever owns the [Employee] update (see
/// `fcmInitProvider`) — this service only talks to the messaging SDK.
class NotificationService {
  NotificationService(this._messaging);

  final FirebaseMessaging _messaging;

  Future<void> requestPermission() {
    return _messaging
        .requestPermission(alert: true, badge: true, sound: true)
        .then((_) => _messaging.setForegroundNotificationPresentationOptions(
              alert: true,
              badge: true,
              sound: true,
            ));
  }

  Future<String?> getToken() => _messaging.getToken();

  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
}
