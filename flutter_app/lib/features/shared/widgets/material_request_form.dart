import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/material_request.dart';
import '../../../models/project.dart';
import '../../../theme/app_spacing.dart';
import 'form_sheet_scaffold.dart';
import 'multi_photo_picker.dart';

class _ItemRow {
  final name = TextEditingController();
  final quantity = TextEditingController();
  final unit = TextEditingController();

  bool get isFilled => name.text.trim().isNotEmpty && quantity.text.trim().isNotEmpty;

  MaterialRequestItem toItem() => MaterialRequestItem(
        name: name.text.trim(),
        quantity: quantity.text.trim(),
        unit: unit.text.trim().isEmpty ? null : unit.text.trim(),
      );

  void dispose() {
    name.dispose();
    quantity.dispose();
    unit.dispose();
  }
}

/// Bottom-sheet form for submitting a material request — a repeatable list
/// of items (name/qty/unit) plus optional photos, scoped to one of the
/// submitter's projects. Used by both workers and managers.
class MaterialRequestForm extends StatefulWidget {
  const MaterialRequestForm({
    super.key,
    required this.projects,
    required this.onSave,
  });

  final List<Project> projects;
  final Future<void> Function(
    String projectId,
    List<MaterialRequestItem> items,
    String? notes,
    List<File> photos,
  ) onSave;

  @override
  State<MaterialRequestForm> createState() => _MaterialRequestFormState();
}

class _MaterialRequestFormState extends State<MaterialRequestForm> {
  late Project? _project = widget.projects.length == 1 ? widget.projects.first : null;
  final List<_ItemRow> _rows = [_ItemRow()];
  final _notes = TextEditingController();
  final List<File> _photos = [];
  bool _saving = false;

  @override
  void dispose() {
    for (final row in _rows) {
      row.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  bool get _canSave =>
      !_saving && _project != null && _rows.any((r) => r.isFilled);

  Future<void> _submit() async {
    setState(() => _saving = true);
    final items = _rows.where((r) => r.isFilled).map((r) => r.toItem()).toList();
    await widget.onSave(
      _project!.id,
      items,
      _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      _photos,
    );
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    return FormSheetScaffold(
      title: 'Request Materials',
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
          const SizedBox(height: AppSpacing.lg),
        ],
        Text('Items', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        for (var i = 0; i < _rows.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _rows[i].name,
                    decoration: const InputDecoration(labelText: 'Item'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _rows[i].quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Qty'),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _rows[i].unit,
                    decoration: const InputDecoration(labelText: 'Unit'),
                  ),
                ),
                if (_rows.length > 1)
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Remove item',
                    onPressed: () => setState(() {
                      _rows[i].dispose();
                      _rows.removeAt(i);
                    }),
                  ),
              ],
            ),
          ),
        OutlinedButton(
          onPressed: () => setState(() => _rows.add(_ItemRow())),
          child: const Text('+ Add Another Item'),
        ),
        const SizedBox(height: AppSpacing.lg),
        TextField(
          controller: _notes,
          decoration: const InputDecoration(labelText: 'Notes (optional)'),
          maxLines: 2,
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
              : const Text('Submit Request'),
        ),
      ],
    );
  }
}
