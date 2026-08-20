import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/employee.dart';
import '../../models/task.dart';
import '../../providers/auth_providers.dart';
import '../../providers/employees_providers.dart';
import '../../providers/projects_providers.dart';
import '../../providers/tasks_providers.dart';
import '../../theme/app_spacing.dart';
import '../shared/widgets/employee_item.dart';
import '../shared/widgets/form_sheet_scaffold.dart';
import '../shared/widgets/task_form.dart';
import '../shared/widgets/task_item.dart';

/// Reserved bottom clearance so the last task in the list isn't hidden behind
/// the fully-expanded 3-FAB speed dial (2 mini FABs + main FAB + gaps/margin).
const double _fabClearance = 220;

class ProjectViewScreen extends ConsumerStatefulWidget {
  const ProjectViewScreen({super.key, required this.projectId});

  final String projectId;

  @override
  ConsumerState<ProjectViewScreen> createState() => _ProjectViewScreenState();
}

class _ProjectViewScreenState extends ConsumerState<ProjectViewScreen>
    with SingleTickerProviderStateMixin {
  bool _employeesExpanded = false;
  bool _tasksExpanded = false;
  bool _fabExpanded = false;
  static const _tabLabels = ['To-Do', 'In Progress', 'Done'];
  static const _statuses = [TaskStatus.todo, TaskStatus.inProgress, TaskStatus.done];

  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _statuses.length, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openAddEmployeeSheet(List<Employee> allEmployees) {
    Employee? selected;
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return FormSheetScaffold(
              title: 'Add Employee to Project',
              children: [
                DropdownButtonFormField<Employee>(
                  initialValue: selected,
                  hint: const Text('Select Employee'),
                  items: allEmployees
                      .map((emp) => DropdownMenuItem(value: emp, child: Text(emp.fullName)))
                      .toList(),
                  onChanged: (emp) => setSheetState(() => selected = emp),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton(
                  onPressed: selected == null
                      ? null
                      : () {
                          ref
                              .read(projectControllerProvider)
                              .addEmployeeToProject(widget.projectId, selected!.id);
                          Navigator.of(sheetContext).pop();
                        },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openAddTaskSheet(List<Employee> allEmployees) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => TaskForm(
        projectId: widget.projectId,
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
    final projectAsync = ref.watch(projectByIdProvider(widget.projectId));
    final employeesAsync = ref.watch(projectEmployeesProvider(widget.projectId));
    final tasksAsync = ref.watch(projectTasksProvider(widget.projectId));
    final allEmployeesAsync = ref.watch(visibleEmployeesProvider);
    final isAdmin = ref.watch(currentEmployeeProvider).value?.isAdmin ?? false;

    return Scaffold(
      body: projectAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error: $e')),
        data: (project) {
          if (project == null) {
            return const Center(child: Text('Loading project…'));
          }
          final employees = employeesAsync.value ?? const [];
          final tasks = tasksAsync.value ?? const [];
          final filteredTasks = tasks.where((t) => t.status == _statuses[_tabController.index]).toList();

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 260,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (project.photoUrl?.isNotEmpty ?? false)
                        CachedNetworkImage(
                          imageUrl: project.photoUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            child: const Center(child: CircularProgressIndicator()),
                          ),
                          errorWidget: (context, url, error) =>
                              Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                        )
                      else
                        Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.transparent, Colors.black.withValues(alpha: 0.75)],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.bottomLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          child: Text(
                            project.name.isEmpty ? 'Unnamed Project' : project.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(color: Colors.white),
                          ),
                        ),
                      ),
                      Positioned(
                        top: MediaQuery.of(context).padding.top + AppSpacing.sm,
                        left: AppSpacing.sm,
                        child: Material(
                          color: Colors.black.withValues(alpha: 0.35),
                          shape: const CircleBorder(),
                          child: IconButton(
                            icon: const Icon(Icons.arrow_back, color: Colors.white),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Location', style: Theme.of(context).textTheme.labelMedium),
                      Text(
                        project.address ?? '',
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                      const Divider(height: AppSpacing.xxl),
                      InkWell(
                        onTap: () => setState(() => _employeesExpanded = !_employeesExpanded),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                          child: Row(
                            children: [
                              Text('Employees (${employees.length})',
                                  style: Theme.of(context).textTheme.titleMedium),
                              const Spacer(),
                              TextButton(
                                onPressed: () => context.push('/project/${widget.projectId}/employees'),
                                child: const Text('View All'),
                              ),
                              Icon(_employeesExpanded ? Icons.expand_less : Icons.expand_circle_down_outlined),
                            ],
                          ),
                        ),
                      ),
                      if (_employeesExpanded)
                        SizedBox(
                          height: 110,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: employees.map((emp) => EmployeeItem(employee: emp)).toList(),
                          ),
                        ),
                      const SizedBox(height: AppSpacing.xs),
                      InkWell(
                        onTap: () => setState(() => _tasksExpanded = !_tasksExpanded),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                          child: Row(
                            children: [
                              Text('Tasks (${tasks.length})', style: Theme.of(context).textTheme.titleMedium),
                              const Spacer(),
                              TextButton(
                                onPressed: () => context.push('/project/${widget.projectId}/tasks'),
                                child: const Text('View All'),
                              ),
                              Icon(_tasksExpanded ? Icons.expand_less : Icons.expand_circle_down_outlined),
                            ],
                          ),
                        ),
                      ),
                      if (_tasksExpanded) ...[
                        TabBar(
                          controller: _tabController,
                          tabAlignment: TabAlignment.fill,
                          tabs: List.generate(_statuses.length, (index) {
                            final count = tasks.where((t) => t.status == _statuses[index]).length;
                            return Tab(text: '${_tabLabels[index]} ($count)');
                          }),
                        ),
                        const SizedBox(height: AppSpacing.md),
                        if (filteredTasks.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                            child: Center(child: Text('No tasks found')),
                          )
                        else
                          ...filteredTasks.map((t) => TaskItem(task: t)),
                      ],
                      const SizedBox(height: _fabClearance),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: projectAsync.value == null
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (_fabExpanded) ...[
                  if (isAdmin) ...[
                    FloatingActionButton(
                      heroTag: 'addEmployee',
                      onPressed: () => _openAddEmployeeSheet(allEmployeesAsync.value ?? const []),
                      child: const Icon(Icons.person_add),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  FloatingActionButton(
                    heroTag: 'addTask',
                    onPressed: () => _openAddTaskSheet(allEmployeesAsync.value ?? const []),
                    child: const Icon(Icons.playlist_add),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                FloatingActionButton(
                  heroTag: 'mainFab',
                  onPressed: () => setState(() => _fabExpanded = !_fabExpanded),
                  child: Icon(_fabExpanded ? Icons.close : Icons.add),
                ),
              ],
            ),
    );
  }
}
