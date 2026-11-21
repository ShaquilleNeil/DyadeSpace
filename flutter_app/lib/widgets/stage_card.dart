import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_strings.dart';
import '../models/stage.dart';
import '../models/task_item.dart';
import '../providers/locale_provider.dart';
import '../theme/app_tokens.dart';
import 'run_progress_bar.dart';
import 'status_indicator.dart';
import 'task_chain.dart';

String _firstName(String name) => name.split(' ').first;

/// One stage of a site roadmap, per the approved concept: % at
/// the top-right, name, status line, thin progress bar, task
/// count + assignees, tap to expand its tasks. Locked stages
/// render dimmed. Admin controls (Start / Move up / Move down /
/// Skip / Un-skip / Delete) only when [isManager] is true;
/// completed stages get no Start / Move / Skip — there is
/// nothing to start, move or skip once every task is done — but
/// Delete stays available. Expanded, the stage's tasks render
/// with their chain interconnections ([chain]): chained steps
/// draw the chain rail, a step waiting on a task in another
/// stage names that task in its "Waiting on" chip.
class StageCard extends ConsumerWidget {
  final Stage stage;
  final int stageNumber;
  final StageIndex index;
  final ChainIndex chain;
  final Map<String, String> userName;
  final bool expanded;
  final bool isManager;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onToggleExpand;
  final VoidCallback onStart;
  final VoidCallback onSkip;
  final VoidCallback onUnskip;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;
  final void Function(TaskItem task) onTaskTap;
  final void Function(TaskItem task) onDeleteTask;

  const StageCard({
    super.key,
    required this.stage,
    required this.stageNumber,
    required this.index,
    required this.chain,
    required this.userName,
    required this.expanded,
    required this.isManager,
    required this.isFirst,
    required this.isLast,
    required this.onToggleExpand,
    required this.onStart,
    required this.onSkip,
    required this.onUnskip,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
    required this.onTaskTap,
    required this.onDeleteTask,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final status = index.statusOf(stage);
    final progress = index.progressOf(stage);
    final color = stageStatusColor(status, tokens);
    final tasks = index.tasksOf(stage);
    final assignees = <String>{
      for (final t in tasks)
        for (final id in t.assigneeIds)
          if (userName[id] != null && userName[id]!.isNotEmpty)
            _firstName(userName[id]!),
    };
    final pct = progress.total == 0
        ? 0
        : ((progress.done / progress.total) * 100).round();
    final waitingOnName = status == StageStatus.locked
        ? index.previousStage(stage)?.name
        : null;

    // Admin actions: Start for a Ready stage; Move up / Move
    // down + Skip (or Un-skip) for any other open stage.
    // Completed stages get none — there is nothing to start,
    // move or skip once every task is done.
    final actions = <Widget>[];
    if (isManager && status != StageStatus.completed) {
      if (status == StageStatus.ready) {
        actions.add(_actionButton(
          context,
          label: s.startStage,
          accent: true,
          onPressed: () {
            HapticFeedback.lightImpact();
            onStart();
          },
        ));
      } else {
        if (!isFirst) {
          actions.add(_actionButton(
            context,
            label: s.moveUp,
            onPressed: () {
              HapticFeedback.lightImpact();
              onMoveUp();
            },
          ));
        }
        if (!isLast) {
          actions.add(_actionButton(
            context,
            label: s.moveDown,
            onPressed: () {
              HapticFeedback.lightImpact();
              onMoveDown();
            },
          ));
        }
      }
      actions.add(_actionButton(
        context,
        label: status == StageStatus.skipped ? s.unskipStage : s.skipStage,
        onPressed: () {
          HapticFeedback.lightImpact();
          if (status == StageStatus.skipped) {
            onUnskip();
          } else {
            onSkip();
          }
        },
      ));
    }

    return Opacity(
      // Locked stages render dimmed, like locked chain steps.
      opacity: status == StageStatus.locked ? 0.62 : 1,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.lightImpact();
          onToggleExpand();
        },
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(AppTokens.cardRadius),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    s.stageNumber(stageNumber).toUpperCase(),
                    style:  TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: tokens.textTertiary,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$pct%',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ],
                      // The % measures completion, so it is green
                      // at every percentage — the status dot above
                      // carries the stage's state instead.
                      color: tokens.statusDone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                stage.name,
                style:  TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      s.stageStatusLabel(status,
                          waitingOnName: waitingOnName),
                      style:  TextStyle(
                        fontSize: 12,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 11),
              RunProgressBar(
                completed: progress.done,
                total: progress.total,
                height: 4,
                // The bar measures completion, so it is green at
                // every percentage (the status dot carries the
                // stage's state).
                fillColor: tokens.statusDone,
              ),
              const SizedBox(height: 8),
              RichText(
                text: TextSpan(
                  style: TextStyle(
                    fontSize: 12,
                    color: tokens.textSecondary,
                  ),
                  children: [
                    TextSpan(
                      text: s.tasksDone(progress.done, progress.total),
                      style: TextStyle(
                        color: tokens.statusDone,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (assignees.isNotEmpty)
                      TextSpan(text: ' · ${assignees.join(', ')}'),
                  ],
                ),
              ),
              if (expanded && tasks.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: tokens.border),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _expandedTaskWidgets(context, tasks, s),
                  ),
                ),
              ],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 11),
                Row(
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              ],
              // Delete is available on every stage, including a
              // completed one — cleanup should never be blocked
              // by the stage being done. Admins only; the
              // confirmation lives in the roadmap view.
              if (isManager) ...[
                SizedBox(height: actions.isNotEmpty ? 8 : 11),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: tokens.danger,
                      minimumSize: const Size.fromHeight(40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(color: tokens.border),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      onDelete();
                    },
                    child: Text(s.deleteStage),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The expanded task list, chains first and contiguous — the
  /// same pattern as the Today tab. Each chain renders as a
  /// ChainStepRow rail, then the standalone tasks in their usual
  /// order. A step whose predecessor lives in another stage
  /// still draws its rail from that predecessor's status, and
  /// its "Waiting on" chip names the other stage's task.
  List<Widget> _expandedTaskWidgets(
      BuildContext context, List<TaskItem> tasks, AppStrings s) {
    final widgets = <Widget>[];
    final renderedChains = <String>{};
    for (final t in tasks) {
      final c = chain.chainOf[t.id];
      if (c == null) continue;
      if (!renderedChains.add(c.first.id)) continue;
      // Only this stage's steps of the chain, in chain order.
      final steps = c.where((x) => x.stageId == stage.id).toList();
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        widgets.add(ChainStepRow(
          task: step,
          previous: i > 0 ? steps[i - 1] : chain.predecessor(step),
          isFirst: i == 0,
          isLast: i == steps.length - 1,
          dimmed: chain.isLockedNow(step),
          child: _taskRow(context, step, s),
        ));
      }
    }
    for (final t in tasks.where((t) => !chain.isInChain(t))) {
      widgets.add(_taskRow(context, t, s));
    }
    return widgets;
  }

