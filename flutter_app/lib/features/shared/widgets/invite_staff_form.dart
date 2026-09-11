import 'package:flutter/material.dart';

import '../../../models/employee.dart';
import '../../../models/project.dart';
import '../../../theme/app_spacing.dart';
import 'form_sheet_scaffold.dart';
import 'project_multi_picker.dart';

/// Admin-only sheet for inviting a new staff member by email — creates their
/// account server-side (see `InviteController`) rather than editing an
/// existing one, so it collects name/email in addition to role + projects.
class InviteStaffForm extends StatefulWidget {
  const InviteStaffForm({
    super.key,
    required this.allProjects,
    required this.onSave,
  });

  final List<Project> allProjects;
  final Future<void> Function(
    String firstName,
    String lastName,
    String email,
    String role,
    List<String> projectIds,
  ) onSave;

  @override
  State<InviteStaffForm> createState() => _InviteStaffFormState();
}

// Mirrors the email check the `inviteStaff` Cloud Function enforces
// server-side, so a malformed address is caught before the round-trip.
final _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

class _InviteStaffFormState extends State<InviteStaffForm> {
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  String _role = EmployeeRole.employee;
  final Set<Project> _selectedProjects = {};
  bool _saving = false;

  bool get _isEmailValid => _emailPattern.hasMatch(_email.text.trim());

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormSheetScaffold(
      title: 'Invite Staff Member',
      children: [
        TextField(
          controller: _firstName,
          decoration: const InputDecoration(labelText: 'First Name'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _lastName,
          decoration: const InputDecoration(labelText: 'Last Name'),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            labelText: 'Email',
            errorText: _email.text.isNotEmpty && !_isEmailValid
                ? 'Enter a valid email address'
                : null,
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.lg),
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
          onPressed: _saving || _firstName.text.trim().isEmpty || !_isEmailValid
              ? null
              : () async {
                  setState(() => _saving = true);
                  await widget.onSave(
                    _firstName.text.trim(),
                    _lastName.text.trim(),
                    _email.text.trim(),
                    _role,
                    _selectedProjects.map((p) => p.id).toList(),
                  );
                  if (mounted) setState(() => _saving = false);
                },
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Send Invite'),
        ),
      ],
    );
  }
}
