import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/employee.dart';
import '../models/task.dart';
import 'auth_providers.dart';
import 'firebase_providers.dart';

final allTasksProvider = StreamProvider<List<Task>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllTasks();
});

/// Tasks assigned to the current user — mirrors `TaskViewModel.fetchMyTasks`.
final myTasksProvider = StreamProvider<List<Task>>((ref) {
  final uid = ref.watch(authStateChangesProvider).value?.uid;
  if (uid == null) return Stream.value(const <Task>[]);
  return ref.watch(firestoreServiceProvider).watchMyTasks(uid);
});

final taskByIdProvider = StreamProvider.autoDispose.family<Task?, String>((ref, taskId) {
  return ref.watch(firestoreServiceProvider).watchTaskById(taskId);
});

final projectTasksProvider = StreamProvider.family<List<Task>, String>((ref, projectId) {
  return ref.watch(firestoreServiceProvider).watchProjectTasks(projectId);
});

final assignedEmployeesForTaskProvider = FutureProvider.family<List<Employee>, String>((ref, taskId) {
  return ref.watch(firestoreServiceProvider).getEmployeesForTask(taskId);
});

final taskControllerProvider = Provider<TaskController>((ref) => TaskController(ref));

class TaskController {
  TaskController(this._ref);

  final Ref _ref;

  Future<void> addTaskAndAssign(Task task, List<String> employeeIds) {
    return _ref.read(firestoreServiceProvider).addTaskAndAssign(task, employeeIds);
  }

  Future<void> deleteTask(String taskId) {
    return _ref.read(firestoreServiceProvider).deleteTask(taskId);
  }

  Future<void> updateTaskStatus(String taskId, String newStatus) {
    return _ref.read(firestoreServiceProvider).updateTaskStatus(taskId, newStatus);
  }
}
