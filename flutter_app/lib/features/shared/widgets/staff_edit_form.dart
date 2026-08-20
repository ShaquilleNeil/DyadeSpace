import 'package:flutter/material.dart';

import '../../../models/employee.dart';
import '../../../models/project.dart';
import '../../../theme/app_spacing.dart';
import 'form_sheet_scaffold.dart';
import 'project_multi_picker.dart';

/// Admin-only sheet for changing an employee's role (worker/manager) and
/// which project(s) they're assigned to.
class StaffEditForm extends StatefulWidget {
  const StaffEditForm({
    super.key,
    required this.employee,
    required this.allProjects,
    required this.onSave,
  });

  final Employee employee;
  final List<Project> allProjects;
  final void Function(String role, List<String> projectIds) onSave;

  @override
  State<StaffEditForm> createState() => _StaffEditFormState();
}

class _StaffEditFormState extends State<StaffEditForm> {
  late String _role = widget.employee.role == EmployeeRole.admin
      ? EmployeeRole.manager // admins aren't reassigned through this sheet
      : widget.employee.role;
  late final Set<Project> _selectedProjects = widget.allProjects
      .where((p) => widget.employee.projectIds.contains(p.id))
      .toSet();
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    return FormSheetScaffold(
      title: 'Edit ${widget.employee.fullName}',
      children: [
        Text('Role', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: EmployeeRole.employee, label: Text('Worker')),
            ButtonSegment(value: EmployeeRole.manager, label: Text('Manager')),
          ],
          selected: {_role},
          onSelectionChanged: (selection) => setState(() => _role = selection.first),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Projects', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        ProjectMultiPicker(
          allProjects: widget.allProjects,
          selectedProjects: _selectedProjects,
          onAdd: (project) => setState(() => _selectedProjects.add(project)),
          onRemove: (project) => setState(() => _selectedProjects.remove(project)),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: _saving
              ? null
              : () async {
                  setState(() => _saving = true);
                  await Future.sync(() => widget.onSave(
                        _role,
                        _selectedProjects.map((p) => p.id).toList(),
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
