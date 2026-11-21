import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_strings.dart';
import '../../models/site.dart';
import '../../models/task_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/sites_provider.dart';
import '../../providers/stages_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/units_provider.dart';
import '../../services/task_service.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/site_header.dart';
import '../../widgets/task_card.dart';
import '../../widgets/task_chain.dart';
import '../manager/run_builder_screen.dart';
import '../task_screen.dart';
import 'web_shared.dart';

enum _WebBoardFilter { all, today, overdue, blocked }

/// Board: the mockup's second view. Filter chips (Today is the
/// landing view, as the owner asked), search, site groups with
/// the same TaskCard the phone Board uses (locked + "Waiting
/// on" included). Overdue tasks pin to the top on All, like the
/// phone Board. On narrow screens the groups start collapsed.
class WebBoardScreen extends ConsumerStatefulWidget {
  final String? initialQuery;
  final String? initialSiteId;
  const WebBoardScreen({super.key, this.initialQuery, this.initialSiteId});

  @override
  ConsumerState<WebBoardScreen> createState() => _WebBoardScreenState();
}

class _WebBoardScreenState extends ConsumerState<WebBoardScreen> {
  _WebBoardFilter _filter = _WebBoardFilter.today;
  late final TextEditingController _searchController;
  final _collapsed = <String>{};
  bool _narrowDefaultApplied = false;
  String? _siteFilter;

  @override
  void initState() {
    super.initState();
    _searchController =
        TextEditingController(text: widget.initialQuery ?? '');
    _siteFilter = widget.initialSiteId;
  }

  @override
  void didUpdateWidget(WebBoardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialQuery != oldWidget.initialQuery) {
      _searchController.text = widget.initialQuery ?? '';
    }
    if (widget.initialSiteId != oldWidget.initialSiteId) {
      _siteFilter = widget.initialSiteId;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final now = DateTime.now();
    final allTasks = ref.watch(allTasksProvider).valueOrNull ?? [];
    final sitesById = ref.watch(siteByIdProvider);
    final sites = ref.watch(sitesProvider).valueOrNull ?? [];
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final units = ref.watch(allUnitsProvider).valueOrNull ?? [];
    final stageIndex = ref.watch(stageIndexProvider);
    final chainIndex = ChainIndex.from(allTasks);

    final userById = {for (final u in users) u.id: u};
    final unitById = {for (final u in units) u.id: u.name};

    // Narrow default: groups start collapsed on phones.
    final isNarrow = MediaQuery.sizeOf(context).width < kWebDrawerBreakpoint;
    if (!_narrowDefaultApplied) {
      _narrowDefaultApplied = true;
      if (isNarrow) {
        _collapsed.addAll(sites.map((s) => s.id));
      }
    }

    List<TaskItem> filtered;
    switch (_filter) {
      case _WebBoardFilter.all:
        filtered = List.of(allTasks);
      case _WebBoardFilter.today:
        filtered = TaskService.tasksForToday(allTasks, now);
      case _WebBoardFilter.overdue:
        filtered = TaskService.overdueOnly(allTasks);
      case _WebBoardFilter.blocked:
        filtered =
            allTasks.where((t) => t.status == TaskStatus.blocked).toList();
    }
    if (_siteFilter != null) {
      filtered = filtered.where((t) => t.siteId == _siteFilter).toList();
    }
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      filtered = filtered.where((t) {
        final siteName = sitesById[t.siteId]?.name ?? '';
        final assignee = t.assigneeIds
            .map((id) => userById[id]?.name ?? '')
            .join(' ');
        return t.title.toLowerCase().contains(query) ||
            siteName.toLowerCase().contains(query) ||
            assignee.toLowerCase().contains(query);
      }).toList();
    }

    // Group by site, sites in name order.
    final groups = <String, List<TaskItem>>{};
    for (final t in filtered) {
      (groups[t.siteId] ??= []).add(t);
    }
    final groupIds = groups.keys.toList()
      ..sort((a, b) => (sitesById[a]?.name ?? a)
          .compareTo(sitesById[b]?.name ?? b));
    for (final list in groups.values) {
      list.sort((a, b) {
        final da = a.dueDate;
        final db = b.dueDate;
        if (da == null && db == null) return a.title.compareTo(b.title);
        if (da == null) return 1;
        if (db == null) return -1;
        final c = da.compareTo(db);
        return c == 0 ? a.title.compareTo(b.title) : c;
      });
    }

