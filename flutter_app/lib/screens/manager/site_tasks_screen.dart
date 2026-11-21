import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_strings.dart';
import '../../models/site.dart';
import '../../models/task_item.dart';
import '../../models/unit.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/stages_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/units_provider.dart';
import '../../services/task_service.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/crew_row.dart';
import '../../widgets/material_request_form.dart';
import '../../widgets/roadmap_view.dart';
import '../../widgets/section_label.dart';
import '../../widgets/site_header.dart';
import '../../widgets/skeleton_card.dart';
import '../../widgets/status_indicator.dart';
import '../../widgets/task_card.dart';
import '../../widgets/task_chain.dart';
import '../../widgets/unit_card.dart';
import '../task_screen.dart';
import 'unit_tasks_screen.dart';

/// One site's tasks: the site header, then the tasks grouped by
/// status, each group headed by its status indicator with a
/// count — tap a status header to collapse / expand that group.
/// Tap a card to edit it; the + button starts a new task
/// already on this site. The Tasks | Roadmap switch at the top
/// flips to the site's roadmap: stages in order, each with its
/// completion % — a stage's tasks go live only once an admin
/// starts the stage.
class SiteTasksScreen extends ConsumerStatefulWidget {
  final Site site;
  const SiteTasksScreen({super.key, required this.site});

  @override
  ConsumerState<SiteTasksScreen> createState() => _SiteTasksScreenState();
}

class _SiteTasksScreenState extends ConsumerState<SiteTasksScreen> {
  // Status groups start collapsed: every status is in the set
  // until the user expands a group.
  final _collapsed = <TaskStatus>{...TaskStatus.values};

