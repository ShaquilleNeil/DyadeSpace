import 'package:flutter/material.dart';

import '../../../models/employee.dart';
import '../../../theme/app_spacing.dart';

/// Searchable multi-select employee picker — selected employees render as
/// removable pills above a type-to-filter field. Shared between task
/// creation and task editing so both stay in sync.
class EmployeeMultiPicker extends StatelessWidget {
  const EmployeeMultiPicker({
    super.key,
    required this.allEmployees,
    required this.selectedEmployees,
    required this.onAdd,
    required this.onRemove,
  });

  final List<Employee> allEmployees;
  final Set<Employee> selectedEmployees;
  final ValueChanged<Employee> onAdd;
  final ValueChanged<Employee> onRemove;

  @override
  Widget build(BuildContext context) {
    TextEditingController? fieldController;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (selectedEmployees.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: selectedEmployees.map((emp) {
                return InputChip(
                  label: Text(emp.fullName),
                  onDeleted: () => onRemove(emp),
                );
              }).toList(),
            ),
          ),
        Autocomplete<Employee>(
          optionsBuilder: (textEditingValue) {
            final query = textEditingValue.text.toLowerCase();
            return allEmployees.where((emp) =>
                !selectedEmployees.contains(emp) &&
                emp.fullName.toLowerCase().contains(query));
          },
          displayStringForOption: (emp) => emp.fullName,
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            fieldController = controller;
            return TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: const InputDecoration(
                labelText: 'Add employee',
                prefixIcon: Icon(Icons.search),
              ),
            );
          },
          onSelected: (emp) {
            onAdd(emp);
            fieldController?.clear();
          },
        ),
      ],
    );
  }
}
