import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../l10n/app_strings.dart';
import '../models/app_user.dart';
import '../models/site.dart';
import '../models/task_item.dart';
import '../providers/locale_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import 'member_tile.dart';
import 'run_progress_bar.dart';
import 'status_indicator.dart';

/// One task as a clean board card: the card itself stays neutral
/// and the colour lives only in the status indicator and the
/// person's avatar. Semibold title, one muted subtitle line
/// (site · unit · due), status row with a thin progress bar
/// underneath. Screens that need an action under the card
/// (e.g. My Day's Start button) pass it as [footer]. Tap opens
/// the task.
/// One assignee as shown on a task card: name, role (for the
/// avatar colour) and photo when set. Built by [taskAssignees]
/// from the crew map — a former member (user doc gone) keeps
/// their id's name as the localized "Former member" label.
class TaskAssigneeDisplay {
  final String name;
  final UserRole? role;
  final String? photoUrl;

  const TaskAssigneeDisplay({
    required this.name,
    this.role,
    this.photoUrl,
  });
}

/// The assignees of [task] in assignment order, resolved against
/// [userById]. Unknown ids (a removed user) render with the
/// localized former-member label.
List<TaskAssigneeDisplay> taskAssignees(
  TaskItem task,
  Map<String, AppUser> userById,
  AppStrings s,
) {
  return [
    for (final id in task.assigneeIds)
      TaskAssigneeDisplay(
        name: userById[id]?.name ?? s.formerMember,
        role: userById[id]?.role,
        photoUrl: userById[id]?.photoUrl,
      ),
  ];
}

class TaskCard extends ConsumerWidget {
  final TaskItem task;
  final Site? site;

  /// The linked unit's name, when the task belongs to a unit
  /// (apartment). Shown in the meta line instead of the
  /// free-text unit field — screens that know the units pass
  /// it; the rest keep today's rendering.
  final String? unitName;

  /// The task's assignees, in assignment order. The card shows
  /// the first three avatars (a "+N" circle for the rest) and
  /// the first two names ("+N more" after that); an empty list
  /// renders no assignee row at all.
  final List<TaskAssigneeDisplay> assignees;
  final bool locked;
  final String? waitingOn;
  final VoidCallback? onTap;
  final Widget? footer;

  const TaskCard({
    super.key,
    required this.task,
    this.site,
    this.unitName,
    this.assignees = const [],
    this.locked = false,
    this.waitingOn,
    this.onTap,
    this.footer,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final dateFmt = DateFormat('EEE MMM d');
    final due = task.dueDate == null ? null : dateFmt.format(task.dueDate!);
    final meta = [
      if (site != null) site!.name,
      if (unitName != null)
        'Unit $unitName'
      else if (task.unit.isNotEmpty)
        'Unit ${task.unit}',
      if (due != null) due,
    ].join(' · ');

    // The assignee names line: first two names, "+N more" for
    // the rest. The avatars live top-right next to the title.
    final assigneeNames = assignees.map((a) => a.name).toList();
    final namesLine = assigneeNames.isEmpty
        ? null
        : assigneeNames.length <= 2
            ? assigneeNames.join(', ')
            : '${assigneeNames.take(2).join(', ')} ${s.moreAssignees(assigneeNames.length - 2)}';

    // The span chip and bar only live inside the window:
    // outside it [TaskItem.spanDayIndex] is null, and the bar
    // falls back to the status fraction instead of pretending
    // it is day 1 of the window.
    final spanDay = task.spanDayIndex;
    final double fraction;
    if (spanDay != null) {
      fraction = (spanDay / (task.spanTotalDays ?? 1)).clamp(0.0, 1.0);
    } else {
      switch (task.status) {
        case TaskStatus.todo:
          fraction = 0.0;
        case TaskStatus.inProgress:
        case TaskStatus.toConfirm:
        case TaskStatus.blocked:
        case TaskStatus.paused:
          fraction = 0.5;
        case TaskStatus.done:
          fraction = 1.0;
      }
    }

    return Opacity(
      opacity: locked ? 0.5 : 1,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: appCardDecoration(context),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                  ),
                  if (assignees.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    _AssigneeAvatars(assignees: assignees),
                  ],
                ],
              ),
              if (namesLine != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    namesLine,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: tokens.textTertiary,
                    ),
                  ),
                ),
              if (meta.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    meta,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: tokens.textTertiary,
                    ),
                  ),
                ),
              if (task.status == TaskStatus.blocked &&
                  task.blockedReason != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    task.blockedNote.isNotEmpty
                        ? task.blockedNote
                        : blockedReasonLabel(s, task.blockedReason),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: tokens.danger,
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Flexible(child: StatusIndicator(status: task.status)),
                  if (task.spanDayIndex != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppTokens.accentMuted,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        s.dayOf(task.spanDayIndex!,
                            task.spanTotalDays ?? task.spanDayIndex!),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: tokens.accentText,
                        ),
                      ),
                    ),
                  ],
                  if (task.isOverdue) ...[
                    const SizedBox(width: 8),
                    Text(
                      s.overdue,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: tokens.danger,
                      ),
                    ),
                  ] else if (task.carriedOver) ...[
                    const SizedBox(width: 8),
                    Text(
                      s.carriedOver,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: tokens.textTertiary,
                      ),
                    ),
                  ],
                  if (task.photoUrls.isNotEmpty) ...[
                    const Spacer(),
                    Icon(
                      Icons.photo_camera_outlined,
                      size: 15,
                      color: tokens.textTertiary,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${task.photoUrls.length}',
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              RunProgressBar(
                completed: (fraction * 100).round(),
                total: 100,
                height: 4,
              ),
              if (task.startDate != null) ...[
                const SizedBox(height: 6),
                Text(
                  '${s.startsOn} ${dateFmt.format(task.startDate!)}'
                  '${task.dueDate != null ? ' · ${s.due} ${dateFmt.format(task.dueDate!)}' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: tokens.textTertiary,
                  ),
                ),
              ],
              if (locked) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: tokens.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        waitingOn != null
                            ? s.waitingOn(waitingOn!)
                            : s.locked,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: tokens.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              if (footer != null) ...[
                const SizedBox(height: 10),
                footer!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The assignee avatars on a task card: the first three, slightly
/// overlapped, plus a "+N" circle when there are more. The count
/// circle reuses the worker avatar colour so it reads as part of
/// the same stack.
class _AssigneeAvatars extends StatelessWidget {
  final List<TaskAssigneeDisplay> assignees;

  const _AssigneeAvatars({required this.assignees});

  @override
  Widget build(BuildContext context) {
    const size = 28.0;
    final shown = assignees.take(3).toList();
    final extra = assignees.length - shown.length;
    final colors = AppTokens.roleAvatarColors(UserRole.worker);
    final totalWidth = size + (shown.length - 1) * (size - 10) + (extra > 0 ? size - 10 : 0);
    return SizedBox(
      width: totalWidth,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * (size - 10),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).cardColor,
                    width: 2,
                  ),
                ),
                child: RoleAvatar(
                  name: shown[i].name,
                  role: shown[i].role,
                  size: size,
                  photoUrl: shown[i].photoUrl,
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * (size - 10),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: colors.bg,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).cardColor,
                    width: 2,
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: colors.fg,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
