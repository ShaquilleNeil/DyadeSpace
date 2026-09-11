import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/task.dart';
import '../../providers/employees_providers.dart';
import '../../providers/tasks_providers.dart';
import '../../theme/app_spacing.dart';
import '../shared/widgets/task_item.dart';
import '../../utils/friendly_error.dart';

/// Manager-facing staff detail — tapping an employee card in the staff
/// directory lands here: name, phone, and their tasks split by status.
class StaffProfileScreen extends ConsumerStatefulWidget {
  const StaffProfileScreen({super.key, required this.employeeId});

  final String employeeId;

  @override
  ConsumerState<StaffProfileScreen> createState() => _StaffProfileScreenState();
}

class _StaffProfileScreenState extends ConsumerState<StaffProfileScreen>
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
    final employeeAsync = ref.watch(employeeByIdProvider(widget.employeeId));
    final tasksAsync = ref.watch(employeeTasksProvider(widget.employeeId));
    final employee = employeeAsync.value;
    final tasks = tasksAsync.value ?? const [];

    return Scaffold(
      appBar: AppBar(
        title: Text(employee?.fullName ?? 'Staff'),
        bottom: TabBar(
          controller: _tabController,
          tabs: List.generate(_statuses.length, (index) {
            final count = tasks.where((t) => t.status == _statuses[index]).length;
            return Tab(text: '${_tabLabels[index]} ($count)');
          }),
        ),
      ),
      body: SafeArea(
        child: employeeAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text(friendlyErrorMessage(e))),
          data: (employee) {
            if (employee == null) {
              return const Center(child: Text('Employee not found'));
            }
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundImage: (employee.avatarUrl?.isNotEmpty ?? false)
                            ? CachedNetworkImageProvider(employee.avatarUrl!)
                            : null,
                        child: (employee.avatarUrl?.isNotEmpty ?? false)
                            ? null
                            : const Icon(Icons.person, size: 32),
                      ),
                      const SizedBox(width: AppSpacing.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(employee.fullName, style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              employee.role,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ),
                            if (employee.phone?.isNotEmpty ?? false) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Row(
                                children: [
                                  Icon(Icons.phone, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(employee.phone!, style: Theme.of(context).textTheme.bodyMedium),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
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
              ],
            );
          },
        ),
      ),
    );
  }
}
