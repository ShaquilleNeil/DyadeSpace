import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../models/employee.dart';
import '../../models/task.dart';
import '../../providers/auth_providers.dart';
import '../../providers/employees_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/tasks_providers.dart';
import '../../theme/app_spacing.dart';
import '../../theme/status_colors.dart';
import '../../utils/friendly_error.dart';
import '../shared/widgets/form_sheet_scaffold.dart';
import '../shared/widgets/multi_photo_picker.dart';
import '../shared/widgets/task_edit_form.dart';

class TaskViewScreen extends ConsumerWidget {
  const TaskViewScreen({super.key, required this.taskId});

  final String taskId;

  Future<void> _updateStatus(BuildContext context, WidgetRef ref, String newStatus) async {
    try {
      await ref.read(taskControllerProvider).updateTaskStatus(taskId, newStatus);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(e, fallback: 'Could not update task. Please try again.'),
          ),
        ),
      );
    }
  }

  void _openCompletionSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _CompletionSheet(
        onSubmit: (photos, note) async {
          try {
            final photoUrls = photos.isEmpty
                ? const <String>[]
                : await ref
                    .read(storageServiceProvider)
                    .uploadTaskPhotos(taskId: taskId, files: photos);
            await ref
                .read(taskControllerProvider)
                .completeTask(taskId, photoUrls: photoUrls, note: note);
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          } catch (e) {
            if (!sheetContext.mounted) return;
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(
                content: Text(
                  friendlyErrorMessage(e, fallback: 'Could not complete task. Please try again.'),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  void _openEditSheet(
    BuildContext context,
    WidgetRef ref,
    Task task,
    List<Employee> allEmployees,
    List<Employee> assignedEmployees,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => TaskEditForm(
        task: task,
        allEmployees: allEmployees,
        assignedEmployees: assignedEmployees,
        onSave: (title, description, deadline, employeeIds) async {
          try {
            await ref.read(taskControllerProvider).updateTask(
                  taskId,
                  title: title,
                  description: description,
                  deadline: deadline,
                  assigneeIds: employeeIds,
                );
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          } catch (e) {
            if (!sheetContext.mounted) return;
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(
                content: Text(
                  friendlyErrorMessage(e, fallback: 'Could not update task. Please try again.'),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  Future<void> _savePhoto(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await http.get(Uri.parse(url));
      await Gal.putImageBytes(
        response.bodyBytes,
        name: 'dyadespace_${DateTime.now().millisecondsSinceEpoch}',
      );
      messenger.showSnackBar(const SnackBar(content: Text('Photo saved to your gallery')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e, fallback: 'Could not save photo. Please try again.')),
        ),
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
    final currentEmployee = ref.watch(currentEmployeeProvider).value;
    final allEmployees = ref.watch(visibleEmployeesProvider).value ?? const [];
    final task = taskAsync.value;
    final isManager = currentEmployee?.isManager ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(task?.title ?? 'Task'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => _navigateBack(context, task),
        ),
        actions: [
          if (isManager && task != null)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit task',
              onPressed: () => _openEditSheet(
                context,
                ref,
                task,
                allEmployees,
                assignedAsync.value ?? const [],
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: taskAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text(friendlyErrorMessage(e))),
          data: (task) {
            if (task == null) {
              return const Center(child: Text('Task not found'));
            }
            final assigned = assignedAsync.value ?? const [];
            final palette = taskStatusPalette(context, task.status);
            final isAssignee =
                currentEmployee != null && task.assigneeIds.contains(currentEmployee.id);
            final isManager = currentEmployee?.isManager ?? false;
            final isClient = currentEmployee?.isClient ?? false;

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
                  if (!isClient) ...[
                    const SizedBox(height: AppSpacing.md),
                    _InfoTile(
                      icon: Icons.person,
                      label: 'Assigned To',
                      value: assigned.isNotEmpty
                          ? assigned.map((e) => e.fullName).join(', ')
                          : 'No employees assigned',
                    ),
                  ],
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
                  if (task.completionNote?.isNotEmpty ?? false) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text('Completion Note', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md + 2),
                        child: SizedBox(width: double.infinity, child: Text(task.completionNote!)),
                      ),
                    ),
                  ],
                  if (task.completionPhotoUrls.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Completion Photos', style: Theme.of(context).textTheme.titleMedium),
                        if (isManager && task.completionPhotoUrls.length > 1)
                          TextButton.icon(
                            onPressed: () async {
                              for (final url in task.completionPhotoUrls) {
                                await _savePhoto(context, url);
                              }
                            },
                            icon: const Icon(Icons.download, size: 18),
                            label: const Text('Save All'),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: task.completionPhotoUrls.map((url) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                          child: Stack(
                            children: [
                              CachedNetworkImage(
                                imageUrl: url,
                                width: 110,
                                height: 110,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => Container(
                                  width: 110,
                                  height: 110,
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                ),
                                errorWidget: (context, url, error) => Container(
                                  width: 110,
                                  height: 110,
                                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                                  child: const Icon(Icons.broken_image),
                                ),
                              ),
                              if (isManager)
                                Positioned(
                                  right: 2,
                                  bottom: 2,
                                  child: Material(
                                    color: Colors.black54,
                                    shape: const CircleBorder(),
                                    child: IconButton(
                                      icon: const Icon(Icons.download, size: 16, color: Colors.white),
                                      tooltip: 'Save photo',
                                      constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                      padding: EdgeInsets.zero,
                                      onPressed: () => _savePhoto(context, url),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  if (task.status == TaskStatus.done)
                    Text('Completed', style: Theme.of(context).textTheme.titleMedium)
                  else if (isAssignee && task.status == TaskStatus.todo)
                    FilledButton(
                      onPressed: () => _updateStatus(context, ref, TaskStatus.inProgress),
                      style: FilledButton.styleFrom(
                        backgroundColor: employeeAvailabilityColor(EmployeeAvailability.available),
                      ),
                      child: const Text('Accept'),
                    )
                  else if (isAssignee && task.status == TaskStatus.inProgress)
                    FilledButton(
                      onPressed: () => _openCompletionSheet(context, ref),
                      child: const Text('Mark as Complete'),
                    ),
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

/// Bottom-sheet shown when an employee taps "Mark as Complete" — optional
/// proof-of-work photos plus a completion note, both attached to the task.
class _CompletionSheet extends StatefulWidget {
  const _CompletionSheet({required this.onSubmit});

  final Future<void> Function(List<File> photos, String? note) onSubmit;

  @override
  State<_CompletionSheet> createState() => _CompletionSheetState();
}

class _CompletionSheetState extends State<_CompletionSheet> {
  final _note = TextEditingController();
  final List<File> _photos = [];
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormSheetScaffold(
      title: 'Mark as Complete',
      children: [
        Text('Photos (optional)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        MultiPhotoPicker(
          photos: _photos,
          onAdd: (picked) => setState(() => _photos.addAll(picked)),
          onRemoveAt: (index) => setState(() => _photos.removeAt(index)),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _note,
          decoration: const InputDecoration(labelText: 'Completion note (optional)'),
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  final note = _note.text.trim();
                  await widget.onSubmit(_photos, note.isEmpty ? null : note);
                  if (mounted) setState(() => _saving = false);
                },
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Mark as Complete'),
        ),
      ],
    );
  }
}
