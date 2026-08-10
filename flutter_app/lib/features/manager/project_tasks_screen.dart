import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/task.dart';
import '../../providers/projects_providers.dart';
import '../../providers/tasks_providers.dart';
import '../shared/widgets/task_item.dart';

class ProjectTasksScreen extends ConsumerStatefulWidget {
  const ProjectTasksScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectTasksScreen> createState() => _ProjectTasksScreenState();
}

class _ProjectTasksScreenState extends ConsumerState<ProjectTasksScreen>
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
    final projectAsync = ref.watch(projectByIdProvider(widget.projectId));
    final tasksAsync = ref.watch(projectTasksProvider(widget.projectId));
    final tasks = tasksAsync.value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(projectAsync.value?.name ?? 'Loading project…'),
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
                  itemBuilder: (context, index) {
                    final task = filtered[index];
                    return TaskItem(
                      task: task,
                      showRemove: true,
                      onRemove: () => ref.read(taskControllerProvider).deleteTask(task.id),
                    );
                  },
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }
}
