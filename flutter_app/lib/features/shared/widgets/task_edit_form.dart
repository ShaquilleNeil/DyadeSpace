import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/employee.dart';
import '../../../models/task.dart';
import '../../../theme/app_spacing.dart';
import 'employee_multi_picker.dart';
import 'form_sheet_scaffold.dart';

/// Manager-only edit sheet for an existing task — title/description/deadline
/// plus reassigning employees. Pre-filled from [task] and [assignedEmployees].
class TaskEditForm extends StatefulWidget {
  const TaskEditForm({
    super.key,
    required this.task,
    required this.allEmployees,
    required this.assignedEmployees,
    required this.onSave,
  });

  final Task task;
  final List<Employee> allEmployees;
  final List<Employee> assignedEmployees;
  final void Function(
    String title,
    String? description,
    DateTime? deadline,
    List<String> employeeIds,
  ) onSave;

  @override
  State<TaskEditForm> createState() => _TaskEditFormState();
}

class _TaskEditFormState extends State<TaskEditForm> {
  late final _title = TextEditingController(text: widget.task.title);
  late final _description = TextEditingController(text: widget.task.description ?? '');
  late DateTime? _deadline = widget.task.deadline;
  late final Set<Employee> _pickedEmployees = widget.assignedEmployees.toSet();
  bool _saving = false;

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline ?? now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 5),
    );
    if (picked != null) {
      setState(() => _deadline = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _title.text.trim().isNotEmpty && _pickedEmployees.isNotEmpty && !_saving;

    return FormSheetScaffold(
      title: 'Edit Task',
      children: [
        TextField(
          controller: _title,
          decoration: const InputDecoration(labelText: 'Title'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _description,
          decoration: const InputDecoration(labelText: 'Description'),
        ),
        const SizedBox(height: AppSpacing.md),
        InkWell(
          onTap: _pickDeadline,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Deadline'),
            child: Text(_deadline != null ? DateFormat('yyyy-MM-dd').format(_deadline!) : ''),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('Assign Employees', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        EmployeeMultiPicker(
          allEmployees: widget.allEmployees,
          selectedEmployees: _pickedEmployees,
          onAdd: (emp) => setState(() => _pickedEmployees.add(emp)),
          onRemove: (emp) => setState(() => _pickedEmployees.remove(emp)),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: !canSave
              ? null
              : () async {
                  setState(() => _saving = true);
                  await Future.sync(() => widget.onSave(
                        _title.text.trim(),
                        _description.text.trim().isEmpty ? null : _description.text.trim(),
                        _deadline,
                        _pickedEmployees.map((e) => e.id).toList(),
                      ));
                  if (mounted) setState(() => _saving = false);
                },
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
