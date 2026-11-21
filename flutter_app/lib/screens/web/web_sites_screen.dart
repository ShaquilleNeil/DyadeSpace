import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_strings.dart';
import '../../models/site.dart';
import '../../models/stage.dart';
import '../../models/task_item.dart';
import '../../models/unit.dart';
import '../../providers/locale_provider.dart';
import '../../providers/sites_provider.dart';
import '../../providers/stages_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/units_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/client_share_dialog.dart';
import '../../widgets/site_editor.dart';
import '../../widgets/unit_card.dart';
import '../manager/unit_tasks_screen.dart';
import 'web_shared.dart';

/// Sites: each site with its roadmap line — current stage and
/// percent done — matching the mockup. Tap a site to open the
/// Board filtered to it. Add / edit / delete use the same
/// editor dialog as the phone Sites screen, including the
/// clock-in fence radius (default 100 m) — so the web can
/// manage sites fully, not just read them.
///
/// Units live under each site card, with the same add / rename
/// / delete calls as the phone site-tasks screen (UnitService)
/// and per-unit task counts; tapping a unit opens its tasks.
/// The share button on a site opens the client share link
/// dialog (read-only progress view, no app or login needed).
class WebSitesScreen extends ConsumerWidget {
  final WebNavigate onNavigate;
  const WebSitesScreen({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final sites = ref.watch(sitesProvider).valueOrNull ?? [];
    final stageIndex = ref.watch(stageIndexProvider);
    final units = ref.watch(allUnitsProvider).valueOrNull ?? [];
    final tasks = ref.watch(allTasksProvider).valueOrNull ?? [];
    final sorted = List<Site>.from(sites)
      ..sort((a, b) => a.name.compareTo(b.name));

    return ListView(
      padding: webContentPadding(MediaQuery.sizeOf(context).width),
      children: [
        WebSectionHeader(
          title: s.sites,
          // The app theme gives every FilledButton an infinite
          // minimum width — bound this one to its content (same
          // fix as the topbar button).
          trailing: FilledButton.icon(
            onPressed: () => showSiteEditor(context, ref, null),
            icon: const Icon(Icons.add, size: 18),
            label: Text(s.addSite),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (sorted.isEmpty)
          Text(s.noSites, style: TextStyle(color: tokens.textSecondary))
        else
          for (final site in sorted) ...[
            _siteCard(context, ref, s, tokens, site, stageIndex),
            const SizedBox(height: 6),
            ..._unitsSection(
                context, ref, s, tokens, site, units, tasks, stageIndex),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _siteCard(BuildContext context, WidgetRef ref, AppStrings s,
      AppColors tokens, Site site, StageIndex? stageIndex) {
    final stage = stageIndex?.currentStageForSite(site.id);
    final progress =
        stage == null ? null : stageIndex!.progressOf(stage);
    final status = stage == null ? null : stageIndex!.statusOf(stage);
    final pct = progress == null || progress.total == 0
        ? 0
        : (progress.done / progress.total * 100).round();
    return InkWell(
      onTap: () => onNavigate(ControlCenterSection.board, siteId: site.id),
      borderRadius: BorderRadius.circular(13),
      child: WebCard(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(site.name,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700)),
                  if (site.address.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(site.address,
                        style: TextStyle(
                            fontSize: 13, color: tokens.textSecondary)),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    s.siteRadiusDisplay(
                        site.effectiveRadiusMeters.round()),
                    style: TextStyle(
                        fontSize: 12, color: tokens.textTertiary),
                  ),
                  const SizedBox(height: 8),
                  if (stage == null)
                    Text(s.noRoadmap,
                        style: TextStyle(
                            fontSize: 13, color: tokens.textSecondary))
                  else ...[
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: stageStatusColor(status!, tokens),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            '${stage.name} · $pct%',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: progress!.total == 0
                            ? 0
                            : progress.done / progress.total,
                        minHeight: 6,
                        backgroundColor: tokens.surfaceRaised,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            stageStatusColor(status, tokens)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // The buttons handle their own taps, so tapping
            // one does not fire the card's Board navigation.
            IconButton(
              icon: const Icon(Icons.share_outlined, size: 20),
              tooltip: s.shareWithClient,
              onPressed: () => showClientShareDialog(context, ref, site),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: s.editSite,
              onPressed: () => showSiteEditor(context, ref, site),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              tooltip: s.delete,
              onPressed: () => deleteSite(context, ref, site),
            ),
            Icon(Icons.chevron_right, color: tokens.textTertiary),
          ],
        ),
      ),
    );
  }

  /// A site's units (apartments), in order, with per-unit task
  /// counts — the same section as the phone site-tasks screen,
  /// under the site card instead of behind a tap. The web shell
  /// is admin/manager-only, so the add / rename / delete
  /// controls always render.
  List<Widget> _unitsSection(
    BuildContext context,
    WidgetRef ref,
    AppStrings s,
    AppColors tokens,
    Site site,
    List<Unit> allUnits,
    List<TaskItem> siteTasks,
    StageIndex? stageIndex,
  ) {
    final units =
        allUnits.where((u) => u.siteId == site.id).toList();
    final widgets = <Widget>[
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 6, 2, 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                s.units,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: tokens.textSecondary),
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text(s.addUnit),
              onPressed: () => _showAddUnitDialog(context, ref, site, units),
              style: TextButton.styleFrom(
                foregroundColor: tokens.accentText,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
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
            style: TextStyle(fontSize: 13, color: tokens.textTertiary),
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
      final blocked =
          tasksOfUnit.where((t) => t.status == TaskStatus.blocked).length;
      widgets.add(
        UnitCard(
          unit: unit,
          done: done,
          total: tasksOfUnit.length,
          blockedCount: blocked,
          isManager: true,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => UnitTasksScreen(site: site, unit: unit)),
          ),
          onRename: () => _showRenameUnitDialog(context, ref, unit),
          onDelete: () => _confirmDeleteUnit(
              context, ref, unit, tasksOfUnit.length, stageIndex),
        ),
      );
    }
    return widgets;
  }

  /// Add one unit: a name only. Order is always after the last
  /// unit, so a new unit lands at the end of the list.
  Future<void> _showAddUnitDialog(BuildContext context, WidgetRef ref,
      Site site, List<Unit> units) async {
    final s = ref.read(stringsProvider);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _UnitNameDialog(
        strings: s,
        title: s.addUnit,
        actionLabel: s.addUnit,
      ),
    );
    if (name == null || !context.mounted) return;
    final maxOrder = units.isEmpty
        ? 0
        : units.map((u) => u.order).reduce((a, b) => a > b ? a : b);
    await ref.read(unitServiceProvider).createUnit(
        siteId: site.id, name: name, order: maxOrder + 1);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.unitAdded)));
    }
  }

  /// Rename a unit: the same name dialog, prefilled with the
  /// current name.
  Future<void> _showRenameUnitDialog(
      BuildContext context, WidgetRef ref, Unit unit) async {
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
    if (name == null || name == unit.name || !context.mounted) return;
    await ref
        .read(unitServiceProvider)
        .updateUnit(unit.copyWith(name: name));
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.unitRenamed)));
    }
  }

  /// Deletes a unit, after confirmation. Its tasks stay on the
  /// site as ordinary site-level tasks. A unit with a roadmap
  /// loses the roadmap too — the dialog says so, so the delete
  /// is never a surprise.
  Future<void> _confirmDeleteUnit(BuildContext context, WidgetRef ref,
      Unit unit, int taskCount, StageIndex? stageIndex) async {
    final s = ref.read(stringsProvider);
    final tokens = AppTokens.of(context);
    final stageCount = stageIndex?.stagesForUnit(unit.id).length ?? 0;
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
    if (ok != true || !context.mounted) return;
    await ref.read(unitServiceProvider).deleteUnit(unit.id);
    if (context.mounted) {
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
