import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_strings.dart';
import '../../models/app_user.dart';
import '../../models/delivery_run.dart';
import '../../models/run_stop.dart';
import '../../models/task_item.dart';
import '../../models/time_entry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/runs_provider.dart';
import '../../providers/sites_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../providers/time_entries_provider.dart';
import '../../services/task_service.dart';
import '../../theme/app_tokens.dart';
import '../../utils/week_hours.dart';
import '../../widgets/member_tile.dart';
import '../../widgets/run_progress_bar.dart';
import '../clock_location_screen.dart';
import '../manager/run_builder_screen.dart';
import '../task_screen.dart';
import '../worker_profile_screen.dart';
import 'web_run_screen.dart';
import 'web_shared.dart';

/// Overview: the mockup's first view. Four stat cards, the
/// who's-on-site table, Drew's run, and the needs-attention
/// list. On narrow screens the run + attention sections stack
/// instead of sitting side by side.
class WebOverviewScreen extends ConsumerWidget {
  final WebNavigate onNavigate;
  const WebOverviewScreen({super.key, required this.onNavigate});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    // Toronto wall-clock "now": the week, the day, and the
    // hours below all follow the server's timezone, never the
    // browser's.
    final now = torontoNow();
    final allTasks = ref.watch(allTasksProvider).valueOrNull ?? [];
    final entries = ref.watch(allTimeEntriesProvider).valueOrNull ?? [];
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final runs = ref.watch(allRunsProvider).valueOrNull ?? [];

    final todayTasks = TaskService.tasksForToday(allTasks, now);
    final overdue = TaskService.overdueOnly(allTasks);
    final openByUser = <String, TimeEntry>{};
    for (final e in entries) {
      if (e.isOpen) openByUser[e.userId] = e;
    }
    final flaggedOpen =
        entries.where((e) => e.isOpen && e.flagged).toList();
    final blocked = allTasks.where((t) => t.status == TaskStatus.blocked).toList()
      ..sort((a, b) => a.title.compareTo(b.title));

    // Hours this week (Mon–Sun, Toronto): each entry counts
    // only the hours falling in this week — a shift crossing
    // midnight splits — and an open entry counts its live
    // time so far, the same total the Hours view shows, so the
    // two views never disagree.
    final weekStart = weekStartFor(now);
    final weekEnd = weekEndFor(weekStart);
    var weekHours = 0.0;
    final weekWorkers = <String>{};
    for (final e in entries) {
      final h = entryHoursInWeek(e, weekStart);
      if (h <= 0) continue;
      weekHours += h;
      weekWorkers.add(e.userId);
    }

    final todaysRuns = runs.where((r) => isSameDay(r.date, now)).toList();
    final deliveryRuns = todaysRuns
        .where((r) => users
            .any((u) => u.id == r.driverId && u.role == UserRole.delivery))
        .toList();

    final sitesById = ref.watch(siteByIdProvider);
    String siteName(String id) => sitesById[id]?.name ?? '';

    final sortedUsers = List<AppUser>.from(users)
      ..sort((a, b) {
        final aOpen = openByUser.containsKey(a.id) ? 0 : 1;
        final bOpen = openByUser.containsKey(b.id) ? 0 : 1;
        if (aOpen != bOpen) return aOpen.compareTo(bOpen);
        return a.name.compareTo(b.name);
      });

