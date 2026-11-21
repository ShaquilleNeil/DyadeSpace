import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _date(dynamic v) => v is Timestamp ? v.toDate() : DateTime.now();

/// One in-app notification, written by Cloud Functions (Admin SDK)
/// into `notifications/{id}`. The client only reads it and flips
/// `read` - the Firestore rules allow owner read/update/delete
/// and no client create.
class AppNotification {
  final String id;
  final String userId;
  final String title;
  final String body;

  /// Notification kind, e.g. `stopCompleted`, `taskUnlocked`,
  /// `taskAssigned`, `blocked`, `runPublished`, `dayReport`,
  /// `chatMessage`, `clockIn`, `clockOut`.
  final String type;
  final String? taskId;
  final String? runId;
  final String? stopId;

  /// Chat conversations: tapping the notification opens this
  /// conversation (type `chatMessage` only).
  final String? conversationId;

  /// Day reports: tapping opens the Reports screen (type
  /// `dayReport`). The id is the Toronto yyyy-MM-dd doc id.
  final String? reportId;

  /// Material requests: tapping opens the requests screen.
  final String? materialRequestId;

  /// Clock-in/out events (types `clockIn` / `clockOut`): the
  /// time entry to open on the map, plus the worker, site and
  /// GPS coordinates of the event, carried on the doc so the
  /// map can render even before the entry loads.
  final String? timeEntryId;
  final String? userName;
  final String? siteId;
  final String? siteName;
  final double? lat;
  final double? lng;

  /// Falls back to now when the server timestamp is still
  /// pending on a freshly written doc.
  final DateTime createdAt;
  final bool read;

  const AppNotification({
    required this.id,
    required this.userId,
    required this.title,
    required this.body,
    required this.type,
    this.taskId,
    this.runId,
    this.stopId,
    this.conversationId,
    this.reportId,
    this.materialRequestId,
    this.timeEntryId,
    this.userName,
    this.siteId,
    this.siteName,
    this.lat,
    this.lng,
    required this.createdAt,
    this.read = false,
  });

  factory AppNotification.fromFirestore(DocumentSnapshot doc) {
    return AppNotification.fromMap(
        doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory AppNotification.fromMap(String id, Map<String, dynamic> map) {
    return AppNotification(
      id: id,
      userId: map['userId'] as String? ?? '',
      title: map['title'] as String? ?? '',
      body: map['body'] as String? ?? '',
      type: map['type'] as String? ?? '',
      taskId: map['taskId'] as String?,
      runId: map['runId'] as String?,
      stopId: map['stopId'] as String?,
      conversationId: map['conversationId'] as String?,
      reportId: map['reportId'] as String?,
      materialRequestId: map['materialRequestId'] as String?,
      timeEntryId: map['timeEntryId'] as String?,
      userName: map['userName'] as String?,
      siteId: map['siteId'] as String?,
      siteName: map['siteName'] as String?,
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      createdAt: _date(map['createdAt']),
      read: map['read'] as bool? ?? false,
    );
  }
}
