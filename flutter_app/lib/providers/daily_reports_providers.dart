import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/daily_report.dart';
import 'auth_providers.dart';
import 'firebase_providers.dart';

/// Role-aware daily report feed: admin sees every report, a manager sees
/// reports from the project(s) they're on, a worker sees only their own.
final visibleDailyReportsProvider = StreamProvider<List<DailyReport>>((ref) {
  final me = ref.watch(currentEmployeeProvider).value;
  if (me == null) return Stream.value(const []);
  final firestore = ref.watch(firestoreServiceProvider);
  if (me.isAdmin) return firestore.watchAllDailyReports();
  if (me.isManager) return firestore.watchDailyReportsForProjects(me.projectIds);
  return firestore.watchMyDailyReports(me.id);
});

/// Reports for a single project — used by the client-only "Reports" section
/// on the shared project detail screen (clients don't have a global Reports
/// tab, unlike admin/manager/employee).
final dailyReportsForProjectProvider =
    StreamProvider.autoDispose.family<List<DailyReport>, String>((ref, projectId) {
  return ref.watch(firestoreServiceProvider).watchDailyReportsForProject(projectId);
});

final dailyReportByIdProvider =
    StreamProvider.autoDispose.family<DailyReport?, String>((ref, reportId) {
  return ref.watch(firestoreServiceProvider).watchDailyReportById(reportId);
});

final dailyReportControllerProvider =
    Provider<DailyReportController>((ref) => DailyReportController(ref));

class DailyReportController {
  DailyReportController(this._ref);

  final Ref _ref;

  Future<void> submit(DailyReport report, {required List<File> photos}) async {
    final firestore = _ref.read(firestoreServiceProvider);
    final reportId = await firestore.createDailyReport(report);
    if (photos.isNotEmpty) {
      final urls = await _ref
          .read(storageServiceProvider)
          .uploadDailyReportPhotos(reportId: reportId, files: photos);
      await firestore.setDailyReportPhotos(reportId, urls);
    }
  }

  Future<void> delete(String reportId) {
    return _ref.read(firestoreServiceProvider).deleteDailyReport(reportId);
  }
}
