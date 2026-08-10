import 'package:flutter/material.dart';

import '../../../models/employee.dart';

/// Full-width row with avatar, name/role, and a remove action — used on the
/// project employees list screen.
class EmployeeRow extends StatelessWidget {
  const EmployeeRow({super.key, required this.employee, required this.onRemove});

  final Employee employee;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage:
                (employee.avatarUrl?.isNotEmpty ?? false) ? NetworkImage(employee.avatarUrl!) : null,
            child: (employee.avatarUrl?.isNotEmpty ?? false) ? null : const Icon(Icons.person),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(employee.fullName, style: Theme.of(context).textTheme.bodyMedium),
                Text(
                  employee.role,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRemove,
            child: Text('Remove', style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );
  }
}
