import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_strings.dart';
import '../models/app_user.dart';
import '../models/roadmap_template.dart';
import '../models/stage.dart';
import '../models/task_item.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/sites_provider.dart';
import '../providers/stages_provider.dart';
import '../providers/tasks_provider.dart';
import '../theme/app_tokens.dart';
import 'empty_state.dart';
import 'skeleton_card.dart';
import 'stage_card.dart';
import 'task_chain.dart';
import '../screens/task_screen.dart';

/// One roadmap: its stages in order on a vertical timeline
/// (rail + node, same geometry as the task chain rows), each
/// stage a card with its % at the top. A roadmap with no stages
/// shows the Create roadmap empty state instead (admin/manager
/// only — workers see nothing to tap).
///
/// [siteId] is the site the roadmap belongs to. Pass [unitId]
/// for a unit's roadmap — the stages shown, created and
/// deleted are that unit's only; without it, the site's
/// roadmap. A unit roadmap starts blank (add stages one by
/// one); only the site roadmap offers the house template.
class RoadmapView extends ConsumerStatefulWidget {
  final String siteId;
  final String? unitId;
  const RoadmapView({super.key, required this.siteId, this.unitId});

  @override
  ConsumerState<RoadmapView> createState() => _RoadmapViewState();
}

class _RoadmapViewState extends ConsumerState<RoadmapView> {
  final _expanded = <String>{};

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final stageIndex = ref.watch(stageIndexProvider);
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final userName = {for (final u in users) u.id: u.name};
    final isManager =
        ref.watch(currentUserProvider).valueOrNull?.isAdminOrManager ??
            false;
    if (stageIndex == null || stageIndex.isLoading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(14, 6, 14, 88),
        child: SkeletonList(count: 4),
      );
    }
    // The stages of this roadmap's scope only: the unit's
    // stages when unitId is set, the site's stages otherwise.
    // Unit stages never leak into the site roadmap or the
    // other way round.
    final stages = widget.unitId != null
        ? stageIndex.stagesForUnit(widget.unitId!)
        : stageIndex.stagesForSite(widget.siteId);
    if (stages.isEmpty) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 88),
        children: [
          EmptyState(
            icon: Icons.route_outlined,
            title: widget.unitId != null
                ? s.noUnitRoadmapYet
                : s.noRoadmapYet,
            caption: s.roadmapHint,
            actionLabel: isManager ? s.createRoadmap : null,
            onAction: isManager
                ? () {
                    HapticFeedback.lightImpact();
                    // A unit roadmap starts blank: straight to
                    // Add stage, no template choice. The site
                    // roadmap keeps the template dialog.
                    if (widget.unitId != null) {
                      _showAddStageDialog(context, s, const []);
                    } else {
                      _showCreateDialog(context, s);
                    }
                  }
                : null,
          ),
        ],
      );
    }
    final service = ref.read(stageServiceProvider);
    // The chain index is built from every task (not just this
    // site's), so a step waiting on a task in another stage
    // still resolves its predecessor for the rail and the
    // "Waiting on" chip.
    final allTasks = ref.watch(allTasksProvider).valueOrNull ?? [];
    final chainIndex = ChainIndex.from(allTasks);
    final roadmapTaskCount = stages.fold<int>(
        0, (sum, st) => sum + stageIndex.tasksOf(st).length);
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 88),
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${s.roadmap} · ${s.stagesCount(stages.length)}',
                  style:  TextStyle(
                      fontSize: 12, color: tokens.textTertiary),
                ),
              ),
              if (isManager) ...[
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (value) {
                    HapticFeedback.lightImpact();
                    if (value == 'save') {
                      _showSaveTemplateDialog(context, s);
                    } else if (value == 'copy') {
                      _showCopyDialog(context, s);
                    }
                  },
                  itemBuilder: (ctx) => [
                    PopupMenuItem(
                      value: 'save',
                      child: Text(s.saveAsTemplate),
                    ),
                    PopupMenuItem(
                      value: 'copy',
                      child: Text(s.copyRoadmap),
                    ),
                  ],
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.danger,
                    minimumSize: const Size(0, 32),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  onPressed: () {
                    HapticFeedback.lightImpact();
                    _confirmDeleteRoadmap(
                        context, s, stages, roadmapTaskCount);
                  },
                  child: Text(s.deleteRoadmap),
                ),
              ],
            ],
          ),
        ),
        for (var i = 0; i < stages.length; i++) ...[
          Builder(builder: (context) {
            final stage = stages[i];
            final status = stageIndex.statusOf(stage);
            return _StageRow(
              status: status,
              isFirst: i == 0,
              isLast: i == stages.length - 1,
              previousCompleted: i > 0 &&
                  stageIndex.statusOf(stages[i - 1]) ==
                      StageStatus.completed,
              child: StageCard(
                stage: stage,
                stageNumber: i + 1,
                index: stageIndex,
                chain: chainIndex,
                userName: userName,
                expanded: _expanded.contains(stage.id),
                isManager: isManager,
                isFirst: i == 0,
                isLast: i == stages.length - 1,
                onToggleExpand: () => setState(() {
                  if (_expanded.contains(stage.id)) {
                    _expanded.remove(stage.id);
                  } else {
                    _expanded.add(stage.id);
                  }
                }),
                onStart: () async {
                  await service.startStage(stage.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.stageStarted)));
                  }
                },
                onSkip: () async {
                  await service.skipStage(stage.id);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.stageSkipped)));
                  }
                },
                onUnskip: () => service.unskipStage(stage.id),
                onMoveUp: () => service.moveStage(stages, stage, up: true),
                onMoveDown: () =>
                    service.moveStage(stages, stage, up: false),
                onDelete: () => _confirmDeleteStage(context, s, stage),
                onTaskTap: (task) => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => TaskScreen(task: task)),
                ),
                onDeleteTask: (task) => _confirmDeleteTask(context, s, task),
              ),
            );
          }),
        ],
        if (isManager) ...[
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
              ),
              icon: const Icon(Icons.add),
              label: Text(s.addStage),
              onPressed: () {
                HapticFeedback.lightImpact();
                _showAddStageDialog(context, s, stages);
              },
            ),
          ),
        ],
      ],
    );
  }

  /// Deletes one stage, after confirmation. Its tasks keep
  /// their stageId cleared by the service, so they stay on the
  /// site as ordinary tasks. Admins/managers only — the button
  /// never renders for workers.
  Future<void> _confirmDeleteStage(
      BuildContext context, AppStrings s, Stage stage) async {
    final tokens = AppTokens.of(context);
    final taskCount =
        ref.read(stageIndexProvider)?.tasksOf(stage).length ?? 0;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteStage),
        content: Text(s.deleteStageConfirm(taskCount)),
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
    await ref.read(stageServiceProvider).deleteStage(stage.id);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.stageDeleted)));
    }
  }

  /// Deletes one task from inside the roadmap, after
  /// confirmation. This is the only place a task that belongs
  /// to a roadmap stage can be deleted — the editor hides its
  /// Delete action for staged tasks. Admins/managers only; the
  /// trash icon never renders for workers. The stage's % and
  /// counts recompute from the surviving tasks.
  Future<void> _confirmDeleteTask(
      BuildContext context, AppStrings s, TaskItem task) async {
    final tokens = AppTokens.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteTask),
        content: Text(s.deleteTaskConfirm),
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
    await ref.read(taskServiceProvider).deleteTask(task.id);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.taskDeleted)));
    }
  }

  /// Deletes the whole roadmap, after confirmation. Every
  /// stage goes; their tasks stay on the site without a stage.
  /// Admins/managers only — the button never renders for
  /// workers. Afterwards the site shows the Create roadmap
  /// empty state again.
  Future<void> _confirmDeleteRoadmap(BuildContext context, AppStrings s,
      List<Stage> stages, int taskCount) async {
    final tokens = AppTokens.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteRoadmap),
        content: Text(s.deleteRoadmapConfirm(stages.length, taskCount)),
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
    await ref
        .read(stageServiceProvider)
        .deleteRoadmap(widget.siteId, unitId: widget.unitId);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.roadmapDeleted)));
    }
  }

  /// Saves this roadmap as a reusable template: a name prompt
  /// (prefilled with the site's name), then the stages and
  /// their task definitions are stored. Admins/managers only —
  /// the menu never renders for workers.
  Future<void> _showSaveTemplateDialog(
      BuildContext context, AppStrings s) async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    // Captured before the await: the parameter context must not
    // be used across the async gap.
    final messenger = ScaffoldMessenger.of(context);
    String? siteName;
    for (final site in ref.read(sitesProvider).valueOrNull ?? []) {
      if (site.id == widget.siteId) siteName = site.name;
    }
    final nameCtrl = TextEditingController(text: siteName ?? '');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.saveAsTemplate),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: InputDecoration(labelText: s.templateName),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            onPressed: () {
              final value = nameCtrl.text.trim();
              if (value.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(s.templateNameNeeded)));
                return;
              }
              Navigator.pop(ctx, value);
            },
            child: Text(s.save),
          ),
        ],
      ),
    );
    nameCtrl.dispose();
    if (name == null || !mounted) return;
    final templateId =
        await ref.read(stageServiceProvider).saveRoadmapAsTemplate(
            siteId: widget.siteId, name: name, createdBy: me.id);
    if (mounted) {
      messenger.showSnackBar(SnackBar(
          content: Text(templateId.isEmpty
              // TODO(l10n): move to AppStrings.
              ? 'This roadmap is empty — there is nothing to save as a template.'
              : s.templateSaved)));
    }
  }

  /// Copies this roadmap onto another site: a site picker
  /// (every other site), then the stages and their tasks copy
  /// over fresh — To do and unassigned. Blocked with a message
  /// when the target already has a roadmap. Admins/managers
  /// only — the menu never renders for workers.
  Future<void> _showCopyDialog(BuildContext context, AppStrings s) async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    // Captured before the await: the parameter context must not
    // be used across the async gap.
    final messenger = ScaffoldMessenger.of(context);
    // The site list must have loaded: with no sites in hand the
    // dialog used to return silently, and a manager tapping
    // Copy on a slow connection got nothing at all.
    final sitesAsync = ref.read(sitesProvider);
    if (sitesAsync.isLoading) {
      // TODO(l10n): move to AppStrings.
      messenger.showSnackBar(const SnackBar(
          content: Text('Sites are still loading — try again in a moment.')));
      return;
    }
    if (sitesAsync.hasError) {
      messenger.showSnackBar(SnackBar(
          // TODO(l10n): move to AppStrings.
          content: Text(
              'Could not load the sites: ${sitesAsync.error}')));
      return;
    }
    final sites = (sitesAsync.valueOrNull ?? [])
        .where((site) => site.id != widget.siteId)
        .toList();
    if (sites.isEmpty) {
      // TODO(l10n): move to AppStrings.
      messenger.showSnackBar(const SnackBar(
          content:
              Text('There is no other site to copy this roadmap to.')));
      return;
    }
    String? selected = sites.length == 1 ? sites.first.id : null;
    final targetId = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(s.copyRoadmapTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.copyRoadmapHint),
                const SizedBox(height: 8),
                RadioGroup<String>(
                  groupValue: selected,
                  onChanged: (v) => setState(() => selected = v),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final site in sites)
                        RadioListTile<String>(
                          title: Text(site.name),
                          value: site.id,
                          contentPadding: EdgeInsets.zero,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s.cancel),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(minimumSize: const Size(0, 44)),
              onPressed: selected == null
                  ? null
                  : () => Navigator.pop(ctx, selected),
              child: Text(s.copy),
            ),
          ],
        ),
      ),
    );
    if (targetId == null || !mounted) return;
    final ok = await ref.read(stageServiceProvider).copyRoadmap(
        fromSiteId: widget.siteId, toSiteId: targetId, createdBy: me.id);
    if (mounted) {
      messenger.showSnackBar(SnackBar(
          content: Text(ok ? s.roadmapCopied : s.copyTargetHasRoadmap)));
    }
  }

  /// Create roadmap: blank, the house template (the 7 stages),
  /// or one of the saved templates by name. Site roadmaps only
  /// — unit roadmaps start blank and never reach this dialog
  /// (see the empty state above).
  Future<void> _showCreateDialog(BuildContext context, AppStrings s) async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    // Captured before the await: the parameter context must not
    // be used across the async gap.
    final messenger = ScaffoldMessenger.of(context);
    final choice = await showDialog<_CreateRoadmapChoice>(
      context: context,
      builder: (ctx) => _CreateRoadmapDialog(strings: s),
    );
    if (choice == null || !mounted) return;
    if (choice.kind == _CreateRoadmapKind.blank) {
      // The State's own context, guarded by its mounted check.
      _showAddStageDialog(this.context, s, const []);
    } else if (choice.kind == _CreateRoadmapKind.house) {
      final ok = await ref
          .read(stageServiceProvider)
          .createRoadmapFromTemplate(widget.siteId);
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            content: Text(ok ? s.roadmapCreated : s.copyTargetHasRoadmap)));
      }
    } else if (choice.template != null) {
      // The guard can still block the write (a roadmap landed
      // after the dialog opened): check the return instead of
      // always reporting success, like _showCopyDialog does.
      final ok = await ref
          .read(stageServiceProvider)
          .createRoadmapFromRoadmapTemplate(
              siteId: widget.siteId,
              template: choice.template!,
              createdBy: me.id);
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            content: Text(ok ? s.roadmapCreated : s.copyTargetHasRoadmap)));
      }
    }
  }

  /// Add one stage: a name, plus the tasks it should already
  /// contain. Tasks are title + assignee only — the full editor
  /// stays the place for dates, photos and the rest. Rows with
  /// an empty title are ignored; a stage may still be saved
  /// with no tasks at all. Order is always after the last
  /// stage, so a new stage lands at the end of the roadmap.
  Future<void> _showAddStageDialog(
      BuildContext context, AppStrings s, List<Stage> stages) async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    final users = ref.read(allUsersProvider).valueOrNull ?? [];
    final result = await showDialog<_AddStageResult>(
      context: context,
      builder: (ctx) => _AddStageDialog(strings: s, users: users),
    );
    if (result == null || !mounted) return;
    final maxOrder = stages.isEmpty
        ? 0
        : stages.map((st) => st.order).reduce((a, b) => a > b ? a : b);
    // The stage first, then its tasks — the tasks need the
    // new stage's id. In a unit roadmap the stage and its
    // tasks both carry the unitId, so the tasks show up in
    // the unit's task list as well as in the stage.
    final stageId = await ref.read(stageServiceProvider).createStage(
        siteId: widget.siteId,
        unitId: widget.unitId,
        name: result.name,
        order: maxOrder + 1);
    final taskService = ref.read(taskServiceProvider);
    for (final draft in result.tasks) {
      if (draft.title.isEmpty) continue;
      await taskService.createTask(TaskItem(
        id: '',
        title: draft.title,
        siteId: widget.siteId,
        unitId: widget.unitId,
        assigneeIds: draft.assigneeId == null ? const [] : [draft.assigneeId!],
        createdBy: me.id,
        status: TaskStatus.todo,
        stageId: stageId,
      ));
    }
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.stageAdded)));
    }
  }
}

