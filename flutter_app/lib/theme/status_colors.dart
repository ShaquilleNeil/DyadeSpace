import 'package:flutter/material.dart';

import '../models/material_request.dart';
import '../models/task.dart';

/// Single source of truth for "status" colors across the app. Previously each
/// screen (employee_card, task_item, task_view_screen, project_item) rolled
/// its own hardcoded colors, and task in-progress/done both resolved to the
/// same blue by accident.
class StatusPalette {
  const StatusPalette({required this.background, required this.foreground});

  final Color background;
  final Color foreground;
}

StatusPalette taskStatusPalette(BuildContext context, String status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case TaskStatus.todo:
      return isDark
          ? const StatusPalette(background: Color(0xFF3A3D42), foreground: Color(0xFFD0D3D9))
          : const StatusPalette(background: Color(0xFFE6E8EB), foreground: Color(0xFF4A4E57));
    case TaskStatus.inProgress:
      return isDark
          ? const StatusPalette(background: Color(0xFF4A3B12), foreground: Color(0xFFFFD873))
          : const StatusPalette(background: Color(0xFFFFF3CD), foreground: Color(0xFF8A6100));
    case TaskStatus.done:
      return isDark
          ? const StatusPalette(background: Color(0xFF123A22), foreground: Color(0xFF6EE7A8))
          : const StatusPalette(background: Color(0xFFD9F7E3), foreground: Color(0xFF15803D));
    default:
      return isDark
          ? const StatusPalette(background: Color(0xFF3A3D42), foreground: Color(0xFFD0D3D9))
          : const StatusPalette(background: Color(0xFFE6E8EB), foreground: Color(0xFF4A4E57));
  }
}

/// Same background/foreground scheme as [taskStatusPalette], reused for
/// material request status chips (pending/approved/rejected/fulfilled).
StatusPalette materialRequestStatusPalette(BuildContext context, String status) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (status) {
    case MaterialRequestStatus.pending:
      return isDark
          ? const StatusPalette(background: Color(0xFF4A3B12), foreground: Color(0xFFFFD873))
          : const StatusPalette(background: Color(0xFFFFF3CD), foreground: Color(0xFF8A6100));
    case MaterialRequestStatus.approved:
      return isDark
          ? const StatusPalette(background: Color(0xFF123A22), foreground: Color(0xFF6EE7A8))
          : const StatusPalette(background: Color(0xFFD9F7E3), foreground: Color(0xFF15803D));
    case MaterialRequestStatus.rejected:
      return isDark
          ? const StatusPalette(background: Color(0xFF4A1616), foreground: Color(0xFFFF9B9B))
          : const StatusPalette(background: Color(0xFFFBDADA), foreground: Color(0xFFB42318));
    case MaterialRequestStatus.fulfilled:
      return isDark
          ? const StatusPalette(background: Color(0xFF12313A), foreground: Color(0xFF7DD3E8))
          : const StatusPalette(background: Color(0xFFD8F0F7), foreground: Color(0xFF0E6B85));
    default:
      return isDark
          ? const StatusPalette(background: Color(0xFF3A3D42), foreground: Color(0xFFD0D3D9))
          : const StatusPalette(background: Color(0xFFE6E8EB), foreground: Color(0xFF4A4E57));
  }
}

/// Traffic-light coding for employee availability, driven by active task load
/// since there's no explicit availability field on [Employee] yet.
enum EmployeeAvailability { available, busy, unavailable }

EmployeeAvailability employeeAvailabilityFromTaskCount(int taskCount) {
  if (taskCount == 0) return EmployeeAvailability.available;
  if (taskCount <= 2) return EmployeeAvailability.busy;
  return EmployeeAvailability.unavailable;
}

Color employeeAvailabilityColor(EmployeeAvailability availability) {
  switch (availability) {
    case EmployeeAvailability.available:
      return const Color(0xFF22C55E);
    case EmployeeAvailability.busy:
      return const Color(0xFFF59E0B);
    case EmployeeAvailability.unavailable:
      return const Color(0xFFEF4444);
  }
}
