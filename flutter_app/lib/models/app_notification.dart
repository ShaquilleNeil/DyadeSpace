import 'package:cloud_firestore/cloud_firestore.dart';

class NotificationType {
  static const taskAssigned = 'task_assigned';
  static const materialRequestSubmitted = 'material_request_submitted';
  static const materialRequestDecided = 'material_request_decided';
  static const dailyReportSubmitted = 'daily_report_submitted';
  static const staffAssignmentChanged = 'staff_assignment_changed';
}

class AppNotification {
  final String id;
  final String recipientId;
  final String type;
  final String title;
  final String body;
  final String? deepLink;
  final bool read;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.recipientId,
    required this.type,
    required this.title,
    required this.body,
    this.deepLink,
    this.read = false,
    this.createdAt,
  });

  factory AppNotification.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return AppNotification(
      id: doc.id,
      recipientId: data['recipientId'] as String? ?? '',
      type: data['type'] as String? ?? '',
      title: data['title'] as String? ?? '',
      body: data['body'] as String? ?? '',
      deepLink: data['deepLink'] as String?,
      read: data['read'] as bool? ?? false,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