    return ListView(
      padding: webContentPadding(MediaQuery.sizeOf(context).width),
      children: [
        WebStatGrid(cards: [
          WebStatCard(
            label: s.tasksToday,
            value: '${todayTasks.length}',
            sub:
                '${todayTasks.where((t) => t.status == TaskStatus.done).length} ${s.done} · ${todayTasks.where((t) => t.status == TaskStatus.inProgress).length} ${s.inProgress}',
          ),
          WebStatCard(
            label: s.overdue,
            value: '${overdue.length}',
            valueColor: overdue.isEmpty ? null : tokens.danger,
            sub: '${s.blocked}: ${blocked.length}',
          ),
          WebStatCard(
            label: s.clockedInNow,
            value: '${openByUser.length}',
            sub: '${s.hoursFlagged}: ${flaggedOpen.length}',
          ),
          WebStatCard(
            label: s.hoursThisWeek,
            value: webHours(weekHours),
            sub: s.hoursWeekLabel(
              DateFormat('MMM d').format(weekStart),
              DateFormat('MMM d').format(weekEnd),
            ),
          ),
        ]),
        const SizedBox(height: 22),
        WebSectionHeader(title: s.whosOnSite),
        const SizedBox(height: 10),
        WebCard(
          child: WebResponsiveTable(
            headers: [s.crew, s.site, s.clockIn, s.status],
            rows: sortedUsers.map((u) {
              final entry = openByUser[u.id];
              final run = u.role == UserRole.delivery
                  ? deliveryRuns
                      .where((r) => r.driverId == u.id)
                      .firstOrNull
                  : null;
              final onRun = run != null;
              return [
                Row(
                  children: [
                    RoleAvatar(
                        name: u.name,
                        role: u.role,
                        size: 32,
                        photoUrl: u.photoUrl),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        u.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(
                  onRun
                      ? _nextStopTitle(run)
                      : entry?.siteName ?? '—',
                  overflow: TextOverflow.ellipsis,
                ),
                Text(entry == null ? '—' : webTime(entry.clockInAt)),
                onRun
                    ? WebPill(label: s.onRun, color: tokens.accent)
                    : entry == null
                        ? Text(s.notClockedIn,
                            style: TextStyle(color: tokens.textSecondary))
                        : entry.flagged
                            ? WebPill(
                                label: s.hoursFlagged, color: tokens.danger)
                            : WebPill(
                                label: s.hoursVerified,
                                color: tokens.statusDone),
              ];
            }).toList(),
            flex: const [3, 3, 1, 2],
            onRowTap: (i) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      WorkerProfileScreen(user: sortedUsers[i]),
                ),
              );
            },
            emptyText: s.noWorkersYet,
          ),
        ),
        const SizedBox(height: 22),
        LayoutBuilder(builder: (context, constraints) {
          final wide = constraints.maxWidth >= kWebRailBreakpoint;
          final runCard = _runCard(context, s, tokens, deliveryRuns, users);
          final attention = _attentionCard(
              context, s, tokens, blocked, flaggedOpen, siteName);
          if (!wide) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [runCard, const SizedBox(height: 14), attention],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: runCard),
              const SizedBox(width: 14),
              Expanded(child: attention),
            ],
          );
        }),
      ],
    );
  }

  String _nextStopTitle(DeliveryRun run) {
    for (final stop in run.stops) {
      if (stop.status == StopStatus.pending) return stop.title;
    }
    return run.stops.isEmpty ? '—' : run.stops.last.title;
  }

  Widget _runCard(BuildContext context, AppStrings s, AppColors tokens,
      List<DeliveryRun> runs, List<AppUser> users) {
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WebSectionHeader(title: s.seansRun),
          const SizedBox(height: 10),
          if (runs.isEmpty) ...[
            Text(s.noRunToday,
                style: TextStyle(color: tokens.textSecondary)),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.local_shipping_outlined, size: 18),
                label: Text(s.planRun),
                // The theme gives every OutlinedButton an
                // infinite minimum width — bound it to its
                // content (same fix as the topbar button).
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const RunBuilderScreen()),
                  );
                },
              ),
            ),
          ] else
            for (final run in runs) ...[
              _RunSummary(run: run, driverName: _driverName(run, users)),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) => WebRunScreen(run: run)),
                        );
                      },
                      child: Text(s.viewRun),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  RunBuilderScreen(existingRun: run)),
                        );
                      },
                      child: Text(s.editRun),
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }

  String _driverName(DeliveryRun run, List<AppUser> users) {
    return users
            .where((u) => u.id == run.driverId)
            .firstOrNull
            ?.name ??
        run.driverId;
  }

  Widget _attentionCard(BuildContext context, AppStrings s, AppColors tokens,
      List<TaskItem> blocked, List<TimeEntry> flaggedOpen,
      String Function(String id) siteName) {
    final items = <Widget>[];
    for (final t in blocked.take(5)) {
      items.add(_attentionRow(
        context,
        title: t.title,
        meta: siteName(t.siteId),
        pill: WebPill(label: s.blocked, color: tokens.statusBlocked),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => TaskScreen(task: t)),
          );
        },
      ));
    }
    for (final e in flaggedOpen) {
      items.add(_attentionRow(
        context,
        title: e.userName,
        meta: '${e.siteName} · ${s.flagReasonLabel(e.flagReason)}',
        pill: WebPill(label: s.hoursFlagged, color: tokens.danger),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => ClockLocationScreen(entry: e)),
          );
        },
      ));
    }
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WebSectionHeader(title: s.needsAttention),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Text(s.nothingToday,
                style: TextStyle(color: tokens.textSecondary))
          else
            ...items,
        ],
      ),
    );
  }

  Widget _attentionRow(
    BuildContext context, {
    required String title,
    required String meta,
    required Widget pill,
    required VoidCallback onTap,
  }) {
    final tokens = AppTokens.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Text(meta,
                      style: TextStyle(
                          fontSize: 12, color: tokens.textSecondary),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 10),
            pill,
          ],
        ),
      ),
    );
  }
}

class _RunSummary extends StatelessWidget {
  final DeliveryRun run;
  final String driverName;
  const _RunSummary({required this.run, required this.driverName});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final done =
        run.stops.where((s) => s.status == StopStatus.completed).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          driverName,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        RunProgressBar(completed: done, total: run.stops.length),
        const SizedBox(height: 6),
        Text(
          '$done / ${run.stops.length}',
          style: TextStyle(fontSize: 13, color: tokens.textSecondary),
        ),
      ],
    );
  }
}
