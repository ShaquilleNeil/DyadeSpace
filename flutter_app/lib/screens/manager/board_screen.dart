import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_strings.dart';
import '../../models/app_user.dart';
import '../../models/site.dart';
import '../../models/stage.dart';
import '../../models/task_item.dart';
import '../../models/unit.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/material_requests_provider.dart';
import '../../providers/runs_provider.dart';
import '../../providers/sites_provider.dart';
import '../../providers/stages_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/units_provider.dart';
import '../../services/task_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/crew_row.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/run_progress_bar.dart';
import '../../widgets/section_label.dart';
import '../../widgets/site_header.dart';
import '../../widgets/skeleton_card.dart';
import '../../widgets/task_card.dart';
import '../../widgets/task_chain.dart';
import 'run_builder_screen.dart';
import 'runs_progress_screen.dart';
import 'material_requests_screen.dart';
import 'hours_screen.dart';
import 'site_tasks_screen.dart';
import 'sites_screen.dart';
import '../task_screen.dart';

/// The manager board: search + filter row on top, then — on All —
/// Overdue pinned on top, then one group per site. Tap a site
/// header's chevron to collapse / expand that site's tasks
/// (remembered on this phone), tap a site's name to open that
/// site's own board. Tasks assigned to me get a Start button
/// right on the card (admins and managers included, same rule as
/// My Day: never when locked, only from To do / To confirm).
/// Tap a card to edit it.
///
/// The old Today tab lives here now as the Today filter: today's
/// tasks only, grouped by site (collapsible), with dependency
/// chains rendered whole as connected stacks — the same
/// rendering the Today tab used — plus its manager shortcuts
/// (plan a run, sites, run progress) above the groups.
class BoardScreen extends ConsumerStatefulWidget {
  const BoardScreen({super.key});

  @override
  ConsumerState<BoardScreen> createState() => _BoardScreenState();
}

enum _BoardFilter { all, today, overdue, blocked }

class _BoardScreenState extends ConsumerState<BoardScreen> {
  static const _collapsedKey = 'board_collapsed_sites';
  // Null until the saved toggle state loads: while null every
  // site starts collapsed (first launch), and once loaded the
  // saved state wins (an empty saved list = all expanded).
  Set<String>? _collapsed;

