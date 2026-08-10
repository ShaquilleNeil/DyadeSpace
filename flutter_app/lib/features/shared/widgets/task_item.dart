import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/task.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/status_colors.dart';

/// Expandable task card — collapsed shows title + status chip; expanded
/// shows the deadline and a "View Details" button that pushes the task route.
class TaskItem extends StatefulWidget {
  const TaskItem({
    super.key,
    required this.task,
    this.showRemove = false,
    this.onRemove,
  });

  final Task task;
  final bool showRemove;
  final VoidCallback? onRemove;

  @override
  State<TaskItem> createState() => _TaskItemState();
}

class _TaskItemState extends State<TaskItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final palette = taskStatusPalette(context, task.status);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md + 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(task.title, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: palette.background,
                      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                    ),
                    child: Text(
                      TaskStatus.label(task.status),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: palette.foreground, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (widget.showRemove) ...[
                    const SizedBox(width: AppSpacing.md),
                    InkWell(
                      onTap: widget.onRemove,
                      child: Text(
                        'Remove',
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  ],
                  const SizedBox(width: AppSpacing.sm),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_circle_down_outlined),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.only(
                left: AppSpacing.md + 2,
                right: AppSpacing.md + 2,
                bottom: AppSpacing.md + 2,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Due: ${task.deadline != null ? DateFormat('yyyy-MM-dd').format(task.deadline!) : ''}',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  FilledButton.icon(
                    onPressed: () => context.push('/task/${task.id}'),
                    icon: const Icon(Icons.arrow_forward, size: 18),
                    label: const Text('View Details'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
