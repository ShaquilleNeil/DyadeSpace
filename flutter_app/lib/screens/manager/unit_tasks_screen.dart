import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/site.dart';
import '../../models/task_item.dart';
import '../../models/unit.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/stages_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/units_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/roadmap_view.dart';
import '../../widgets/run_progress_bar.dart';
import '../../widgets/status_indicator.dart';
import '../../widgets/task_card.dart';
import '../../widgets/task_chain.dart';
import '../task_screen.dart';

/// One unit's tasks: the unit's progress at the top, then its
/// tasks as the same cards the site view shows (status dot,
/// title, assignee, status label, chain strip, Start button for
/// my own tasks — same lock rules as everywhere else). Tap a
/// card to open the task; the + button starts a new task
/// already linked to this unit and site. The unit's name is
/// read live, so a rename lands here without reopening.
class UnitTasksScreen extends ConsumerStatefulWidget {
  final Site site;
  final Unit unit;
  const UnitTasksScreen({super.key, required this.site, required this.unit});

  @override
  ConsumerState<UnitTasksScreen> createState() => _UnitTasksScreenState();
}

class _UnitTasksScreenState extends ConsumerState<UnitTasksScreen> {
  // Tasks view by default; Roadmap shows the unit's stages.
  // Same toggle as the site view — a unit roadmap starts
  // blank, with no template choice.
  bool _showRoadmap = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final site = widget.site;
    final s = ref.watch(stringsProvider);
    final tasksAsync = ref.watch(allTasksProvider);
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final userById = {for (final u in users) u.id: u};
    final myId = ref.watch(currentUserProvider).valueOrNull?.id;
    // Null while the stage/task streams load — tasks behave
    // exactly as they do today until it lands.
    final stageIndex = ref.watch(stageIndexProvider);
    // The live unit: a rename from the site view lands here.
    final liveUnits =
        ref.watch(unitsForSiteProvider(site.id)).valueOrNull ?? [];
    final liveUnit = liveUnits
            .where((u) => u.id == widget.unit.id)
            .firstOrNull ??
        widget.unit;

    return Scaffold(
      appBar: AppBar(title: Text(liveUnit.name)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(s.newTask),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => TaskScreen(
                  initialSiteId: site.id, initialUnitId: liveUnit.id)),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: [
                  ButtonSegment<String>(
                      value: 'tasks', label: Text(s.tasks)),
                  ButtonSegment<String>(
                      value: 'roadmap', label: Text(s.roadmap)),
                ],
                selected: {_showRoadmap ? 'roadmap' : 'tasks'},
                onSelectionChanged: (selection) {
                  if (selection.isNotEmpty) {
                    HapticFeedback.lightImpact();
                    setState(
                        () => _showRoadmap = selection.first == 'roadmap');
                  }
                },
              ),
            ),
          ),
          Expanded(
            child: _showRoadmap
                ? RoadmapView(siteId: site.id, unitId: liveUnit.id)
                : tasksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          final mine = all
              .where((t) =>
                  t.siteId == site.id && t.unitId == liveUnit.id)
              .toList();
          final done =
              mine.where((t) => t.status == TaskStatus.done).length;
          final blocked = mine
              .where((t) => t.status == TaskStatus.blocked)
              .length;
          final pct = mine.isEmpty
              ? 0
              : ((done / mine.length) * 100).round();
          // Same status order as the site view, so a unit's
          // tasks read in the same order as the site's.
          const order = [
            TaskStatus.todo,
            TaskStatus.inProgress,
            TaskStatus.paused,
            TaskStatus.blocked,
            TaskStatus.toConfirm,
            TaskStatus.done,
          ];
          final ordered = [...mine]
            ..sort((a, b) {
              final o = order
                  .indexOf(a.status)
                  .compareTo(order.indexOf(b.status));
              if (o != 0) return o;
              return (a.dueDate ?? DateTime(2100))
                  .compareTo(b.dueDate ?? DateTime(2100));
            });
          final index = ChainIndex.from(all);

          Widget cardFor(TaskItem t) {
            final chain = index.chainOf[t.id];
            // Locked by the chain OR by the stage: a task in a
            // stage that is not Active yet cannot be started.
            // The chain predecessor wins the "Waiting on" label;
            // a stage-only lock names the stage instead.
            final chainLocked = index.isLockedNow(t);
            final stage = stageIndex?.stageOf(t);
            final stageLocked = stageIndex?.isLockedByStage(t) ?? false;
            final locked = chainLocked || stageLocked;
            final predecessor = index.predecessor(t);
            final footerParts = <Widget>[];
            if (chain != null) {
              footerParts.add(
                  ChainStrip(index: index, chain: chain, currentId: t.id));
            }
            // My own tasks start from here — same rule as the
            // Board and the site view: never when locked, only
            // from To do / To confirm.
            final isMine = myId != null && t.assigneeIds.contains(myId);
            if (isMine &&
                !locked &&
                (t.status == TaskStatus.todo ||
                    t.status == TaskStatus.toConfirm)) {
              footerParts.add(SizedBox(
                width: double.infinity,
                child: TextButton(
                  style: TextButton.styleFrom(
                    backgroundColor:
                        Theme.of(context).colorScheme.surfaceContainer,
                    foregroundColor: tokens.textPrimary,
                    minimumSize: const Size.fromHeight(40),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    ref.read(taskServiceProvider).startTask(t);
                  },
                  child: Text(s.start),
                ),
              ));
            }
            Widget? footer;
            if (footerParts.isNotEmpty) {
              footer = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var i = 0; i < footerParts.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    footerParts[i],
                  ],
                ],
              );
            }
            return TaskCard(
              task: t,
              site: site,
              assignees: taskAssignees(t, userById, s),
              locked: locked,
              waitingOn: chainLocked
                  ? predecessor?.title
                  : (stageLocked ? stage?.name : null),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) => TaskScreen(task: t)),
              ),
              footer: footer,
            );
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 88),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Expanded(
                    child: Text(
                      s.tasksDone(done, mine.length),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: tokens.statusDone,
                      ),
                    ),
                  ),
                  Text(
                    '$pct%',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ],
                      color: tokens.statusDone,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              RunProgressBar(
                completed: done,
                total: mine.length,
                height: 4,
              ),
              if (blocked > 0) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    StatusIndicator(status: TaskStatus.blocked),
                    const SizedBox(width: 8),
                    Text(
                      '$blocked ${s.blocked}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: tokens.danger,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              if (mine.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(s.noTasks, textAlign: TextAlign.center),
                ),
              for (final t in ordered) cardFor(t),
            ],
          );
        },
      ),
        ),
      ],
    ),
  );
  }
}