  // Live search text (filters title, site name, assignee name)
  // and the active filter chip. Search combines with the filter:
  // it narrows whatever the filter shows.
  final _searchController = TextEditingController();
  _BoardFilter _filter = _BoardFilter.today;
  String _query = '';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (!mounted) return;
      setState(() {
        _collapsed = prefs.getStringList(_collapsedKey)?.toSet();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _toggleSite(String siteId, Set<String> allSiteIds) async {
    HapticFeedback.lightImpact();
    final next = Set<String>.of(_collapsed ?? allSiteIds);
    if (next.contains(siteId)) {
      next.remove(siteId);
    } else {
      next.add(siteId);
    }
    setState(() => _collapsed = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_collapsedKey, next.toList());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final tasksAsync = ref.watch(allTasksProvider);
    final siteById = ref.watch(siteByIdProvider);
    final runs = ref.watch(allRunsProvider).valueOrNull ?? [];
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final userName = {for (final u in users) u.id: u.name};
    final userRole = {for (final u in users) u.id: u.role};
    final userById = {for (final u in users) u.id: u};
    final userPhoto = {for (final u in users) u.id: u.photoUrl};
    // Unit names for the task cards: a task in a unit shows
    // "Unit 502" in its meta line.
    final Map<String, String> unitById = {
      for (final u in ref.watch(allUnitsProvider).valueOrNull ?? <Unit>[])
        u.id: u.name
    };
    final me = ref.watch(currentUserProvider).valueOrNull;
    final myId = me?.id;
    // Null while the stage/task streams load — tasks behave
    // exactly as they do today until it lands.
    final stageIndex = ref.watch(stageIndexProvider);

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: s.newTask,
        onPressed: () {
          HapticFeedback.lightImpact();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const TaskScreen()),
          );
        },
        child: const Icon(Icons.add),
      ),
      body: tasksAsync.when(
        loading: () => Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          child: SkeletonList(count: 6),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tasks) {
          final now = DateTime.now();
          final index = ChainIndex.from(tasks);
          // Search: title, site name, unit name, assignee name,
          // notes, or status — case-insensitive, live as he
          // types. An empty query matches everything.
          final query = _query.trim().toLowerCase();
          bool matchesSearch(TaskItem t) {
            if (query.isEmpty) return true;
            final siteName = siteById[t.siteId]?.name ?? '';
            final assignee = t.assigneeIds
                .map((id) => userName[id] ?? '')
                .join(' ');
            final unitName =
                t.unitId == null ? '' : (unitById[t.unitId!] ?? '');
            return t.title.toLowerCase().contains(query) ||
                siteName.toLowerCase().contains(query) ||
                assignee.toLowerCase().contains(query) ||
                t.notes.toLowerCase().contains(query) ||
                unitName.toLowerCase().contains(query) ||
                t.status.name.toLowerCase().contains(query) ||
                statusLabel(s, t.status).toLowerCase().contains(query);
          }
          // The task set this filter shows, narrowed by search.
          // Today pulls in every step of any chain that touches
          // today — exactly the old Today tab's set, computed
          // from the full list so chains stay whole.
          final List<TaskItem> visible;
          switch (_filter) {
            case _BoardFilter.all:
              visible = tasks.where(matchesSearch).toList();
              break;
            case _BoardFilter.today:
              final today =
                  TaskService.tasksForToday(tasks, now, stageIndex);
              final visibleIds = today.map((t) => t.id).toSet();
              for (final t in today) {
                final chain = index.chainOf[t.id];
                if (chain != null) {
                  visibleIds.addAll(chain.map((c) => c.id));
                }
              }
              visible = tasks
                  .where((t) =>
                      visibleIds.contains(t.id) && matchesSearch(t))
                  .toList();
              break;
            case _BoardFilter.overdue:
              visible = TaskService.overdueOnly(tasks)
                  .where(matchesSearch)
                  .toList();
              break;
            case _BoardFilter.blocked:
              visible = tasks
                  .where((t) =>
                      t.status == TaskStatus.blocked && matchesSearch(t))
                  .toList();
              break;
          }
          // Overdue pinned section (All view only): the overdue
          // tasks in the current search, so the section never
          // contradicts the search box.
          final overdue = _filter == _BoardFilter.all
              ? TaskService.overdueOnly(visible)
              : const <TaskItem>[];
          // One group per site, sorted by site name. Overdue
          // tasks still appear in their site group too; the
          // section on top is the "look here first" copy.
          final bySite = <String, List<TaskItem>>{};
          for (final t in visible) {
            bySite.putIfAbsent(t.siteId, () => []).add(t);
          }
          final siteIds = bySite.keys.toList()
            ..sort((a, b) {
              final aName = siteById[a]?.name ?? '';
              final bName = siteById[b]?.name ?? '';
              if (aName.isEmpty && bName.isEmpty) return 0;
              if (aName.isEmpty) return 1;
              if (bName.isEmpty) return -1;
              return aName.compareTo(bName);
            });

          // Collapsed-by-default: before the saved state loads,
          // every site starts collapsed. One collapsed set for
          // the whole Board, Today filter included — the old
          // Today tab's separate key ('today_collapsed_sites')
          // is retired with the tab.
          final collapsed = _collapsed ?? siteIds.toSet();
          // Today's runs at a glance: aggregate stops across
          // every run dated today.
          // Who's where today: siteId -> assigneeId -> task count.
          // A person is "at" a site today iff they have a task at
          // that site in tasksForToday with status NOT done and
          // NOT paused (tasksForToday also returns done-today and
          // paused tasks; both are excluded here: done = finished,
          // paused = not working on it today). People with no
          // qualifying task appear nowhere.
          final whosWhere = <String, Map<String, int>>{};
          for (final t in TaskService.tasksForToday(tasks, now, stageIndex)) {
            if (t.status == TaskStatus.done ||
                t.status == TaskStatus.paused) {
              continue;
            }
            // Every assignee counts as present at the site.
            for (final id in t.assigneeIds) {
              whosWhere
                  .putIfAbsent(t.siteId, () => {})
                  .update(id, (c) => c + 1, ifAbsent: () => 1);
            }
          }
          final todayRuns =
              runs.where((r) => isSameDay(r.date, now)).toList();
          final totalStops = todayRuns.fold<int>(
              0, (sum, r) => sum + r.orderedStops.length);
          final doneStops = todayRuns.fold<int>(
              0, (sum, r) => sum + r.completedCount);
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
            // My own tasks start from here — admins and managers
            // included, same rule as My Day: never when locked,
            // only from To do / To confirm.
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
                    try {
                      await ref.read(taskServiceProvider).startTask(t);
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
              site: siteById[t.siteId],
              unitName:
                  t.unitId == null ? null : unitById[t.unitId],
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

          final isAll = _filter == _BoardFilter.all;
          final isTodayFilter = _filter == _BoardFilter.today;
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
            children: [
              _searchField(tokens, s),
              const SizedBox(height: 8),
              _filterChips(tokens, s),
              if (isAll && overdue.isNotEmpty) ...[
                const SizedBox(height: 8),
                SectionLabel('${s.overdue} (${overdue.length})'),
                ...overdue.map(cardFor),
                const SizedBox(height: 24),
              ],
              // Runs at a glance: only when there is at least one
              // run today, All view only. Tap opens the run
              // progress screen in view-only mode (no edit pencil).
              if (isAll && todayRuns.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) =>
                                const RunsProgressScreen(readOnly: true)),
                      ),
                      borderRadius: BorderRadius.circular(13),
                      child: Container(
                        decoration: appCardDecoration(context),
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(s.todaysRuns,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium),
                                ),
                                Text(s.runsToday(todayRuns.length),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(s.stopsDone(doneStops, totalStops),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall),
                            const SizedBox(height: 8),
                            RunProgressBar(
                                completed: doneStops, total: totalStops),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
              // Daily actions: always visible, on every filter —
              // "Plan a run" is the daily action, and "Actions"
              // holds the rest (sites, run progress, requests,
              // hours) one tap further in.
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 8),
                child: _actionButtons(context, s),
              ),
              if (visible.isEmpty)
                Center(
                  child: EmptyState(
                    icon: tasks.isEmpty
                        ? Icons.inbox_outlined
                        : (isTodayFilter && query.isEmpty
                            ? Icons.event_available_outlined
                            : Icons.search_off_outlined),
                    title: tasks.isEmpty
                        ? s.noTasks
                        : (isTodayFilter && query.isEmpty
                            ? s.nothingToday
                            : s.noTasksMatch),
                  ),
                )
              else
                for (final siteId in siteIds) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SiteHeader(
                          site: siteById[siteId],
                          count: bySite[siteId]!.length,
                          collapsed: collapsed.contains(siteId),
                          onToggleCollapse: () =>
                              _toggleSite(siteId, siteIds.toSet()),
                          // Tapping a site name opens that site's board
                          // on every filter, including Today (the Board
                          // default) — the name is the way into the site
                          // page, the chevron only collapses the group.
                          onOpenSite: siteById[siteId] == null
                              ? null
                              : () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                        builder: (_) => SiteTasksScreen(
                                            site: siteById[siteId]!)),
                                  ),
                        ),
                        // Crew row: outside the collapsed check, so
                        // it stays visible even when the group is
                        // collapsed. Only when this site has crew
                        // today — and only on the All view, where
                        // the Board always showed it.
                        if (isAll &&
                            (whosWhere[siteId]?.isNotEmpty ?? false))
                          CrewRow(
                              crew: whosWhere[siteId]!,
                              userName: userName,
                              userRole: userRole,
                              userPhoto: userPhoto),
                        if (!collapsed.contains(siteId))
                          ...(isTodayFilter
                              ? _todaySiteWidgets(
                                  context,
                                  s,
                                  bySite[siteId]!,
                                  index,
                                  stageIndex,
                                  siteById,
                                  userById,
                                  unitById)
                              : bySite[siteId]!.map(cardFor)),
                      ],
                    ),
                  ),
                ],
            ],
          );
        },
      ),
    );
  }

  /// Live search: title, site name, unit name, assignee name,
  /// notes, or status. The clear button appears once there is
  /// text to clear.
  Widget _searchField(AppColors tokens, AppStrings s) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppTokens.inputRadius),
      borderSide: BorderSide(color: tokens.border),
    );
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: s.searchTasksHint,
        hintStyle: TextStyle(color: tokens.textTertiary),
        prefixIcon: Icon(Icons.search, color: tokens.textTertiary),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.clear, color: tokens.textTertiary),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _query = '');
                },
              ),
        filled: true,
        fillColor: tokens.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.inputRadius),
          borderSide: const BorderSide(color: AppTokens.accent),
        ),
      ),
    );
  }

  /// All / Today / Overdue / Blocked. A single horizontal
  /// scrollable row, so the labels never truncate.
  Widget _filterChips(AppColors tokens, AppStrings s) {
    String labelFor(_BoardFilter f) {
      switch (f) {
        case _BoardFilter.all:
          return s.filterAll;
        case _BoardFilter.today:
          return s.today;
        case _BoardFilter.overdue:
          return s.overdue;
        case _BoardFilter.blocked:
          return s.blocked;
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < _BoardFilter.values.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            ChoiceChip(
              label: Text(labelFor(_BoardFilter.values[i])),
              selected: _filter == _BoardFilter.values[i],
              onSelected: (_) =>
                  setState(() => _filter = _BoardFilter.values[i]),
              showCheckmark: false,
              backgroundColor: tokens.surface,
              selectedColor: tokens.accentMuted,
              side: BorderSide(
                  color: _filter == _BoardFilter.values[i]
                      ? AppTokens.accent
                      : tokens.border),
              labelStyle: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _filter == _BoardFilter.values[i]
                    ? tokens.accentText
                    : tokens.textSecondary,
              ),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
            ),
          ],
        ],
      ),
    );
  }

  /// Daily actions, one button: "Actions" opens a sheet with
  /// everything — plan a run, sites, run progress, material
  /// requests (with its open-count badge), hours. Nothing is
  /// removed, only regrouped: every action stays two taps away
  /// at most.
  Widget _actionButtons(BuildContext context, AppStrings s) {
    final style = OutlinedButton.styleFrom(
      minimumSize: const Size(0, 40),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          OutlinedButton.icon(
            style: style,
            icon: const Icon(Icons.more_horiz, size: 18),
            label: Text(s.actions),
            onPressed: () => _showBoardActionsSheet(context),
          ),
        ],
      ),
    );
  }

  /// The secondary Board actions, in a bottom sheet: plan a
  /// run, sites, run progress, material requests (badge while
  /// requests are open), hours. Tapping a row closes the sheet
  /// and opens the screen — one tap past "Actions".
  void _showBoardActionsSheet(BuildContext context) {
    final s = ref.read(stringsProvider);
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Consumer(
          builder: (ctx, ref, _) {
            final tokens = AppTokens.of(ctx);
            final openRequests =
                ref.watch(openMaterialRequestsCountProvider);
            Widget row({
              required IconData icon,
              required String label,
              Widget? trailing,
              required VoidCallback onTap,
            }) {
              return ListTile(
                leading: Icon(icon, color: tokens.textSecondary),
                title: Text(label),
                trailing: trailing,
                onTap: () {
                  HapticFeedback.lightImpact();
                  Navigator.of(sheetContext).pop();
                  onTap();
                },
              );
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(20, 16, 20, 4),
                  child: Text(
                    s.actions,
                    style: Theme.of(ctx).textTheme.titleMedium,
                  ),
                ),
                row(
                  icon: Icons.local_shipping_outlined,
                  label: s.planRun,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const RunBuilderScreen()),
                  ),
                ),
                row(
                  icon: Icons.apartment_outlined,
                  label: s.sites,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const SitesScreen()),
                  ),
                ),
                row(
                  icon: Icons.timeline_outlined,
                  label: s.runProgress,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const RunsProgressScreen()),
                  ),
                ),
                row(
                  icon: Icons.inventory_2_outlined,
                  label: s.materialRequests,
                  trailing: openRequests > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppTokens.accent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$openRequests',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        )
                      : null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) =>
                            const MaterialRequestsScreen()),
                  ),
                ),
                row(
                  icon: Icons.access_time_outlined,
                  label: s.hours,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const HoursScreen()),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  /// One site's slice of the Today filter, ported from the old
  /// Today tab: chains first (each rendered whole as a tree —
  /// see [_chainBranchWidgets] — then standalone tasks as plain
  /// cards. A chain renders once, in the group of its first
  /// step's site: steps from other sites render there too,
  /// with their site named on the card, instead of each site
  /// showing only its own fragment of the chain.
  List<Widget> _todaySiteWidgets(
    BuildContext context,
    AppStrings s,
    List<TaskItem> tasks,
    ChainIndex index,
    StageIndex? stageIndex,
    Map<String, Site> siteById,
    Map<String, AppUser> userById,
    Map<String, String> unitById,
  ) {
    final widgets = <Widget>[];
    final renderedChains = <String>{};
    for (final t in tasks) {
      final chain = index.chainOf[t.id];
      if (chain == null) continue;
      // Not this group's chain to render: its first step lives
      // at another site, and the whole chain renders there.
      if (chain.first.siteId != t.siteId) continue;
      final key = chain.first.id;
      if (!renderedChains.add(key)) continue;
      widgets.addAll(_chainBranchWidgets(context, s, chain, index,
          stageIndex, siteById, userById, unitById));
    }
    for (final t in tasks.where((t) => !index.isInChain(t))) {
      widgets.add(_todayCard(context, s, t, index, stageIndex, siteById,
          userById, unitById));
    }
    return widgets;
  }

  /// Renders one chain as a tree, not a flat sequence. A step
  /// with one child continues the same rail; a step with
  /// several children renders each child's sub-chain as its own
  /// stack, indented under the parent, so a fork reads as a
  /// fork and never as a sequence it is not. Steps carry their
  /// own site on the card (see [_todayCard]), which is what
  /// gives a cross-site chain its site context.
  List<Widget> _chainBranchWidgets(
    BuildContext context,
    AppStrings s,
    List<TaskItem> chain,
    ChainIndex index,
    StageIndex? stageIndex,
    Map<String, Site> siteById,
    Map<String, AppUser> userById,
    Map<String, String> unitById,
  ) {
    final byId = {for (final c in chain) c.id: c};
    final children = <String, List<TaskItem>>{};
    for (final c in chain) {
      final dep = c.dependsOnTaskId;
      if (dep != null && byId.containsKey(dep)) {
        children.putIfAbsent(dep, () => []).add(c);
      }
    }
    // Children in the index's DFS order, so a branch lists its
    // arms in the same order the flat chain used to.
    final order = {for (var i = 0; i < chain.length; i++) chain[i].id: i};
    for (final list in children.values) {
      list.sort((a, b) => order[a.id]!.compareTo(order[b.id]!));
    }
    final roots = chain
        .where((c) =>
            c.dependsOnTaskId == null ||
            !byId.containsKey(c.dependsOnTaskId))
        .toList();

    List<Widget> renderStep(TaskItem step,
        {required bool isFirst, required bool isLast, TaskItem? previous}) {
      final out = <Widget>[
        ChainStepRow(
          task: step,
          previous: previous,
          isFirst: isFirst,
          isLast: isLast,
          dimmed: index.isLockedNow(step) ||
              (stageIndex?.isLockedByStage(step) ?? false),
          child: _todayCard(context, s, step, index, stageIndex, siteById,
              userById, unitById),
        ),
      ];
      final kids = children[step.id] ?? const <TaskItem>[];
      bool leaf(TaskItem c) => (children[c.id]?.isEmpty ?? true);
      if (kids.length == 1) {
        out.addAll(renderStep(kids.first,
            isFirst: false, isLast: leaf(kids.first), previous: step));
      } else if (kids.length > 1) {
        for (final kid in kids) {
          // Each arm is its own stack under the parent: a fresh
          // rail and a small indent, so the fork is visible.
          out.add(Padding(
            padding: const EdgeInsets.only(left: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: renderStep(kid,
                  isFirst: true, isLast: leaf(kid), previous: step),
            ),
          ));
        }
      }
      return out;
    }

    final widgets = <Widget>[];
    for (var i = 0; i < roots.length; i++) {
      final root = roots[i];
      widgets.addAll(renderStep(root,
          isFirst: i == 0,
          isLast: (children[root.id]?.isEmpty ?? true),
          previous: null));
    }
    return widgets;
  }

  /// A Today-filter card, as the old Today tab rendered it: no
  /// chain strip and no Start button — the chain rail above
  /// carries the order, and starting happens from the Board or
  /// My Day. Locked by the chain OR by the stage, same as the
  /// Board.
  Widget _todayCard(
    BuildContext context,
    AppStrings s,
    TaskItem t,
    ChainIndex index,
    StageIndex? stageIndex,
    Map<String, Site> siteById,
    Map<String, AppUser> userById,
    Map<String, String> unitById,
  ) {
    final chainLocked = index.isLockedNow(t);
    final stage = stageIndex?.stageOf(t);
    final stageLocked = stageIndex?.isLockedByStage(t) ?? false;
    final locked = chainLocked || stageLocked;
    final predecessor = index.predecessor(t);
    return TaskCard(
      task: t,
      site: siteById[t.siteId],
      unitName: t.unitId == null ? null : unitById[t.unitId],
      assignees: taskAssignees(t, userById, s),
      locked: locked,
      waitingOn: chainLocked
          ? predecessor?.title
          : (stageLocked ? stage?.name : null),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => TaskScreen(task: t)),
      ),
    );
  }
}
