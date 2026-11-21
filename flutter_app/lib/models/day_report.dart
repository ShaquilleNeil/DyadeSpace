import 'package:cloud_firestore/cloud_firestore.dart';

/// The end-of-day summary Sam receives. Built either by the
/// scheduled Cloud Function (6 PM) or manually from the Reports screen.
class DayReport {
  final String id;
  final DateTime date;
  final DateTime? generatedAt;
  final int doneCount;
  final int inProgressCount;
  final int blockedCount;
  final int overdueCount;
  final List<String> doneTaskIds;
  final List<String> inProgressTaskIds;
  final List<String> overdueTaskIds;

  /// taskId -> "reason: note" for tasks blocked that day.
  final Map<String, String> blockedReasons;

  const DayReport({
    required this.id,
    required this.date,
    this.generatedAt,
    this.doneCount = 0,
    this.inProgressCount = 0,
    this.blockedCount = 0,
    this.overdueCount = 0,
    this.doneTaskIds = const [],
    this.inProgressTaskIds = const [],
    this.overdueTaskIds = const [],
    this.blockedReasons = const {},
  });

  factory DayReport.fromFirestore(DocumentSnapshot doc) {
    return DayReport.fromMap(doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory DayReport.fromMap(String id, Map<String, dynamic> map) {
    return DayReport(
      id: id,
      // The date never silently falls back to "now": the doc id
      // IS the yyyy-MM-dd date (written by both the function
      // and ReportService), so a doc without a `date` field
      // still parses to its own day; only a malformed id falls
      // through to the generation time, then to now.
      date: _reportDate(id, map),
      generatedAt: map['generatedAt'] is Timestamp
          ? (map['generatedAt'] as Timestamp).toDate()
          : null,
      doneCount: (map['doneCount'] as num?)?.toInt() ?? 0,
      inProgressCount: (map['inProgressCount'] as num?)?.toInt() ?? 0,
      blockedCount: (map['blockedCount'] as num?)?.toInt() ?? 0,
      overdueCount: (map['overdueCount'] as num?)?.toInt() ?? 0,
      doneTaskIds: List<String>.from(map['doneTaskIds'] as List? ?? []),
      inProgressTaskIds:
          List<String>.from(map['inProgressTaskIds'] as List? ?? []),
      overdueTaskIds: List<String>.from(map['overdueTaskIds'] as List? ?? []),
      blockedReasons:
          Map<String, String>.from(map['blockedReasons'] as Map? ?? {}),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'generatedAt': FieldValue.serverTimestamp(),
      'doneCount': doneCount,
      'inProgressCount': inProgressCount,
      'blockedCount': blockedCount,
      'overdueCount': overdueCount,
      'doneTaskIds': doneTaskIds,
      'inProgressTaskIds': inProgressTaskIds,
      'overdueTaskIds': overdueTaskIds,
      'blockedReasons': blockedReasons,
    };
  }
}

/// Derives a report's date: the stored `date` field first,
/// then the doc id (yyyy-MM-dd), then the generation time.
/// `DateTime.now()` is only the last resort for a doc with
/// none of those.
DateTime _reportDate(String id, Map<String, dynamic> map) {
  if (map['date'] is Timestamp) {
    return (map['date'] as Timestamp).toDate();
  }
  final parts = id.split('-');
  if (parts.length == 3) {
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final d = int.tryParse(parts[2]);
    if (y != null && m != null && d != null) {
      final parsed = DateTime.tryParse(id);
      if (parsed != null) return DateTime(parsed.year, parsed.month, parsed.day);
    }
  }
  if (map['generatedAt'] is Timestamp) {
    final g = (map['generatedAt'] as Timestamp).toDate();
    return DateTime(g.year, g.month, g.day);
  }
  return DateTime.now();
}