    final overdue = TaskService.overdueOnly(allTasks);
    final showOverduePin = _filter == _WebBoardFilter.all &&
        _siteFilter == null &&
        overdue.isNotEmpty;

    Widget cardFor(TaskItem t) {
      final chainLocked = chainIndex.isLockedNow(t);
      final stage = stageIndex?.stageOf(t);
      final stageLocked = stageIndex?.isLockedByStage(t) ?? false;
      final chain = chainIndex.chainOf[t.id];
      return TaskCard(
        task: t,
        site: sitesById[t.siteId],
        unitName: t.unitId == null ? null : unitById[t.unitId],
        assignees: taskAssignees(t, userById, s),
        locked: chainLocked || stageLocked,
        waitingOn: chainLocked
            ? chainIndex.predecessor(t)?.title
            : (stageLocked ? stage?.name : null),
        // The dependency chain strip: one node per step, the
        // line turning green as steps complete, the current
        // step ringed — the same ChainStrip the phone board
        // renders for its chains.
        footer: chain == null
            ? null
            : Padding(
                padding: const EdgeInsets.only(top: 2),
                child: ChainStrip(
                  index: chainIndex,
                  chain: chain,
                  currentId: t.id,
                ),
              ),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TaskScreen(task: t)),
          );
        },
      );
    }

    return ListView(
      padding: webContentPadding(MediaQuery.sizeOf(context).width),
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  hintText: s.searchTasksHint,
                  prefixIcon: const Icon(Icons.search, size: 20),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
            ),
            if (_siteFilter != null) ...[
              const SizedBox(width: 8),
              InputChip(
                label: Text(sitesById[_siteFilter]?.name ?? ''),
                onDeleted: () => setState(() => _siteFilter = null),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(s, tokens, s.filterAll, _WebBoardFilter.all,
                _filter == _WebBoardFilter.all),
            _chip(s, tokens, s.today, _WebBoardFilter.today,
                _filter == _WebBoardFilter.today),
            _chip(s, tokens, s.overdue, _WebBoardFilter.overdue,
                _filter == _WebBoardFilter.overdue),
            _chip(s, tokens, s.blocked, _WebBoardFilter.blocked,
                _filter == _WebBoardFilter.blocked),
            // Plan a delivery run — the same entry point as the
            // phone Board's Actions sheet. The theme gives every
            // OutlinedButton an infinite minimum width, so bound
            // it to its content (same fix as the topbar button).
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => const RunBuilderScreen()),
                );
              },
              icon: const Icon(Icons.local_shipping_outlined, size: 18),
              label: Text(s.planRun),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 52),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 32),
            child: Center(
              child: Text(
                s.noTasksMatch,
                style: TextStyle(color: tokens.textSecondary),
              ),
            ),
          )
        else ...[
          if (showOverduePin) ...[
            _overdueGroup(context, s, tokens, overdue, cardFor),
            const SizedBox(height: 18),
          ],
          for (final siteId in groupIds) ...[
            _siteGroup(context, s, sitesById[siteId], groups[siteId]!,
                cardFor),
            const SizedBox(height: 18),
          ],
        ],
      ],
    );
  }

  Widget _chip(AppStrings s, AppColors tokens, String label,
      _WebBoardFilter filter, bool selected) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _filter = filter),
      selectedColor: tokens.accentMuted,
      backgroundColor: tokens.surface,
      side: BorderSide(color: tokens.border),
      labelStyle: TextStyle(
        color: selected ? tokens.accentText : tokens.textPrimary,
        fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _overdueGroup(BuildContext context, AppStrings s, AppColors tokens,
      List<TaskItem> overdue, Widget Function(TaskItem) cardFor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 18, color: tokens.danger),
            const SizedBox(width: 6),
            Text(
              s.overdue,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: tokens.danger,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '(${overdue.length})',
              style: TextStyle(color: tokens.textSecondary),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final t in overdue) ...[
          cardFor(t),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _siteGroup(BuildContext context, AppStrings s, Site? site,
      List<TaskItem> tasks, Widget Function(TaskItem) cardFor) {
    final collapsed = _collapsed.contains(site?.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SiteHeader(
          site: site,
          count: tasks.length,
          collapsed: collapsed,
          onToggleCollapse: () {
            setState(() {
              final id = site?.id;
              if (id == null) return;
              if (collapsed) {
                _collapsed.remove(id);
              } else {
                _collapsed.add(id);
              }
            });
          },
        ),
        if (!collapsed)
          for (final t in tasks) ...[
            cardFor(t),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}
