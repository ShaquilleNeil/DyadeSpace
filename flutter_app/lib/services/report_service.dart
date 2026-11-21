import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/day_report.dart';
import '../models/task_item.dart';
import '../utils/toronto_time.dart';

/// Builds the end-of-day summary from the tasks collection.
/// The scheduled Cloud Function does the same thing at the
/// configured time (6 PM default); this service powers the
/// "Generate today's report" button and the Reports screen list.
class ReportService {
  final FirebaseFirestore _db;
  ReportService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _reports =>
      _db.collection('dayReports');

  Stream<List<DayReport>> watchReports() {
    return _reports
        .orderBy('date', descending: true)
        .limit(60)
        .snapshots()
        .map((snap) => snap.docs.map(DayReport.fromFirestore).toList());
  }

  /// End-of-day send channel, stored on the shared settings doc
  /// `settings/eodReport` as field `channel`: 'push', 'email' or
  /// 'both'. Missing doc/field means 'both' (the default: push
  /// plus email). The scheduled Cloud Function reads the same doc.
  static const String eodChannelDefault = 'both';

  Stream<String> watchEodChannel() {
    return _db
        .collection('settings')
        .doc('eodReport')
        .snapshots()
        .map((snap) {
      final channel = snap.data()?['channel'] as String?;
      if (channel == 'push' || channel == 'email' || channel == 'both') {
        return channel!;
      }
      return eodChannelDefault;
    });
  }

  Future<void> saveEodChannel(String channel) async {
    await _db.collection('settings').doc('eodReport').set(
      {'channel': channel},
      SetOptions(merge: true),
    );
  }

  /// End-of-day send time, stored on the same shared settings
  /// doc as field `time` ("HH:mm", Toronto time). Missing doc /
  /// field means '18:00' (6 PM, the previous behaviour). The
  /// scheduled Cloud Function reads the same doc and sends at
  /// the first run at or after this time each day.
  static const String eodTimeDefault = '18:00';

  Stream<String> watchEodTime() {
    return _db
        .collection('settings')
        .doc('eodReport')
        .snapshots()
        .map((snap) {
      final time = snap.data()?['time'] as String?;
      if (time != null && RegExp(r'^\d{2}:\d{2}$').hasMatch(time)) {
        return time;
      }
      return eodTimeDefault;
    });
  }

  Future<void> saveEodTime(String time) async {
    await _db.collection('settings').doc('eodReport').set(
      {'time': time},
      SetOptions(merge: true),
    );
  }

  /// Asks the Cloud Function to build and send today's report
  /// right now: the function watches this collection (see
  /// sendDayReportNow in functions/index.js), checks the caller
  /// is an admin, then sends per the stored channel. The doc is
  /// left in place as an audit trail (status: pending/sent).
  ///
  /// This waits for the function to answer: it returns only
  /// once the request doc lands on `sent`, and throws
  /// [ReportSendException] when the function marks it `denied`
  /// or `failed` (or does not answer within 90 seconds, in
  /// which case the function may still send later — the caller
  /// reports the send as failed rather than as a success).
  Future<void> requestSendNow(String requestedBy) async {
    final ref = await _db.collection('eodSendRequests').add({
      'requestedBy': requestedBy,
      'requestedAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });
    final status = await _waitForSendNowStatus(ref);
    if (status != 'sent') {
      throw ReportSendException(status);
    }
  }

  /// Watches one send-now request doc until its status leaves
  /// `pending` (sent / denied / failed), the doc disappears,
  /// or the wait times out. Returns the terminal status, or
  /// `'timeout'`.
  Future<String> _waitForSendNowStatus(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final snap = await ref
          .snapshots()
          .firstWhere((doc) {
            if (!doc.exists) return true;
            final status = doc.data()?['status'] as String?;
            return status != null && status != 'pending';
          })
          .timeout(const Duration(seconds: 90));
      if (!snap.exists) return 'failed';
      return snap.data()?['status'] as String? ?? 'failed';
    } on TimeoutException {
      return 'timeout';
    }
  }

  /// Aggregates [day] and saves a DayReport doc (id = yyyy-MM-dd,
  /// so re-generating the same day overwrites instead of duplicating).
  /// [day] is read in America/Toronto, not device-local time:
  /// the Cloud Function builds the same report id from Toronto
  /// time, so a device outside Toronto must agree with it or
  /// the two reports land on different days (and can overwrite
  /// each other). Done/overdue comparisons are Toronto calendar
  /// days too, for the same reason.
  Future<DayReport> buildAndSaveReport(DateTime day) async {
    final snap = await _db.collection('tasks').get();
    final all = snap.docs.map(TaskItem.fromFirestore).toList();

    final toronto = torontoDateParts(day);
    bool sameDay(DateTime? d) => d != null &&
        isSameTorontoDay(d, toronto.year, toronto.month, toronto.day);

    bool isOverdueToronto(TaskItem t) {
      if (t.status == TaskStatus.done || t.dueDate == null) return false;
      final due = torontoDateParts(t.dueDate!);
      if (due.year != toronto.year) return due.year < toronto.year;
      if (due.month != toronto.month) return due.month < toronto.month;
      return due.day < toronto.day;
    }

    final done = all
        .where((t) => t.status == TaskStatus.done && sameDay(t.finishedAt))
        .toList();
    final inProgress = all
        .where((t) =>
            t.status == TaskStatus.inProgress ||
            t.status == TaskStatus.toConfirm)
        .toList();
    final blocked =
        all.where((t) => t.status == TaskStatus.blocked).toList();
    final overdue = all.where(isOverdueToronto).toList();

    final report = DayReport(
      id: torontoDateId(day),
      date: DateTime(toronto.year, toronto.month, toronto.day),
      doneCount: done.length,
      inProgressCount: inProgress.length,
      blockedCount: blocked.length,
      overdueCount: overdue.length,
      doneTaskIds: done.map((t) => t.id).toList(),
      inProgressTaskIds: inProgress.map((t) => t.id).toList(),
      overdueTaskIds: overdue.map((t) => t.id).toList(),
      blockedReasons: {
        for (final t in blocked)
          t.id: '${t.blockedReason?.name ?? 'other'}: ${t.blockedNote}',
      },
    );
    await _reports.doc(report.id).set(report.toMap());
    return report;
  }
}

/// Thrown when a "Send now" request does not land as sent:
/// the function denied it (non-admin), failed, or did not
/// answer in time. Callers show the failure instead of a
/// success — the old fire-and-forget create reported success
/// before the function had even run.
class ReportSendException implements Exception {
  final String status;
  const ReportSendException(this.status);
  @override
  String toString() => 'Report send $status';
}
