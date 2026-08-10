import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/task.dart';
import '../../providers/tasks_providers.dart';
import '../../theme/app_spacing.dart';
import '../../theme/status_colors.dart';

class TaskViewScreen extends ConsumerWidget {
  const TaskViewScreen({super.key, required this.taskId});

  final String taskId;

  Future<void> _updateStatus(BuildContext context, WidgetRef ref, String newStatus) async {
    try {
      await ref.read(taskControllerProvider).updateTaskStatus(taskId, newStatus);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update task: $e')),
      );
    }
  }

  void _navigateBack(BuildContext context, Task? task) {
    if (context.canPop()) {
      context.pop();
    } else if (task?.projectId != null) {
      context.go('/project/${task!.projectId}');
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final taskAsync = ref.watch(taskByIdProvider(taskId));
    final assignedAsync = ref.watch(assignedEmployeesForTaskProvider(taskId));
    final task = taskAsync.value;

    return Scaffold(
      appBar: AppBar(
        title: Text(task?.title ?? 'Task'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _navigateBack(context, task),
        ),
      ),
      body: SafeArea(
        child: taskAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
          data: (task) {
            if (task == null) {
              return const Center(child: Text('Task not found'));
            }
            final assigned = assignedAsync.value ?? const [];
            final palette = taskStatusPalette(context, task.status);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: palette.background,
                      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                    ),
                    child: Text(
                      TaskStatus.label(task.status),
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: palette.foreground, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _InfoTile(
                    icon: Icons.calendar_today,
                    label: 'Deadline',
                    value: task.deadline != null ? DateFormat('yyyy-MM-dd').format(task.deadline!) : '—',
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _InfoTile(
                    icon: Icons.person,
                    label: 'Assigned To',
                    value: assigned.isNotEmpty
                        ? assigned.map((e) => e.fullName).join(', ')
                        : 'No employees assigned',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Description', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md + 2),
                      child: SizedBox(
                        width: double.infinity,
                        child: Text(
                          (task.description?.isNotEmpty ?? false) ? task.description! : 'No description',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  if (task.status == TaskStatus.todo)
                    FilledButton(
                      onPressed: () => _updateStatus(context, ref, TaskStatus.inProgress),
                      style: FilledButton.styleFrom(
                        backgroundColor: employeeAvailabilityColor(EmployeeAvailability.available),
                      ),
                      child: const Text('Accept'),
                    )
                  else if (task.status == TaskStatus.inProgress)
                    FilledButton(
                      onPressed: () => _updateStatus(context, ref, TaskStatus.done),
                      child: const Text('Mark as Complete'),
                    )
                  else
                    Text('Completed', style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 22, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(value, style: Theme.of(context).textTheme.titleMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
