import 'package:flutter/material.dart';

import '../../../models/project.dart';
import '../../../theme/app_spacing.dart';

/// Searchable multi-select project picker — mirrors [EmployeeMultiPicker],
/// used by the admin staff-edit sheet to set which project(s) an employee
/// belongs to.
class ProjectMultiPicker extends StatelessWidget {
  const ProjectMultiPicker({
    super.key,
    required this.allProjects,
    required this.selectedProjects,
    required this.onAdd,
    required this.onRemove,
  });

  final List<Project> allProjects;
  final Set<Project> selectedProjects;
  final ValueChanged<Project> onAdd;
  final ValueChanged<Project> onRemove;

  @override
  Widget build(BuildContext context) {
    TextEditingController? fieldController;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectedProjects.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: selectedProjects.map((project) {
                return InputChip(
                  label: Text(project.name),
                  onDeleted: () => onRemove(project),
                );
              }).toList(),
            ),
          ),
        Autocomplete<Project>(
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.toLowerCase();
            return allProjects.where((project) =>
                !selectedProjects.contains(project) &&
                project.name.toLowerCase().contains(query));
          },
          displayStringForOption: (project) => project.name,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            fieldController = controller;
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'Add project',
                prefixIcon: Icon(Icons.search),
              ),
            );
          },
          onSelected: (project) {
            onAdd(project);
            fieldController?.clear();
          },
        ),
      ],
    );
  }
}
