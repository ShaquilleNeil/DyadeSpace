import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/employee.dart';
import '../../models/task.dart';
import '../../providers/employees_providers.dart';
import '../../providers/tasks_providers.dart';
import '../shared/widgets/task_form.dart';
import '../shared/widgets/task_item.dart';

class ManagerTasksScreen extends ConsumerStatefulWidget {
  const ManagerTasksScreen({super.key});

  @override
  ConsumerState<ManagerTasksScreen> createState() => _ManagerTasksScreenState();
}

class _ManagerTasksScreenState extends ConsumerState<ManagerTasksScreen>
    with SingleTickerProviderStateMixin {
  static const _tabLabels = ['To-Do', 'In Progress', 'Done'];
  static const _statuses = [TaskStatus.todo, TaskStatus.inProgress, TaskStatus.done];

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statuses.length, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openTaskForm(List<Employee> allEmployees) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => TaskForm(
        projectId: null,
        allEmployees: allEmployees,
        preselectedEmployee: null,
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
    final tasksAsync = ref.watch(myTasksProvider);
    final employeesAsync = ref.watch(visibleEmployeesProvider);
    final tasks = tasksAsync.value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tasks'),
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          tabs: List.generate(_statuses.length, (index) {
            final count = tasks.where((t) => t.status == _statuses[index]).length;
            return Tab(text: '${_tabLabels[index]} ($count)');
          }),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: employeesAsync.value == null
            ? null
            : () => _openTaskForm(employeesAsync.value!),
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: tasksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
          data: (tasks) {
            return TabBarView(
              controller: _tabController,
              children: _statuses.map((status) {
                final filtered = tasks.where((t) => t.status == status).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('No tasks found'));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(14),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) => TaskItem(task: filtered[index]),
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}
