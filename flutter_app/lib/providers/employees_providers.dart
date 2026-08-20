import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/employee.dart';
import 'auth_providers.dart';
import 'firebase_providers.dart';

final allEmployeesProvider = StreamProvider<List<Employee>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllEmployees();
});

/// Role-aware staff list: admin sees everyone, a manager sees only employees
/// who share one of their projects, a worker sees just themself.
final visibleEmployeesProvider = StreamProvider<List<Employee>>((ref) {
  final me = ref.watch(currentEmployeeProvider).value;
  if (me == null) return Stream.value(const []);
  if (me.isAdmin) return ref.watch(firestoreServiceProvider).watchAllEmployees();
  if (me.isManager) {
    return ref.watch(firestoreServiceProvider).watchEmployeesForProjects(me.projectIds);
  }
  return Stream.value([me]);
});

final activeTaskCountProvider = FutureProvider.family<int, String>((ref, employeeId) {
  return ref.watch(firestoreServiceProvider).getActiveTaskCountForEmployee(employeeId);
});

final employeeByIdProvider = StreamProvider.autoDispose.family<Employee?, String>((ref, employeeId) {
  return ref.watch(firestoreServiceProvider).watchEmployee(employeeId);
});

/// Admin-only staff management — reassigning role and project membership
/// from the staff directory's edit sheet.
final employeeAdminControllerProvider =
    Provider<EmployeeAdminController>((ref) => EmployeeAdminController(ref));

class EmployeeAdminController {
  EmployeeAdminController(this._ref);

  final Ref _ref;

  Future<void> updateRole(String employeeId, String role) {
    return _ref.read(firestoreServiceProvider).updateEmployeeRole(employeeId, role);
  }

  Future<void> setProjects(
    String employeeId, {
    required List<String> currentProjectIds,
    required List<String> newProjectIds,
  }) {
    return _ref.read(firestoreServiceProvider).setEmployeeProjects(
          employeeId,
          currentProjectIds: currentProjectIds,
          newProjectIds: newProjectIds,
        );
  }
}
