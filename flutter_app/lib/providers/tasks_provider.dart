import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/task_item.dart';
import '../models/task_update.dart';
import '../services/photo_service.dart';
import '../services/report_service.dart';
import '../services/task_service.dart';
import 'auth_provider.dart';

final taskServiceProvider = Provider<TaskService>((ref) => TaskService());
final reportServiceProvider =
    Provider<ReportService>((ref) => ReportService());
final photoServiceProvider = Provider<PhotoService>((ref) => PhotoService());

/// Every task (manager views). Gated on sign-in: when signed out
/// it yields an empty list instead of running a Firestore query
/// that would fail with permission-denied during sign-out.
final allTasksProvider = StreamProvider<List<TaskItem>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(taskServiceProvider).watchAllTasks();
});

/// Tasks assigned to the signed-in user (worker My Day / history).
/// Derived from the full list in Dart on purpose: old task docs
/// carry only the single `assigneeId` string, which an
/// `arrayContains` query on `assigneeIds` would miss — filtering
/// here keeps them visible until they are next re-saved.
final myTasksProvider = StreamProvider<List<TaskItem>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref
      .watch(taskServiceProvider)
      .watchAllTasks()
      .map((all) => TaskService.tasksForAssignee(all, user.id));
});

/// Overdue tasks, derived from allTasksProvider in Dart.
final overdueTasksProvider = Provider<List<TaskItem>>((ref) {
  final all = ref.watch(allTasksProvider).valueOrNull ?? [];
  return TaskService.overdueOnly(all);
});

/// A single task by id (dependency checks). Family provider.
/// Also gated on sign-in, for the same sign-out reason.
final taskByIdProvider = StreamProvider.family<TaskItem?, String>((ref, id) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value(null);
  return ref.watch(taskServiceProvider).watchTask(id);
});

/// The Updates thread of one task (detail screen), oldest
/// first. Gated on sign-in like the other task providers.
final taskUpdatesProvider =
    StreamProvider.family<List<TaskUpdate>, String>((ref, taskId) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(taskServiceProvider).watchUpdates(taskId);
});
