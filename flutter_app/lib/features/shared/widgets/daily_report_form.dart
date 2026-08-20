import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/project.dart';
import '../../../theme/app_spacing.dart';
import 'form_sheet_scaffold.dart';
import 'multi_photo_picker.dart';

/// Bottom-sheet form for submitting a daily report — date, a free-text
/// summary, progress/task notes, and optional photos. Used by both workers
/// and managers.
class DailyReportForm extends StatefulWidget {
  const DailyReportForm({
    super.key,
    required this.projects,
    required this.onSave,
  });

  final List<Project> projects;
  final Future<void> Function(
    String projectId,
    DateTime date,
    String summary,
    String? taskNotes,
    List<File> photos,
  ) onSave;

  @override
  State<DailyReportForm> createState() => _DailyReportFormState();
}

class _DailyReportFormState extends State<DailyReportForm> {
  late Project? _project = widget.projects.length == 1 ? widget.projects.first : null;
  DateTime _date = DateTime.now();
  final _summary = TextEditingController();
  final _taskNotes = TextEditingController();
  final List<File> _photos = [];
  bool _saving = false;

  @override
  void dispose() {
    _summary.dispose();
    _taskNotes.dispose();
    super.dispose();
  }

  bool get _canSave => !_saving && _project != null && _summary.text.trim().isNotEmpty;

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 1),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    await widget.onSave(
      _project!.id,
      _date,
      _summary.text.trim(),
      _taskNotes.text.trim().isEmpty ? null : _taskNotes.text.trim(),
      _photos,
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return FormSheetScaffold(
      title: 'Daily Report',
      children: [
        if (widget.projects.length > 1) ...[
          DropdownButtonFormField<Project>(
            initialValue: _project,
            hint: const Text('Select Project'),
            decoration: const InputDecoration(labelText: 'Project'),
            items: widget.projects
                .map((p) => DropdownMenuItem(value: p, child: Text(p.name)))
                .toList(),
            onChanged: (p) => setState(() => _project = p),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        InkWell(
          onTap: _pickDate,
          child: InputDecorator(
            decoration: const InputDecoration(labelText: 'Date'),
            child: Text(DateFormat('yyyy-MM-dd').format(_date)),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _summary,
          decoration: const InputDecoration(labelText: 'Summary'),
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _taskNotes,
          decoration: const InputDecoration(labelText: 'Task / progress notes (optional)'),
          maxLines: 3,
        ),
        const SizedBox(height: AppSpacing.lg),
        Text('Photos (optional)', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        MultiPhotoPicker(
          photos: _photos,
          onAdd: (picked) => setState(() => _photos.addAll(picked)),
          onRemoveAt: (index) => setState(() => _photos.removeAt(index)),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: !_canSave ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit Report'),
        ),
      ],
    );
  }
}
