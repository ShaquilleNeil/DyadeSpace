import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/employee.dart';
import '../../providers/employees_providers.dart';
import '../../providers/tasks_providers.dart';
import '../shared/widgets/employee_card.dart';
import '../shared/widgets/search_field.dart';
import '../shared/widgets/task_form.dart';
import '../../utils/friendly_error.dart';

class ManagerStaffScreen extends ConsumerStatefulWidget {
  const ManagerStaffScreen({super.key});

  @override
  ConsumerState<ManagerStaffScreen> createState() => _ManagerStaffScreenState();
}

class _ManagerStaffScreenState extends ConsumerState<ManagerStaffScreen> {
  String _query = '';

  void _openTaskForm(BuildContext context, Employee employee, List<Employee> allEmployees) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => TaskForm(
        projectId: null,
        allEmployees: allEmployees,
        preselectedEmployee: employee,
        onSave: (entries) {
          for (final (task, employeeIds) in entries) {
            ref.read(taskControllerProvider).addTaskAndAssign(task, employeeIds);
          }
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final employeesAsync = ref.watch(visibleEmployeesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Staff Directory'), automaticallyImplyLeading: false),
      body: SafeArea(
        child: Column(
          children: [
            SearchField(onChanged: (value) => setState(() => _query = value)),
            Expanded(
              child: employeesAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text(friendlyErrorMessage(e))),
                data: (employees) {
                  final query = _query.toLowerCase();
                  final displayed = query.trim().isEmpty
                      ? employees
                      : employees
                          .where((e) =>
                              e.fullName.toLowerCase().contains(query) ||
                              e.role.toLowerCase().contains(query))
                          .toList();

                  if (displayed.isEmpty) {
                    return const Center(child: Text('No employees found'));
                  }

                  return GridView.builder(
                    padding: const EdgeInsets.all(12),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 16,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 170,
                    ),
                    itemCount: displayed.length,
                    itemBuilder: (context, index) {
                      final emp = displayed[index];
                      final countAsync = ref.watch(activeTaskCountProvider(emp.id));
                      return EmployeeCard(
                        employee: emp,
                        taskCount: countAsync.value ?? 0,
                        onAddTask: () => _openTaskForm(context, emp, employees),
                        onTap: () => context.push('/staff/${emp.id}'),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
