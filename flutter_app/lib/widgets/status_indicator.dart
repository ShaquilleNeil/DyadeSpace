import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_strings.dart';
import '../models/task_item.dart';
import '../providers/locale_provider.dart';
import '../theme/app_tokens.dart';

/// An 8px coloured dot + localized status label.
/// The dot is the status colour, or danger when the task is overdue.
class StatusIndicator extends ConsumerWidget {
  final TaskStatus status;
  final bool overdue;

  const StatusIndicator({
    super.key,
    required this.status,
    this.overdue = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final color =
        overdue ? tokens.danger : tokens.statusColorFor(status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          overdue ? s.overdue : statusLabel(s, status),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: overdue ? tokens.danger : tokens.textSecondary,
          ),
        ),
      ],
    );
  }
}

/// Localized label for a task status. Never a raw enum name.
String statusLabel(AppStrings s, TaskStatus status) {
  switch (status) {
    case TaskStatus.todo:
      return s.toDo;
    case TaskStatus.inProgress:
      return s.inProgress;
    case TaskStatus.blocked:
      return s.blocked;
    case TaskStatus.toConfirm:
      return s.toConfirm;
    case TaskStatus.paused:
      return s.paused;
    case TaskStatus.done:
      return s.done;
  }
}

/// Label for a delivery stop's "couldn't complete" reason key
/// (see stopFailReasonKeys in run_stop.dart), localized.
String stopFailReasonLabel(AppStrings strings, String? key) {
  switch (key) {
    case 'out_of_stock':
      return strings.failOutOfStock;
    case 'no_access':
      return strings.noAccess;
    case 'wrong_item':
      return strings.failWrongItem;
    case 'nobody_there':
      return strings.failNobodyThere;
    case 'other':
    default:
      return strings.other;
  }
}

/// Label for a BlockedReason, localized.
String blockedReasonLabel(AppStrings strings, BlockedReason? reason) {
  switch (reason) {
    case BlockedReason.waitingMaterials:
      return strings.waitingMaterials;
    case BlockedReason.waitingPerson:
      return strings.waitingPerson;
    case BlockedReason.noAccess:
      return strings.noAccess;
    case BlockedReason.other:
    case null:
      return strings.other;
  }
}
