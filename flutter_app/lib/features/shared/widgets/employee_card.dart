import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../models/employee.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/status_colors.dart';

/// Staff-directory grid card with a status dot and an "add task" quick
/// action that floats above the card's top edge.
class EmployeeCard extends StatelessWidget {
  const EmployeeCard({
    super.key,
    required this.employee,
    required this.taskCount,
    required this.onAddTask,
    this.onTap,
    this.actionIcon = Icons.add,
  });

  final Employee employee;
  final int taskCount;
  final VoidCallback onAddTask;
  final VoidCallback? onTap;
  final IconData actionIcon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: Card(
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
                child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.topCenter,
                children: [
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: employeeAvailabilityColor(
                          employeeAvailabilityFromTaskCount(taskCount),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.md + 2,
                      AppSpacing.xl - 2,
                      AppSpacing.md + 2,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundImage: (employee.avatarUrl?.isNotEmpty ?? false)
                              ? CachedNetworkImageProvider(employee.avatarUrl!)
                              : null,
                          child: (employee.avatarUrl?.isNotEmpty ?? false)
                              ? null
                              : const Icon(Icons.person, size: 28),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          employee.firstName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          employee.role,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -10,
            right: -6,
            child: IconButton.filled(
              onPressed: onAddTask,
              icon: Icon(actionIcon, size: 18),
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                minimumSize: const Size(32, 32),
                padding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
