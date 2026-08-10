import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/employee.dart';
import 'firebase_providers.dart';

final allEmployeesProvider = StreamProvider<List<Employee>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllEmployees();
});

final activeTaskCountProvider = FutureProvider.family<int, String>((ref, employeeId) {
  return ref.watch(firestoreServiceProvider).getActiveTaskCountForEmployee(employeeId);
});
