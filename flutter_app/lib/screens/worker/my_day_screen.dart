import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_strings.dart';
import '../../models/app_user.dart';
import '../../models/site.dart';
import '../../models/stage.dart';
import '../../models/task_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/sites_provider.dart';
import '../../providers/stages_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../services/task_service.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/site_header.dart';
import '../../widgets/task_card.dart';
import '../../widgets/task_chain.dart';
import '../task_screen.dart';

/// The worker's whole world: their tasks for today, grouped by
/// site. Dependency chains render whole - as one connected stack
/// with the line and lock nodes - whenever any of MY steps belongs
/// to today. Chains are computed from the FULL task list, so a
/// chain can cross workers: if Eli's step comes before mine,
/// his step shows in my stack as a context card (name + status,
/// no actions) and my step stays locked until his is Done.
class MyDayScreen extends ConsumerWidget {
  const MyDayScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final myAsync = ref.watch(myTasksProvider);
    final siteById = ref.watch(siteByIdProvider);
    return myAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (mine) {
        final me = ref.watch(currentUserProvider).valueOrNull;
        final all = ref.watch(allTasksProvider).valueOrNull ?? mine;
        final users = ref.watch(allUsersProvider).valueOrNull ?? [];
        final userById = {for (final u in users) u.id: u};
        final index = ChainIndex.from(all);
        // Null while the stage/task streams load — tasks behave
        // exactly as they do today until it lands. Tasks in a
        // stage that is not Active and not Completed are hidden
        // here: their stage has not been started yet.
        final stageIndex = ref.watch(stageIndexProvider);
        // Done tasks never show here: the moment a task is
        // marked Done it leaves My Day. tasksForToday still
        // returns tasks finished today (the Board's Today
        // filter relies on that), so the Done filter lives
        // here, in My Day only — the Board keeps showing them.
        final today = TaskService.tasksForToday(mine, DateTime.now(), stageIndex)
            .where((t) => t.status != TaskStatus.done)
            .toList();
        final visibleIds = today.map((t) => t.id).toSet();
        // Pull in every step of any chain that touches my today -
        // including steps assigned to other workers. Done steps
        // stay out, like every other done task: a finished
        // predecessor needs no context card, and the step after
        // it is unlocked once it is Done.
        for (final t in today) {
          final chain = index.chainOf[t.id];
          if (chain != null) {
            visibleIds.addAll(chain
                .where((c) => c.status != TaskStatus.done)
                .map((c) => c.id));
          }
        }
        final myVisible =
            mine.where((t) => visibleIds.contains(t.id)).toList();
        final hasOpenTasks =
            myVisible.any((t) => t.status != TaskStatus.done);
        final renderTasks =
            all.where((t) => visibleIds.contains(t.id)).toList();
        final bySite = <String, List<TaskItem>>{};
        for (final t in renderTasks) {
          bySite.putIfAbsent(t.siteId, () => []).add(t);
        }
        final siteIds = bySite.keys.toList()
          ..sort((a, b) => (siteById[a]?.name ?? '')
              .compareTo(siteById[b]?.name ?? ''));
        // Clock-in/out is the one-tap button next to the My Day
        // title in the shell AppBar (see clock_in_button.dart);
        // nothing clock-related lives on this screen anymore.
        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 28),
          children: [
            if (!hasOpenTasks)
              Center(child: Text(s.noTasks))
            else
              for (final siteId in siteIds) ...[
                SiteHeader(site: siteById[siteId]),
                ..._siteWidgets(context, ref, s, bySite[siteId]!, index,
                    stageIndex, siteById, me?.id ?? '', userById, me),
              ],
          ],
        );
      },
    );
  }

  /// One site's slice of the render list: chains first (each as a
  /// connected stack, in chain order - my steps as action cards,
  /// other workers' steps as context cards), then my standalone
  /// open tasks as plain cards.
  List<Widget> _siteWidgets(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    List<TaskItem> tasks,
    ChainIndex index,
    StageIndex? stageIndex,
    Map<String, Site> siteById,
    String myId,
    Map<String, AppUser> userById,
    AppUser? me,
  ) {
    final widgets = <Widget>[];
    final renderedChains = <String>{};
    for (final t in tasks) {
      final chain = index.chainOf[t.id];
      if (chain == null) continue;
      final key = chain.first.id;
      if (!renderedChains.add(key)) continue;
      final steps = chain
          .where((c) =>
              c.siteId == t.siteId && tasks.any((x) => x.id == c.id))
          .toList();
      for (var i = 0; i < steps.length; i++) {
        final step = steps[i];
        final locked = index.isLockedNow(step) ||
            (stageIndex?.isLockedByStage(step) ?? false);
        widgets.add(ChainStepRow(
          task: step,
          previous: i > 0 ? steps[i - 1] : null,
          isFirst: i == 0,
          isLast: i == steps.length - 1,
          dimmed: locked,
          child: step.assigneeIds.contains(myId)
              ? _card(context, ref, s, step, index, stageIndex, siteById, me)
              : TaskCard(
                  task: step,
                  site: siteById[step.siteId],
                  assignees: taskAssignees(step, userById, s),
                  // A chain step that is not mine still opens -
                  // read-only (I am not its assignee, and this
                  // shell never belongs to a manager).
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TaskScreen(
                        task: step,
                        readOnly: !taskEditableBy(step, me),
                      ),
                    ),
                  ),
                ),
        ));
      }
    }
    for (final t in tasks.where((t) =>
        t.assigneeIds.contains(myId) &&
        !index.isInChain(t) &&
        t.status != TaskStatus.done)) {
      widgets.add(_card(context, ref, s, t, index, stageIndex, siteById, me));
    }
    return widgets;
  }

  Widget _card(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    TaskItem t,
    ChainIndex index,
    StageIndex? stageIndex,
    Map<String, Site> siteById,
    AppUser? me,
  ) {
    final tokens = AppTokens.of(context);
    // Locked by the chain OR by the stage — see the Board. The
    // chain predecessor wins the "Waiting on" chip; a
    // stage-only lock names the stage instead.
    final chainLocked = index.isLockedNow(t);
    final stage = stageIndex?.stageOf(t);
    final stageLocked = stageIndex?.isLockedByStage(t) ?? false;
    final locked = chainLocked || stageLocked;
    final predecessor = index.predecessor(t);
    Widget? footer;
    if (locked) {
      // A locked task NEVER gets a Start button - not even when
      // the predecessor cannot be named.
      footer = chainLocked
          ? (predecessor == null
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child:
                      WaitingChip(label: s.waitingOn(predecessor.title)),
                ))
          : (stage == null
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: WaitingChip(label: s.waitingOn(stage.name)),
                ));
    } else {
      final startButton = (t.status == TaskStatus.todo ||
              t.status == TaskStatus.toConfirm)
          ? SizedBox(
              width: double.infinity,
              child: TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: tokens.surfaceRaised,
                  foregroundColor: Theme.of(context).colorScheme.onSurface,
                  minimumSize: const Size.fromHeight(40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  textStyle: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                onPressed: () =>
                    ref.read(taskServiceProvider).startTask(t),
                child: Text(s.start),
              ),
            )
          : null;
      // Soft link: the note rides above the Start button - the
      // order is visible, but starting early is allowed.
      final softNote = (t.dependsSoft &&
              predecessor != null &&
              predecessor.status != TaskStatus.done)
          ? Align(
              alignment: Alignment.centerLeft,
              child: SoftLinkChip(label: s.usuallyAfter(predecessor.title)),
            )
          : null;
      if (softNote != null && startButton != null) {
        footer = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [softNote, const SizedBox(height: 8), startButton],
        );
      } else {
        footer = softNote ?? startButton;
      }
    }
    return TaskCard(
      task: t,
      site: siteById[t.siteId],
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TaskScreen(
            task: t,
            // My own card: the computation gives full access
            // (my uid matches the assignee).
            readOnly: !taskEditableBy(t, me),
          ),
        ),
      ),
      footer: footer,
    );
  }
}