  // Tasks view by default; Roadmap shows the site's stages.
  bool _showRoadmap = false;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final site = widget.site;
    final s = ref.watch(stringsProvider);
    final tasksAsync = ref.watch(allTasksProvider);
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final userName = {for (final u in users) u.id: u.name};
    final userRole = {for (final u in users) u.id: u.role};
    final userById = {for (final u in users) u.id: u};
    final userPhoto = {for (final u in users) u.id: u.photoUrl};
    final myId = ref.watch(currentUserProvider).valueOrNull?.id;
    final isManager =
        ref.watch(currentUserProvider).valueOrNull?.isAdminOrManager ??
            false;
    // The site's units (apartments). Null while the stream
    // loads — the section simply hides until it lands.
    final units = ref.watch(unitsForSiteProvider(site.id)).valueOrNull ?? [];
    // Null while the stage/task streams load — tasks behave
    // exactly as they do today until it lands.
    final stageIndex = ref.watch(stageIndexProvider);
    return Scaffold(
      appBar: AppBar(title: Text(site.name)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: Text(s.newTask),
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
              builder: (_) => TaskScreen(initialSiteId: site.id)),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Column(
              children: [
                SizedBox(
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
                // Site-level materials request (no task attached):
                // anyone on the site can ask for what the site is
                // short on. Hidden on the roadmap view.
                if (!_showRoadmap) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.inventory_2_outlined, size: 18),
                      label: Text(s.requestMaterials),
                      onPressed: () async {
                        final sent = await showMaterialRequestSheet(
                          context,
                          ref,
                          siteId: site.id,
                        );
                        // The sheet is fully closed by now: the
                        // confirmation comes from here, never from
                        // inside the sheet across its own pop.
                        if (sent == true && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(s.materialRequestSent)),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: tasksAsync.when(
              loading: () => const SkeletonList(),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (all) {
                if (_showRoadmap) return RoadmapView(siteId: site.id);
                // The main list shows site-level tasks only: a
                // task that belongs to a unit lives inside that
                // unit's card (UnitTasksScreen), never here.
                // Unit progress counts still use the unfiltered
                // site list, passed to _unitsSection below.
                final siteTasks =
                    all.where((t) => t.siteId == site.id).toList();
                final mine =
                    siteTasks.where((t) => t.unitId == null).toList();
          const order = [
            TaskStatus.todo,
            TaskStatus.inProgress,
            TaskStatus.paused,
            TaskStatus.blocked,
            TaskStatus.toConfirm,
            TaskStatus.done,
          ];
          final index = ChainIndex.from(all);
          // Who's present at this site today: same rule as the
          // Board crew row — a person is here iff they have a
          // task at this site in tasksForToday with status NOT
          // done and NOT paused (done = finished, paused = not
          // working on it today). People with no qualifying
          // task appear nowhere.
          final crew = <String, int>{};
          for (final t in TaskService.tasksForToday(
              all, DateTime.now(), stageIndex)) {
            if (t.siteId != site.id) continue;
            if (t.status == TaskStatus.done ||
                t.status == TaskStatus.paused) {
              continue;
            }
            // Every assignee counts as present at this site.
            for (final id in t.assigneeIds) {
              crew.update(id, (c) => c + 1, ifAbsent: () => 1);
            }
          }
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
            // Board and My Day: never when locked, only from
            // To do / To confirm.
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
                  onPressed: () async {
                    HapticFeedback.lightImpact();
                    // One-tap Start gets a confirm, like the
                    // task screen's Start button.
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(s.confirmStartTask),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(s.cancel)),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(s.confirm)),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    try {
                      await ref
                          .read(taskServiceProvider)
                          .startTask(t);
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            // TODO(l10n): move to AppStrings.
                            content:
                                Text('Could not start the task: $e'),
                          ),
                        );
                      }
                    }
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
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 88),
            children: [
              SiteHeader(site: site, count: mine.length),
              // Who's present: directly under the header, outside
              // the collapsible status groups, so it is always
              // visible. Nothing at all when no crew today.
              if (crew.isNotEmpty)
                CrewRow(
                  crew: crew,
                  userName: userName,
                  userRole: userRole,
                  userPhoto: userPhoto,
                  indent: 18,
                ),
              // Units (apartments) of this site, above the task
              // list: one card per unit, tap to see its tasks.
              // Workers on a unit-less site see nothing new at
              // all; managers always see the section so they
              // can add the first unit.
              ..._unitsSection(
                s: s,
                units: units,
                siteTasks: siteTasks,
                isManager: isManager,
              ),
              if (mine.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(s.noTasks, textAlign: TextAlign.center),
                ),
              for (final status in order)
                if (mine.any((t) => t.status == status)) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(2, 12, 2, 2),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() {
                          if (_collapsed.contains(status)) {
                            _collapsed.remove(status);
                          } else {
                            _collapsed.add(status);
                          }
                        });
                      },
                      child: Row(children: [
                        AnimatedRotation(
                          turns: _collapsed.contains(status) ? 0.0 : 0.25,
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          child: Icon(
                            Icons.chevron_right,
                            size: 20,
                            color: Theme.of(context)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                        ),
                        StatusIndicator(status: status),
                        const SizedBox(width: 8),
                        Text(
                            '(${mine.where((t) => t.status == status).length})',
                            style: Theme.of(context).textTheme.bodySmall),
                      ]),
                    ),
                  ),
                  if (!_collapsed.contains(status))
                    for (final t in mine.where((x) => x.status == status))
                      cardFor(t),
                ],
            ],
          );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The Units section: one card per apartment of this site,
  /// each with its progress — tap a card to see that unit's
  /// tasks. Unit tasks live ONLY inside their unit card now:
  /// the main task list below shows site-level tasks (no unit)
  /// only. Workers on a unit-less site see nothing at all;
  /// managers always see the section so the first unit can be
  /// added.
  List<Widget> _unitsSection({
    required AppStrings s,
    required List<Unit> units,
    required List<TaskItem> siteTasks,
    required bool isManager,
  }) {
    if (units.isEmpty && !isManager) return [];
    final widgets = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
        child: Row(
          children: [
            Expanded(child: SectionLabel(s.units)),
            if (isManager)
              TextButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: Text(s.addUnit),
                onPressed: () => _showAddUnitDialog(units),
              ),
          ],
        ),
      ),
    ];
    if (units.isEmpty) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 0, 2, 6),
          child: Text(
            s.noUnits,
            style: TextStyle(
              fontSize: 13,
              color: AppTokens.of(context).textTertiary,
            ),
          ),
        ),
      );
      return widgets;
    }
    for (final unit in units) {
      final tasksOfUnit =
          siteTasks.where((t) => t.unitId == unit.id).toList();
      final done =
          tasksOfUnit.where((t) => t.status == TaskStatus.done).length;
      final blocked = tasksOfUnit
          .where((t) => t.status == TaskStatus.blocked)
          .length;
      widgets.add(
        UnitCard(
          unit: unit,
          done: done,
          total: tasksOfUnit.length,
          blockedCount: blocked,
          isManager: isManager,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) =>
                    UnitTasksScreen(site: widget.site, unit: unit)),
          ),
          onRename: () => _showRenameUnitDialog(unit),
          onDelete: () => _confirmDeleteUnit(unit, tasksOfUnit.length),
        ),
      );
    }
    return widgets;
  }

  /// Add one unit: a name only. Order is always after the last
  /// unit, so a new unit lands at the end of the list.
  Future<void> _showAddUnitDialog(List<Unit> units) async {
    final s = ref.read(stringsProvider);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _UnitNameDialog(
        strings: s,
        title: s.addUnit,
        actionLabel: s.addUnit,
      ),
    );
    if (name == null || !mounted) return;
    final maxOrder = units.isEmpty
        ? 0
        : units.map((u) => u.order).reduce((a, b) => a > b ? a : b);
    await ref.read(unitServiceProvider).createUnit(
        siteId: widget.site.id, name: name, order: maxOrder + 1);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.unitAdded)));
    }
  }

  /// Rename a unit: the same name dialog, prefilled with the
  /// current name.
  Future<void> _showRenameUnitDialog(Unit unit) async {
    final s = ref.read(stringsProvider);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _UnitNameDialog(
        strings: s,
        title: s.renameUnit,
        actionLabel: s.renameUnit,
        initialName: unit.name,
      ),
    );
    if (name == null || name == unit.name || !mounted) return;
    await ref
        .read(unitServiceProvider)
        .updateUnit(unit.copyWith(name: name));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.unitRenamed)));
    }
  }

  /// Deletes a unit, after confirmation. Its tasks stay on the
  /// site as ordinary site-level tasks. Admins/managers only —
  /// the delete button never renders for workers.
  Future<void> _confirmDeleteUnit(Unit unit, int taskCount) async {
    final s = ref.read(stringsProvider);
    final tokens = AppTokens.of(context);
    // A unit with a roadmap loses the roadmap too — the dialog
    // says so, so the delete is never a surprise.
    final stageCount =
        ref.read(stageIndexProvider)?.stagesForUnit(unit.id).length ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteUnit),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.deleteUnitConfirm(taskCount)),
            if (stageCount > 0) ...[
              const SizedBox(height: 8),
              Text(s.deleteUnitRoadmapNote(stageCount)),
            ],
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await ref.read(unitServiceProvider).deleteUnit(unit.id);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.unitDeleted)));
    }
  }
}

/// The add/rename-unit dialog: a name field only. It owns its
/// controller and disposes it in dispose — the parent reads the
/// returned name before the dialog is gone, never after, so the
/// old "used after being disposed" crash cannot happen here.
class _UnitNameDialog extends StatefulWidget {
  final AppStrings strings;
  final String title;
  final String actionLabel;
  final String initialName;

  const _UnitNameDialog({
    required this.strings,
    required this.title,
    required this.actionLabel,
    this.initialName = '',
  });

  @override
  State<_UnitNameDialog> createState() => _UnitNameDialogState();
}

class _UnitNameDialogState extends State<_UnitNameDialog> {
  late final TextEditingController _nameCtrl;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _nameCtrl,
        autofocus: true,
        decoration: InputDecoration(labelText: s.unitName),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () {
            final value = _nameCtrl.text.trim();
            if (value.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.unitNameNeeded)));
              return;
            }
            Navigator.pop(context, value);
          },
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
