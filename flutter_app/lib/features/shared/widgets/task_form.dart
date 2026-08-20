import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/employee.dart';
import '../../../models/task.dart';
import '../../../theme/app_spacing.dart';
import 'employee_multi_picker.dart';
import 'form_sheet_scaffold.dart';

class _TaskEntry {
  final title = TextEditingController();
  final description = TextEditingController();
  DateTime? deadline;
  final Set<Employee> pickedEmployees = {};
  bool expanded = true;

  void dispose() {
    title.dispose();
    description.dispose();
  }
}

/// Bottom-sheet form for creating one or more tasks, optionally pre-assigned
/// to [preselectedEmployee] (used from the staff directory's quick-assign
/// button) — otherwise the manager can assign one or more employees from
/// [allEmployees].
///
/// "Add Another Task" collapses the current entry into a summary row and
/// opens a fresh one; Save reports every filled-in entry at once.
class TaskForm extends StatefulWidget {
  const TaskForm({
    super.key,
    required this.projectId,
    required this.allEmployees,
    required this.preselectedEmployee,
    required this.onSave,
  });

  final String? projectId;
  final List<Employee> allEmployees;
  final Employee? preselectedEmployee;
  final void Function(List<(Task task, List<String> employeeIds)> entries) onSave;

  @override
  State<TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends State<TaskForm> {
  final List<_TaskEntry> _entries = [];

  @override
  void initState() {
    super.initState();
    _entries.add(_TaskEntry());
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDeadline(_TaskEntry entry) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: entry.deadline ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => entry.deadline = picked);
    }
  }

  void _addAnotherTask() {
    setState(() {
      _entries.last.expanded = false;
      _entries.add(_TaskEntry());
    });
  }

  void _save() {
    final result = <(Task, List<String>)>[];
    for (final entry in _entries) {
      if (entry.title.text.trim().isEmpty) continue;
      final employeeIds = widget.preselectedEmployee != null
          ? [widget.preselectedEmployee!.id]
          : entry.pickedEmployees.map((e) => e.id).toList();
      if (employeeIds.isEmpty) continue;
      result.add((
        Task(
          id: '',
          title: entry.title.text,
          description: entry.description.text,
          status: TaskStatus.todo,
          deadline: entry.deadline,
          projectId: widget.projectId,
        ),
        employeeIds,
      ));
    }
    if (result.isNotEmpty) {
      widget.onSave(result);
    }
  }

  Widget _buildEntryFields(_TaskEntry entry, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_entries.length > 1) ...[
            Text('Task ${index + 1}', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextField(
            controller: entry.title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: entry.description,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: AppSpacing.md),
          InkWell(
            onTap: () => _pickDeadline(entry),
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Deadline'),
              child: Text(entry.deadline != null ? DateFormat('yyyy-MM-dd').format(entry.deadline!) : ''),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          if (widget.preselectedEmployee != null)
            Text(
              'Assigned to: ${widget.preselectedEmployee!.fullName}',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else ...[
            Text('Assign Employees', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.sm),
            EmployeeMultiPicker(
              allEmployees: widget.allEmployees,
              selectedEmployees: entry.pickedEmployees,
              onAdd: (emp) => setState(() => entry.pickedEmployees.add(emp)),
              onRemove: (emp) => setState(() => entry.pickedEmployees.remove(emp)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCollapsedEntry(_TaskEntry entry, int index) {
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: () => setState(() => entry.expanded = true),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Task ${index + 1}: ${entry.title.text.trim().isEmpty ? 'Untitled' : entry.title.text}',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Icon(Icons.expand_more),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSave = widget.preselectedEmployee != null || _entries.any((e) => e.pickedEmployees.isNotEmpty);

    return FormSheetScaffold(
      title: 'Add Task',
      children: [
        for (var i = 0; i < _entries.length; i++)
          _entries[i].expanded ? _buildEntryFields(_entries[i], i) : _buildCollapsedEntry(_entries[i], i),
        OutlinedButton(
          onPressed: _addAnotherTask,
          child: const Text('+ Add Another Task'),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: !canSave ? null : _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
