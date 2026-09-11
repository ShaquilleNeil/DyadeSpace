import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/task.dart';
import '../../providers/tasks_providers.dart';
import '../shared/widgets/notification_bell.dart';
import '../shared/widgets/task_item.dart';
import '../../utils/friendly_error.dart';

class EmployeeHomeScreen extends ConsumerStatefulWidget {
  const EmployeeHomeScreen({super.key});

  @override
  ConsumerState<EmployeeHomeScreen> createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends ConsumerState<EmployeeHomeScreen>
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

  @override
  Widget build(BuildContext context) {
    final tasksAsync = ref.watch(myTasksProvider);
    final tasks = tasksAsync.value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Tasks'),
        automaticallyImplyLeading: false,
        actions: const [NotificationBell()],
        bottom: TabBar(
          controller: _tabController,
          tabs: List.generate(_statuses.length, (index) {
            final count = tasks.where((t) => t.status == _statuses[index]).length;
            return Tab(text: '${_tabLabels[index]} ($count)');
          }),
        ),
      ),
      body: SafeArea(
        child: tasksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text(friendlyErrorMessage(e))),
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