/// The "add stage" dialog: a stage name plus its first tasks
/// (title + assignee each). It owns the name controller and
/// every task row's title controller and disposes them all in
/// dispose — it reads the titles into plain drafts before
/// popping, so the parent never touches a controller after the
/// dialog is gone (the old crash: the parent read
/// row.title.text after the pop resolved).
class _AddStageDialog extends StatefulWidget {
  final AppStrings strings;
  final List<AppUser> users;

  const _AddStageDialog({required this.strings, required this.users});

  @override
  State<_AddStageDialog> createState() => _AddStageDialogState();
}

class _AddStageDialogState extends State<_AddStageDialog> {
  final _nameCtrl = TextEditingController();
  final _rows = <_NewStageTaskRow>[_NewStageTaskRow()];

  @override
  void dispose() {
    _nameCtrl.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      title: Text(s.addStage),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameCtrl,
              autofocus: true,
              decoration: InputDecoration(labelText: s.stageName),
            ),
            const SizedBox(height: 16),
            Text(
              s.tasks,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: AppTokens.of(context).textTertiary,
              ),
            ),
            const SizedBox(height: 8),
            for (var i = 0; i < _rows.length; i++)
              _newTaskRow(
                context,
                s,
                widget.users,
                _rows[i],
                onRemove: _rows.length > 1
                    ? () => setState(() => _rows.removeAt(i))
                    : null,
                onChanged: () => setState(() {}),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(s.addTask),
                onPressed: () =>
                    setState(() => _rows.add(_NewStageTaskRow())),
              ),
            ),
          ],
        ),
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
                  SnackBar(content: Text(s.stageNameNeeded)));
              return;
            }
            // Titles are read into plain drafts BEFORE popping:
            // the parent must never touch a row controller after
            // this dialog (and its controllers) is disposed.
            Navigator.pop(
                context,
                _AddStageResult(name: value, tasks: [
                  for (final row in _rows)
                    _StageTaskDraft(
                      title: row.title.text.trim(),
                      assigneeId: row.assigneeId,
                    ),
                ]));
          },
          child: Text(s.addStage),
        ),
      ],
    );
  }

  Widget _newTaskRow(
    BuildContext context,
    AppStrings s,
    List<AppUser> users,
    _NewStageTaskRow row, {
    required VoidCallback? onRemove,
    required VoidCallback onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              controller: row.title,
              decoration: InputDecoration(
                hintText: s.taskTitle,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 128,
            child: DropdownButtonFormField<String?>(
              // A removed user must not leave a stale value
              // behind: it would red-screen the dropdown.
              initialValue: row.assigneeId != null &&
                      users.any((u) => u.id == row.assigneeId)
                  ? row.assigneeId
                  : null,
              isExpanded: true,
              hint: Text(s.unassigned),
              decoration: const InputDecoration(
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Text(s.unassigned,
                      overflow: TextOverflow.ellipsis),
                ),
                for (final u in users)
                  DropdownMenuItem<String?>(
                    value: u.id,
                    child:
                        Text(u.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) {
                row.assigneeId = v;
                onChanged();
              },
            ),
          ),
          if (onRemove != null)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}

/// One roadmap step: the connecting rail + node on the left, the
/// stage card on the right — the same rail geometry as the task
/// chain rows. The segment above the node turns green once the
/// previous stage is Done; the segment below turns green once
/// this stage is Done.
class _StageRow extends StatelessWidget {
  final StageStatus status;
  final bool isFirst;
  final bool isLast;
  final bool previousCompleted;
  final Widget child;

  const _StageRow({
    required this.status,
    required this.isFirst,
    required this.isLast,
    required this.previousCompleted,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final border = tokens.border;
    final green = tokens.statusDone;
    final topColor = previousCompleted ? green : border;
    final bottomColor =
        status == StageStatus.completed ? green : border;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 26,
            child: Stack(
              children: [
                if (!isFirst)
                  Positioned(
                    left: 12,
                    top: 0,
                    height: 25,
                    child: Container(width: 2, color: topColor),
                  ),
                if (!isLast)
                  Positioned(
                    left: 12,
                    top: 25,
                    bottom: 0,
                    child: Container(width: 2, color: bottomColor),
                  ),
                Positioned(
                  left: 1,
                  top: 13,
                  child: _StageNode(status: status),
                ),
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _StageNode extends StatelessWidget {
  final StageStatus status;
  const _StageNode({required this.status});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final Widget icon;
    final Color bg;
    BoxBorder? border;
    if (status == StageStatus.completed) {
      bg = tokens.statusDone;
      icon = const Icon(Icons.check, size: 13, color: Colors.white);
    } else if (status == StageStatus.locked) {
      bg = tokens.surface;
      border = Border.all(color: tokens.border);
      icon = Icon(Icons.lock_outline,
          size: 12, color: tokens.textTertiary);
    } else if (status == StageStatus.skipped) {
      bg = tokens.surface;
      border = Border.all(color: tokens.border);
      icon = Icon(Icons.skip_next,
          size: 13, color: tokens.textTertiary);
    } else if (status == StageStatus.inProgress) {
      bg = tokens.statusInProgress;
      icon = const Icon(Icons.circle, size: 8, color: Colors.white);
    } else {
      // Ready: blue, waiting for an admin to start it.
      bg = AppTokens.accent;
      icon = const Icon(Icons.circle, size: 8, color: Colors.white);
    }
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: border,
      ),
      child: Center(child: icon),
    );
  }
}

/// One inline task row while creating a stage: just a title
/// and an assignee. The full editor adds the rest later.
class _NewStageTaskRow {
  final TextEditingController title = TextEditingController();
  String? assigneeId;

  void dispose() => title.dispose();
}

/// What the Add-stage dialog returns: the stage name plus the
/// task drafts to create inside it (empty titles are ignored).
class _AddStageResult {
  final String name;
  final List<_StageTaskDraft> tasks;

  const _AddStageResult({required this.name, required this.tasks});
}

/// One task to create inside a new stage: plain data, read out
/// of the dialog's rows before it pops.
class _StageTaskDraft {
  final String title;
  final String? assigneeId;

  const _StageTaskDraft({required this.title, this.assigneeId});
}

enum _CreateRoadmapKind { blank, house, saved }

/// What the create-roadmap dialog returns: blank, the house
/// template, or one of the saved templates.
class _CreateRoadmapChoice {
  final _CreateRoadmapKind kind;
  final RoadmapTemplate? template;

  const _CreateRoadmapChoice(this.kind, [this.template]);
}

/// The create-roadmap dialog: blank, the house template, or a
/// saved template by name. Saved templates carry a delete
/// button (admin/manager only reach this dialog, and the rules
/// allow admin/manager or the template's creator); deleting
/// keeps the dialog open and the list refreshes from the
/// templates stream.
class _CreateRoadmapDialog extends ConsumerWidget {
  final AppStrings strings;

  const _CreateRoadmapDialog({required this.strings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = strings;
    final tokens = AppTokens.of(context);
    final templates = ref.watch(roadmapTemplatesProvider).valueOrNull ?? [];
    return AlertDialog(
      title: Text(s.createRoadmap),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.roadmapHint),
            const SizedBox(height: 12),
            Text(
              s.roadmapTemplateHint,
              style: TextStyle(fontSize: 12, color: tokens.textTertiary),
            ),
            const SizedBox(height: 16),
            Text(
              s.savedTemplates,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: tokens.textTertiary,
              ),
            ),
            const SizedBox(height: 4),
            if (templates.isEmpty)
              Text(
                s.noTemplatesYet,
                style:
                    TextStyle(fontSize: 13, color: tokens.textSecondary),
              )
            else
              for (final template in templates)
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.zero,
                        ),
                        onPressed: () => Navigator.pop(
                            context,
                            _CreateRoadmapChoice(
                                _CreateRoadmapKind.saved, template)),
                        child: Text(
                          template.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: s.deleteTemplate,
                      onPressed: () =>
                          _confirmDeleteTemplate(context, ref, s, template),
                    ),
                  ],
                ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context,
              const _CreateRoadmapChoice(_CreateRoadmapKind.blank)),
          child: Text(s.blankRoadmap),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          onPressed: () => Navigator.pop(context,
              const _CreateRoadmapChoice(_CreateRoadmapKind.house)),
          child: Text(s.houseTemplate),
        ),
      ],
    );
  }

  Future<void> _confirmDeleteTemplate(BuildContext context, WidgetRef ref,
      AppStrings s, RoadmapTemplate template) async {
    final tokens = AppTokens.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteTemplate),
        content: Text(s.deleteTemplateConfirm(template.name)),
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
    if (ok != true) return;
    await ref.read(stageServiceProvider).deleteTemplate(template.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.templateDeleted)));
    }
  }
}
