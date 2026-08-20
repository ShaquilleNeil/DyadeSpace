import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/employee.dart';

/// Small avatar + name/role — used in the project detail's horizontal
/// employee strip.
class EmployeeItem extends StatelessWidget {
  const EmployeeItem({super.key, required this.employee});

  final Employee employee;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundImage: (employee.avatarUrl?.isNotEmpty ?? false)
                ? CachedNetworkImageProvider(employee.avatarUrl!)
                : null,
            child: (employee.avatarUrl?.isNotEmpty ?? false) ? null : const Icon(Icons.person),
          ),
          const SizedBox(height: 6),
          Text(employee.firstName, maxLines: 1, style: Theme.of(context).textTheme.labelMedium),
          Text(
            employee.role,
            maxLines: 1,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
