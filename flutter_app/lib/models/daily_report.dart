import 'package:cloud_firestore/cloud_firestore.dart';

class DailyReport {
  final String id;
  final String projectId;
  final String submittedById;
  final String submittedByName;
  final DateTime date;
  final String summary;
  final String? taskNotes;
  final List<String> photoUrls;
  final DateTime? createdAt;

  const DailyReport({
    required this.id,
    required this.projectId,
    required this.submittedById,
    required this.submittedByName,
    required this.date,
    required this.summary,
    this.taskNotes,
    this.photoUrls = const [],
    this.createdAt,
  });

  factory DailyReport.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return DailyReport(
      id: doc.id,
      projectId: data['projectId'] as String? ?? '',
      submittedById: data['submittedById'] as String? ?? '',
      submittedByName: data['submittedByName'] as String? ?? '',
      date: (data['date'] as Timestamp?)?.toDate() ?? DateTime.now(),
      summary: data['summary'] as String? ?? '',
      taskNotes: data['taskNotes'] as String?,
      photoUrls: List<String>.from(data['photoUrls'] as List? ?? const []),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'projectId': projectId,
      'submittedById': submittedById,
      'submittedByName': submittedByName,
      'date': Timestamp.fromDate(date),
      'summary': summary,
      'taskNotes': taskNotes,
      'photoUrls': photoUrls,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }
}