  /// One task row inside the expansion — the same row as the
  /// flat list had (status dot, title, assignee + status), plus
  /// a "Waiting on" chip when the task is locked by its chain
  /// dependency, or a soft-link chip when it may start early.
  /// Tap still opens the task editor.
  Widget _taskRow(BuildContext context, TaskItem t, AppStrings s) {
    final tokens = AppTokens.of(context);
    final pred = chain.predecessor(t);
    final chainLocked = chain.isLockedNow(t);
    final soft = t.dependsOnTaskId != null && t.dependsSoft;
    return InkWell(
      onTap: () => onTaskTap(t),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: tokens.statusColorFor(t.status),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    [
                      for (final id in t.assigneeIds)
                        if (userName[id] != null &&
                            userName[id]!.isNotEmpty)
                          _firstName(userName[id]!),
                      statusLabel(s, t.status),
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: tokens.textTertiary,
                    ),
                  ),
                ),
                // A task in a roadmap stage can only be deleted
                // from here, inside the roadmap — admins and
                // managers only. The nested InkWell wins the
                // gesture arena over the row tap, so deleting
                // never opens the editor by accident.
                if (isManager) ...[
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () => onDeleteTask(t),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline,
                          size: 18, color: tokens.danger),
                    ),
                  ),
                ],
              ],
            ),
            if (chainLocked && pred != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: WaitingChip(label: s.waitingOn(pred.title)),
              ),
            ] else if (soft && pred != null) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: SoftLinkChip(label: s.usuallyAfter(pred.title)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// One admin action button: accent-filled for Start, ghost
  /// (surface, hairline border) for the rest — same button
  /// treatment as the Start buttons on task cards.
  Widget _actionButton(
    BuildContext context, {
    required String label,
    bool accent = false,
    required VoidCallback onPressed,
  }) {
    final tokens = AppTokens.of(context);
    return TextButton(
      style: TextButton.styleFrom(
        backgroundColor:
            accent ? AppTokens.accent : tokens.surfaceRaised,
        foregroundColor:
            accent ? AppTokens.onAccent : tokens.textPrimary,
        minimumSize: const Size.fromHeight(40),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: accent
              ? BorderSide.none
              :  BorderSide(color: tokens.border),
        ),
        textStyle:
            const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
