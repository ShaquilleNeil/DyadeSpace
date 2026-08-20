import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../theme/app_spacing.dart';
import 'form_sheet_scaffold.dart';

/// Bottom-sheet form for creating a new project. There was no equivalent
/// screen in the original app — projects were created directly in the
/// Supabase table editor — so this is a new addition, not a ported screen.
class ProjectForm extends StatefulWidget {
  const ProjectForm({super.key, required this.onSave});

  final void Function(String name, String? description, String? address, File? photo) onSave;

  @override
  State<ProjectForm> createState() => _ProjectFormState();
}

class _ProjectFormState extends State<ProjectForm> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();
  File? _photo;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 70,
    );
    if (picked != null) {
      setState(() => _photo = File(picked.path));
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSave = _name.text.trim().isNotEmpty && !_saving;

    return FormSheetScaffold(
      title: 'Add Project',
      children: [
        GestureDetector(
          onTap: _pickPhoto,
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
            ),
            clipBehavior: Clip.antiAlias,
            child: _photo != null
                ? Image.file(_photo!, fit: BoxFit.cover, width: double.infinity)
                : const Center(child: Icon(Icons.add_a_photo, size: 32)),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: 'Name'),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _description,
          decoration: const InputDecoration(labelText: 'Description'),
          maxLines: 2,
        ),
        const SizedBox(height: AppSpacing.md),
        TextField(
          controller: _address,
          decoration: const InputDecoration(labelText: 'Address'),
        ),
        const SizedBox(height: AppSpacing.xl),
        FilledButton(
          onPressed: !canSave
              ? null
              : () async {
                  setState(() => _saving = true);
                  await Future.sync(() => widget.onSave(
                        _name.text.trim(),
                        _description.text.trim().isEmpty ? null : _description.text.trim(),
                        _address.text.trim().isEmpty ? null : _address.text.trim(),
                        _photo,
                      ));
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
