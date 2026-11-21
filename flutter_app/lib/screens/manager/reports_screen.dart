import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/app_user.dart';
import '../../models/day_report.dart';
import '../../models/site.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/sites_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../services/progress_share.dart';
import '../../services/report_service.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/section_label.dart';
import '../../widgets/skeleton_card.dart';
import '../../widgets/status_indicator.dart';
import '../../models/task_item.dart';
import '../task_screen.dart';

/// Day reports are admin/manager-only in the Firestore rules, so
/// this stream only runs for them (and never while signed out).
final _reportsProvider = StreamProvider<List<DayReport>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null || !user.isAdminOrManager) return Stream.value([]);
  return ref.watch(reportServiceProvider).watchReports();
});

/// The end-of-day send channel (admin only — the Send controls
/// are admin-only, so nobody else ever subscribes).
final _eodChannelProvider = StreamProvider<String>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null || user.role != UserRole.admin) {
    return Stream.value(ReportService.eodChannelDefault);
  }
  return ref.watch(reportServiceProvider).watchEodChannel();
});

/// Whether the end-of-day email transport exists yet:
/// `settings/eodReport.emailTransportReady`, set server-side
/// once the Firebase Trigger Email extension is installed.
/// Missing doc/field means false — the email/both channel
/// options stay hidden until then (the stored channel value
/// itself is never changed by hiding them). Same rule as the
/// Settings screen's picker; the two must stay consistent.
final _eodEmailReadyProvider = StreamProvider<bool>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null || user.role != UserRole.admin) {
    return Stream.value(false);
  }
  return FirebaseFirestore.instance
      .collection('settings')
      .doc('eodReport')
      .snapshots()
      .map((snap) => snap.data()?['emailTransportReady'] as bool? ?? false);
});

bool _sameDay(DateTime? d, DateTime day) =>
    d != null && d.year == day.year && d.month == day.month && d.day == day.day;

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Past end-of-day reports (the 6 PM Cloud Function writes these;
/// the button builds today's one on demand) — now led by the
/// end-of-day check: today's snapshot, blocked-first, today's
/// photo proof, and the week so far, with the archive below.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  bool _sending = false;

  /// Builds the client-facing progress text for one site, in the
  /// current app language: done / in progress / blocked (with its
  /// reason) sections, each omitted when empty.
  Future<void> _shareProgress(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final sites = ref.read(sitesProvider).valueOrNull ?? [];
    if (sites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.noSites)),
      );
      return;
    }
    Site? picked = sites.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(s.pickSite),
          content: DropdownButtonFormField<Site>(
            initialValue: picked,
            isExpanded: true,
            items: [
              for (final site in sites)
                DropdownMenuItem(
                    value: site,
                    child: Text(site.name,
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => picked = v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(s.confirm)),
          ],
        ),
      ),
    );
    if (ok != true || picked == null || !context.mounted) return;
    final tasks = ref.read(allTasksProvider).valueOrNull ?? [];
    final text = buildProgressText(s, picked!, tasks);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.shareProgress),
        content: SingleChildScrollView(child: SelectableText(text)),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy_outlined, size: 18),
            label: Text(s.copy),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (ctx.mounted) Navigator.pop(ctx);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.copied)),
                );
              }
            },
          ),
          FilledButton.icon(
            icon: const Icon(Icons.share_outlined, size: 18),
            label: Text(s.share),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await SharePlus.instance.share(ShareParams(text: text));
              } catch (_) {
                // No share sheet available - fall back to the
                // clipboard so the update is never lost.
                await Clipboard.setData(ClipboardData(text: text));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(s.copied)),
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  /// Same navigation the app already uses to open a task (My Day,
  /// History, notifications): the worker task detail screen.
  void _openTask(TaskItem task) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskScreen(task: task)),
    );
  }

  /// Admin only: ask the Cloud Function to build and send today's
  /// report now, on the stored channel.
  Future<void> _sendNow(AppUser me) async {
    if (_sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(reportServiceProvider).requestSendNow(me.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(ref.read(stringsProvider).reportSendRequested)),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(stringsProvider).reportSendFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final reportsAsync = ref.watch(_reportsProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final isAdmin = me?.role == UserRole.admin;
    final channel = ref.watch(_eodChannelProvider).valueOrNull ??
        ReportService.eodChannelDefault;
    final emailReady =
        ref.watch(_eodEmailReadyProvider).valueOrNull ?? false;
    final sites = ref.watch(sitesProvider).valueOrNull ?? [];
    final tasks = ref.watch(allTasksProvider).valueOrNull ?? [];
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final userById = {for (final u in users) u.id: u};
    final siteById = {for (final site in sites) site.id: site};
    final now = DateTime.now();
    final today = _dayOnly(now);

    // --- Today's snapshot -------------------------------------
    // A site's "today" work is what finished today plus what is
    // still open there; a site with neither is left out so the
    // snapshot stays one live line per site.
    final doneToday = tasks
        .where((t) => t.status == TaskStatus.done && _sameDay(t.finishedAt, today))
        .toList();
    final snapshotSites = sites.where((site) {
      return tasks.any((t) =>
          t.siteId == site.id &&
          (t.status != TaskStatus.done ||
              _sameDay(t.finishedAt, today)));
    }).toList();

    // --- Blocked-first ----------------------------------------
    final blocked = tasks.where((t) => t.status == TaskStatus.blocked).toList()
      ..sort((a, b) {
        final siteCmp = (siteById[a.siteId]?.name ?? '')
            .compareTo(siteById[b.siteId]?.name ?? '');
        return siteCmp != 0 ? siteCmp : a.title.compareTo(b.title);
      });

    // --- Photo proof: today's done tasks with photos, by site --
    final photoTasksBySite = <String, List<TaskItem>>{};
    for (final t in doneToday) {
      if (t.photoUrls.isEmpty) continue;
      (photoTasksBySite[t.siteId] ??= []).add(t);
    }

    // --- Week view (Mon-Sun of the current week) ---------------
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final weekDays =
        List.generate(7, (i) => monday.add(Duration(days: i)));
    final doneThisWeek = tasks
        .where((t) =>
            t.status == TaskStatus.done &&
            t.finishedAt != null &&
            !_dayOnly(t.finishedAt!).isBefore(monday) &&
            !_dayOnly(t.finishedAt!).isAfter(today))
        .toList();
    // Who did what, framed as work done: per person, this week's
    // finished tasks (most work first). A task with several
    // assignees lists under each of them — they all did the work —
    // so it still counts once per person, never once per task in
    // the totals.
    final byPerson = <String, List<TaskItem>>{};
    for (final t in doneThisWeek) {
      final ids = t.assigneeIds.isEmpty ? const [''] : t.assigneeIds;
      for (final id in ids) {
        (byPerson[id] ??= []).add(t);
      }
    }
    final personOrder = byPerson.keys.toList()
      ..sort((a, b) => byPerson[b]!.length.compareTo(byPerson[a]!.length));

    Widget sectionGap() => const SizedBox(height: 20);

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.summarize_outlined),
        label: Text(s.generateReport),
        onPressed: () async {
          HapticFeedback.lightImpact();
          try {
            await ref
                .read(reportServiceProvider)
                .buildAndSaveReport(DateTime.now());
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.generateReport)));
            }
          } catch (_) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(s.reportFailed)));
            }
          }
        },
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 96),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.share_outlined, size: 19),
              label: Text(s.shareProgress),
              onPressed: () => _shareProgress(context, ref),
            ),
          ),
          sectionGap(),

          // 1. Today's snapshot: one line per site.
          SectionLabel(s.todaysSnapshot),
          const SizedBox(height: 8),
          if (snapshotSites.isEmpty)
            Text(s.noWorkYet,
                style: TextStyle(fontSize: 13, color: tokens.textTertiary))
          else
            for (final site in snapshotSites)
              Builder(builder: (context) {
                final siteTasks = tasks.where((t) =>
                    t.siteId == site.id &&
                    (t.status != TaskStatus.done ||
                        _sameDay(t.finishedAt, today)));
                final doneCount = siteTasks
                    .where((t) =>
                        t.status == TaskStatus.done &&
                        _sameDay(t.finishedAt, today))
                    .length;
                final totalCount = siteTasks.length;
                final blockedCount = siteTasks
                    .where((t) => t.status == TaskStatus.blocked)
                    .length;
                final overdueCount =
                    siteTasks.where((t) => t.isOverdue).length;
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  child: ListTile(
                    dense: true,
                    title: Text(site.name,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary)),
                    subtitle: RichText(
                      text: TextSpan(
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: tokens.textTertiary),
                        children: [
                          TextSpan(
                            text: s.tasksDone(doneCount, totalCount),
                            style: TextStyle(color: tokens.statusDone),
                          ),
                          if (blockedCount > 0)
                            TextSpan(text: ' · ${s.blocked}: $blockedCount'),
                          if (overdueCount > 0)
                            TextSpan(text: ' · ${s.overdue}: $overdueCount'),
                        ],
                      ),
                    ),
                    trailing: doneCount == totalCount && totalCount > 0
                        ? Icon(Icons.check_circle_outline,
                            color: tokens.statusDone)
                        : null,
                  ),
                );
              }),
          sectionGap(),

          // 2. Blocked-first: every blocked task, with its reason.
          SectionLabel('${s.blocked} (${blocked.length})'),
          const SizedBox(height: 8),
          if (blocked.isEmpty)
            Text(s.noBlockedTasks,
                style: TextStyle(fontSize: 13, color: tokens.textTertiary))
          else
            for (final t in blocked)
              Card(
                margin: const EdgeInsets.symmetric(vertical: 3),
                child: ListTile(
                  dense: true,
                  title: Text(t.title),
                  subtitle: Text(
                    '${siteById[t.siteId]?.name ?? ''}'
                    ' · ${blockedReasonLabel(s, t.blockedReason)}'
                    '${t.blockedNote.isEmpty ? '' : ' — ${t.blockedNote}'}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: StatusIndicator(status: TaskStatus.blocked),
                  onTap: () => _openTask(t),
                ),
              ),
          sectionGap(),

          // 3. Photo proof strip: today's completed-task photos.
          SectionLabel(s.photoProof),
          const SizedBox(height: 8),
          if (photoTasksBySite.isEmpty)
            Text(s.noPhotosToday,
                style: TextStyle(fontSize: 13, color: tokens.textTertiary))
          else
            for (final entry in photoTasksBySite.entries) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6, bottom: 4),
                child: Text(
                  siteById[entry.key]?.name ?? '',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: tokens.textSecondary),
                ),
              ),
              SizedBox(
                height: 96,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: entry.value
                      .expand((t) => t.photoUrls.map((u) => (t, u)))
                      .length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (context, index) {
                    final pairs = entry.value
                        .expand((t) => t.photoUrls.map((u) => (t, u)))
                        .toList();
                    final url = pairs[index].$2;
                    return GestureDetector(
                      // Opens the viewer on this photo, swipeable
                      // across the site's whole strip.
                      onTap: () => showPhotoViewer(
                        context,
                        items: pairs
                            .map((p) => PhotoViewerItem(
                                  url: p.$2,
                                  label: p.$1.title,
                                ))
                            .toList(),
                        initialIndex: index,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(url,
                            width: 96,
                            height: 96,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                                  width: 96,
                                  height: 96,
                                  color: tokens.surfaceRaised,
                                  child: Icon(Icons.broken_image_outlined,
                                      color: tokens.textTertiary),
                                )),
                      ),
                    );
                  },
                ),
              ),
            ],
          sectionGap(),

          // 4. Week view: Mon-Sun done counts, then who did what.
          SectionLabel(s.thisWeek),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final day in weekDays)
                Expanded(
                  child: Builder(builder: (context) {
                    final count = doneThisWeek
                        .where((t) => _sameDay(t.finishedAt, day))
                        .length;
                    final isToday = _sameDay(day, today);
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isToday
                            ? tokens.accentMuted
                            : tokens.surfaceRaised,
                        borderRadius: BorderRadius.circular(8),
                        border: isToday
                            ? Border.all(color: tokens.accent)
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(
                            DateFormat('EEE', s.lang).format(day),
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isToday
                                    ? tokens.accentText
                                    : tokens.textTertiary),
                          ),
                          const SizedBox(height: 2),
                          Text('$count',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: tokens.textPrimary)),
                        ],
                      ),
                    );
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SectionLabel(s.whoDidWhat),
          const SizedBox(height: 8),
          if (doneThisWeek.isEmpty)
            Text(s.noWorkThisWeek,
                style: TextStyle(fontSize: 13, color: tokens.textTertiary))
          else
            for (final assigneeId in personOrder)
              Builder(builder: (context) {
                final personTasks = byPerson[assigneeId]!;
                final name = assigneeId.isEmpty
                    ? s.unassigned
                    : (userById[assigneeId]?.name ?? s.formerMember);
                return Card(
                  margin: const EdgeInsets.symmetric(vertical: 3),
                  child: ListTile(
                    dense: true,
                    title: Text(name,
                        style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary)),
                    subtitle: Text(
                      personTasks.map((t) => t.title).join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Text(
                      s.tasksCount(personTasks.length),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: tokens.textSecondary),
                    ),
                  ),
                );
              }),
          sectionGap(),

          // 5. Send controls (admin only).
          if (isAdmin && me != null) ...[
            SectionLabel(s.sendReport),
            const SizedBox(height: 8),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.sendChannel,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: tokens.textSecondary)),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: [
                        ButtonSegment(
                            value: 'push',
                            label: Text(s.channelPush),
                            icon: const Icon(Icons.notifications_outlined,
                                size: 18)),
                        // Email options stay hidden until the
                        // email transport exists (see
                        // _eodEmailReadyProvider): the stored
                        // channel value itself is untouched.
                        if (emailReady)
                          ButtonSegment(
                              value: 'email',
                              label: Text(s.channelEmail),
                              icon: const Icon(Icons.email_outlined,
                                  size: 18)),
                        if (emailReady)
                          ButtonSegment(
                              value: 'both',
                              label: Text(s.channelBoth),
                              icon: const Icon(Icons.done_all_outlined,
                                  size: 18)),
                      ],
                      selected: {emailReady ? channel : 'push'},
                      onSelectionChanged: (next) {
                        if (next.isNotEmpty) {
                          ref
                              .read(reportServiceProvider)
                              .saveEodChannel(next.first);
                        }
                      },
                    ),
                    if (!emailReady) ...[
                      const SizedBox(height: 8),
                      Text(
                        s.eodEmailUnavailable,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      icon: const Icon(Icons.send_outlined, size: 18),
                      label: Text(s.sendNow),
                      onPressed:
                          _sending ? null : () => _sendNow(me),
                    ),
                  ],
                ),
              ),
            ),
            sectionGap(),
          ],

          // 6. The generated-reports archive, kept below.
          SectionLabel(s.pastReports),
          const SizedBox(height: 8),
          reportsAsync.when(
            loading: () => SkeletonList(count: 4),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (reports) => reports.isEmpty
                ? EmptyState(
                    icon: Icons.summarize_outlined, title: s.noTasks)
                : Column(
                    children: [
                      for (final r in reports)
                        Card(
                          margin:
                              const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            title: Text(
                              DateFormat('EEE MMM d, yyyy').format(r.date),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: tokens.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              '${s.done}: ${r.doneCount} · ${s.inProgress}: ${r.inProgressCount} · ${s.blocked}: ${r.blockedCount} · ${s.overdue}: ${r.overdueCount}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: tokens.textTertiary,
                              ),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => Navigator.of(context).push(
                              MaterialPageRoute(
                                  builder: (_) =>
                                      ReportDetailScreen(report: r)),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// One report: counts plus the actual tasks behind them
/// (ids resolved to titles from the live tasks stream; blocked
/// entries show their reason/note from the report snapshot).
class ReportDetailScreen extends ConsumerWidget {
  final DayReport report;
  const ReportDetailScreen({super.key, required this.report});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final tasks = ref.watch(allTasksProvider).valueOrNull ?? [];
    final byId = {for (final t in tasks) t.id: t};
    String titleOf(String id) => byId[id]?.title ?? id;

    Widget countDot(Color color, String text) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
        ],
      );
    }

    Widget section(String label, List<String> ids, {bool blocked = false}) {
      if (ids.isEmpty) return const SizedBox.shrink();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 18),
          SectionLabel('$label (${ids.length})'),
          const SizedBox(height: 8),
          for (final id in ids)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                dense: true,
                title: Text(titleOf(id)),
                subtitle: blocked
                    ? Text(report.blockedReasons[id] ?? '')
                    : null,
                trailing: blocked
                    ? StatusIndicator(status: TaskStatus.blocked)
                    : null,
              ),
            ),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
          title: Text(DateFormat('MMM d, yyyy').format(report.date))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              countDot(tokens.statusDone,
                  '${s.done}: ${report.doneCount}'),
              countDot(tokens.statusInProgress,
                  '${s.inProgress}: ${report.inProgressCount}'),
              countDot(tokens.statusBlocked,
                  '${s.blocked}: ${report.blockedCount}'),
              countDot(tokens.danger,
                  '${s.overdue}: ${report.overdueCount}'),
            ],
          ),
          section(s.done, report.doneTaskIds),
          section(s.blocked, report.blockedReasons.keys.toList(),
              blocked: true),
          section(s.inProgress, report.inProgressTaskIds),
          section(s.overdue, report.overdueTaskIds),
        ],
      ),
    );
  }
}
