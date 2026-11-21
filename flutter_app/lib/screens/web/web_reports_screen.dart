import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../l10n/app_strings.dart';
import '../../models/app_user.dart';
import '../../models/day_report.dart';
import '../../models/site.dart';
import '../../models/task_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/sites_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../services/progress_share.dart';
import '../../services/report_service.dart';
import '../../services/task_service.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/photo_viewer.dart';
import '../task_screen.dart';
import 'web_shared.dart';

/// The archive stream for this view (the phone Reports screen
/// has its own file-private copy of the same provider).
final _webReportsProvider = StreamProvider<List<DayReport>>((ref) {
  return ref.watch(reportServiceProvider).watchReports();
});

/// Reports: today's snapshot per site, the blocked-first list,
/// the week's reports, the send controls, and the archive.
/// The photo proof strip and Share-progress are implemented
/// here, same as the phone Reports screen (an older comment
/// claimed they stayed phone-only — they do not).
class WebReportsScreen extends ConsumerWidget {
  const WebReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final now = DateTime.now();
    final allTasks = ref.watch(allTasksProvider).valueOrNull ?? [];
    final sitesById = ref.watch(siteByIdProvider);
    final reports = ref.watch(_webReportsProvider).valueOrNull ?? [];
    final channel =
        ref.watch(_webEodChannelProvider).valueOrNull ?? 'both';
    final eodTime =
        ref.watch(_webEodTimeProvider).valueOrNull ?? '18:00';
    final emailReady =
        ref.watch(_webEodEmailReadyProvider).valueOrNull ?? false;
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final userById = {for (final u in users) u.id: u};
    final isAdmin = me?.role == UserRole.admin;

    final todayTasks = TaskService.tasksForToday(allTasks, now);
    final blocked =
        todayTasks.where((t) => t.status == TaskStatus.blocked).toList();
    final done = todayTasks.where((t) => t.status == TaskStatus.done).length;
    final inProgress =
        todayTasks.where((t) => t.status == TaskStatus.inProgress).length;

    // Photo proof: today's completed tasks with photos, by site
    // — the same grouping as the phone Reports screen.
    final photoTasksBySite = <String, List<TaskItem>>{};
    for (final t in todayTasks) {
      if (t.status != TaskStatus.done || t.photoUrls.isEmpty) continue;
      if (t.finishedAt != null && !_sameDay(t.finishedAt, now)) continue;
      (photoTasksBySite[t.siteId] ??= []).add(t);
    }

    // Snapshot per site: done / total / blocked.
    final perSite = <String, ({int done, int total, int blocked})>{};
    for (final t in todayTasks) {
      final cur = perSite[t.siteId] ?? (done: 0, total: 0, blocked: 0);
      perSite[t.siteId] = (
        done: cur.done + (t.status == TaskStatus.done ? 1 : 0),
        total: cur.total + 1,
        blocked: cur.blocked + (t.status == TaskStatus.blocked ? 1 : 0),
      );
    }
    final siteIds = perSite.keys.toList()
      ..sort((a, b) => (sitesById[a]?.name ?? a)
          .compareTo(sitesById[b]?.name ?? b));

    // Week view (Mon-Sun of the current week) + who did what,
    // mirroring the phone Reports screen: per person, this
    // week's finished tasks (most work first). A task with
    // several assignees lists under each of them.
    final today = _dayOnly(now);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final weekDays =
        List.generate(7, (i) => monday.add(Duration(days: i)));
    final doneThisWeek = allTasks
        .where((t) =>
            t.status == TaskStatus.done &&
            t.finishedAt != null &&
            !_dayOnly(t.finishedAt!).isBefore(monday) &&
            !_dayOnly(t.finishedAt!).isAfter(today))
        .toList();
    final byPerson = <String, List<TaskItem>>{};
    for (final t in doneThisWeek) {
      final ids = t.assigneeIds.isEmpty ? const [''] : t.assigneeIds;
      for (final id in ids) {
        (byPerson[id] ??= []).add(t);
      }
    }
    final personOrder = byPerson.keys.toList()
      ..sort((a, b) => byPerson[b]!.length.compareTo(byPerson[a]!.length));

    // The archive: the last 60 reports, same as the phone
    // Reports screen (watchReports already limits to 60).
    final archive = reports.take(60).toList();

    return ListView(
      padding: webContentPadding(MediaQuery.sizeOf(context).width),
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.share_outlined, size: 19),
            label: Text(s.shareProgress),
            // The theme gives every OutlinedButton an infinite
            // minimum width — bound it to its content (same fix
            // as the topbar button).
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 52),
            ),
            onPressed: () => _shareProgress(context, ref),
          ),
        ),
        const SizedBox(height: 18),
        WebSectionHeader(
          title: s.todaysSnapshot,
          subtitle: DateFormat('EEEE, MMM d').format(now),
        ),
        const SizedBox(height: 12),
        WebStatGrid(cards: [
          WebStatCard(label: s.done, value: '$done'),
          WebStatCard(label: s.inProgress, value: '$inProgress'),
          WebStatCard(
            label: s.blocked,
            value: '${blocked.length}',
            valueColor:
                blocked.isEmpty ? null : tokens.statusBlocked,
          ),
          WebStatCard(
              label: s.tasksToday, value: '${todayTasks.length}'),
        ]),
        const SizedBox(height: 18),
        if (siteIds.isEmpty)
          Text(s.noTasks, style: TextStyle(color: tokens.textSecondary))
        else
          for (final siteId in siteIds) ...[
            _siteLine(
                context, tokens, sitesById[siteId]?.name ?? siteId,
                perSite[siteId]!),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 18),
        WebSectionHeader(title: s.blocked),
        const SizedBox(height: 10),
        if (blocked.isEmpty)
          Text(s.noBlockedTasks,
              style: TextStyle(color: tokens.textSecondary))
        else
          for (final t in blocked) ...[
            _blockedRow(context, s, tokens, t, sitesById[t.siteId]?.name),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 22),
        WebSectionHeader(title: s.photoProof),
        const SizedBox(height: 10),
        if (photoTasksBySite.isEmpty)
          Text(s.noPhotosToday,
              style: TextStyle(color: tokens.textSecondary))
        else
          for (final entry in photoTasksBySite.entries) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(
                sitesById[entry.key]?.name ?? '',
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
                    // across the site's whole strip. On web the
                    // viewer's download opens the original in a
                    // new tab (no gallery on web).
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
                      child: Image.network(
                        url,
                        width: 96,
                        height: 96,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 96,
                          height: 96,
                          color: tokens.surfaceRaised,
                          child: Icon(Icons.broken_image_outlined,
                              color: tokens.textTertiary),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        const SizedBox(height: 22),
        WebSectionHeader(title: s.thisWeek),
        const SizedBox(height: 10),
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
        WebSectionHeader(title: s.whoDidWhat),
        const SizedBox(height: 10),
        if (doneThisWeek.isEmpty)
          Text(s.noWorkThisWeek,
              style: TextStyle(fontSize: 13, color: tokens.textTertiary))
        else
          for (final assigneeId in personOrder) ...[
            Builder(builder: (context) {
              final personTasks = byPerson[assigneeId]!;
              final name = assigneeId.isEmpty
                  ? s.unassigned
                  : (userById[assigneeId]?.name ?? s.formerMember);
              return WebCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis),
                          Text(
                            personTasks.map((t) => t.title).join(' · '),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: tokens.textSecondary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      s.tasksCount(personTasks.length),
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: tokens.textSecondary),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
          ],
        const SizedBox(height: 22),
        WebSectionHeader(title: s.pastReports),
        const SizedBox(height: 10),
        if (archive.isEmpty)
          Text(s.noTasks, style: TextStyle(color: tokens.textSecondary))
        else
          for (final r in archive) ...[
            _reportRow(context, s, tokens, r, allTasks),
            const SizedBox(height: 8),
          ],
        // Send controls are admin-only (the phone restricts send
        // to admin, and sendDayReportNow marks non-admin requests
        // denied) — managers are never offered a send that will
        // be refused.
        if (isAdmin && me != null) ...[
          const SizedBox(height: 22),
          WebSectionHeader(title: s.sendReport),
          const SizedBox(height: 10),
          WebCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'push', label: Text(s.channelPush)),
                    // Email options stay hidden until the email
                    // transport exists (see
                    // _webEodEmailReadyProvider): the stored
                    // channel value itself is untouched.
                    if (emailReady)
                      ButtonSegment(
                          value: 'email', label: Text(s.channelEmail)),
                    if (emailReady)
                      ButtonSegment(
                          value: 'both', label: Text(s.channelBoth)),
                  ],
                  selected: {emailReady ? channel : 'push'},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    ref
                        .read(reportServiceProvider)
                        .saveEodChannel(selection.first);
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
                const SizedBox(height: 8),
                Text(
                  '${s.eodReportTime}: $eodTime',
                  style: TextStyle(color: tokens.textSecondary),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilledButton(
                      onPressed: () => _sendNow(context, ref, me.id),
                      // The theme gives every FilledButton an infinite minimum
                      // width — bound it to its content (same fix as the
                      // topbar button).
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      child: Text(s.sendNow),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: () => _generate(context, ref, now),
                      // The theme gives every OutlinedButton an infinite minimum
                      // width — bound it to its content (same fix as the
                      // topbar button).
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      child: Text(s.generateReport),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _siteLine(BuildContext context, AppColors tokens, String name,
      ({int done, int total, int blocked}) counts) {
    return WebCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(name,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
          Text(
            '${counts.done}/${counts.total}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          if (counts.blocked > 0) ...[
            const SizedBox(width: 10),
            WebPill(
                label: '${counts.blocked} blocked',
                color: tokens.statusBlocked),
          ],
        ],
      ),
    );
  }

  Widget _blockedRow(BuildContext context, AppStrings s, AppColors tokens,
      TaskItem t, String? siteName) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => TaskScreen(task: t)),
        );
      },
      borderRadius: BorderRadius.circular(13),
      child: WebCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.title,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Text(siteName ?? '',
                      style: TextStyle(
                          fontSize: 12, color: tokens.textSecondary),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            const SizedBox(width: 10),
            WebPill(label: s.blocked, color: tokens.statusBlocked),
          ],
        ),
      ),
    );
  }

  Widget _reportRow(BuildContext context, AppStrings s, AppColors tokens,
      DayReport r, List<TaskItem> allTasks) {
    final byId = {for (final t in allTasks) t.id: t};
    return InkWell(
      onTap: () => _reportDetail(context, s, tokens, r, byId),
      borderRadius: BorderRadius.circular(13),
      child: WebCard(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Text(
                DateFormat('EEEE, MMM d').format(r.date),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            Text(
              '${r.doneCount} ${s.done} · ${r.blockedCount} ${s.blocked}',
              style: TextStyle(color: tokens.textSecondary),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, color: tokens.textTertiary),
          ],
        ),
      ),
    );
  }

  Future<void> _reportDetail(BuildContext context, AppStrings s,
      AppColors tokens, DayReport r, Map<String, TaskItem> byId) async {
    final doneTitles = r.doneTaskIds
        .map((id) => byId[id]?.title ?? id)
        .toList();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(DateFormat('EEEE, MMM d').format(r.date)),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  '${s.done}: ${r.doneCount} · ${s.inProgress}: ${r.inProgressCount} · ${s.blocked}: ${r.blockedCount} · ${s.overdue}: ${r.overdueCount}'),
              if (doneTitles.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(s.done,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final title in doneTitles)
                  Text('• $title'),
              ],
              if (r.blockedReasons.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(s.blocked,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                for (final entry in r.blockedReasons.entries)
                  Text('• ${byId[entry.key]?.title ?? entry.key}: '
                      '${entry.value}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.close),
          ),
        ],
      ),
    );
  }

  bool _sameDay(DateTime? d, DateTime day) =>
      d != null &&
      d.year == day.year &&
      d.month == day.month &&
      d.day == day.day;

  DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Share today's progress for one site — the same flow as the
  /// phone Reports screen: pick a site, preview the text, then
  /// Share (system share sheet) or Copy. On web the share sheet
  /// is the browser's Web Share API when available; otherwise
  /// the text is copied so the update is never lost.
  Future<void> _shareProgress(
      BuildContext context, WidgetRef ref) async {
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
                // The theme gives every FilledButton an infinite minimum
                // width — bound it to its content (same fix as the
                // topbar button).
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                ),
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
            // The theme gives every FilledButton an infinite minimum
            // width — bound it to its content (same fix as the
            // topbar button).
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
            ),

            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await SharePlus.instance.share(ShareParams(text: text));
              } catch (_) {
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

  Future<void> _sendNow(
      BuildContext context, WidgetRef ref, String uid) async {
    final s = ref.read(stringsProvider);
    try {
      await ref.read(reportServiceProvider).requestSendNow(uid);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.reportSendRequested)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.reportSendFailed)),
      );
    }
  }

  Future<void> _generate(
      BuildContext context, WidgetRef ref, DateTime day) async {
    final s = ref.read(stringsProvider);
    try {
      await ref.read(reportServiceProvider).buildAndSaveReport(day);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.generateReport)),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.reportSendFailed)),
      );
    }
  }
}

/// The EOD channel/time streams for this view (same shape as the
/// phone Reports screen's file-private providers).
final _webEodChannelProvider = StreamProvider<String>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null || me.role != UserRole.admin) {
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
/// phone Reports screen and the Settings screen's picker; the
/// three must stay consistent.
final _webEodEmailReadyProvider = StreamProvider<bool>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null || me.role != UserRole.admin) {
    return Stream.value(false);
  }
  return FirebaseFirestore.instance
      .collection('settings')
      .doc('eodReport')
      .snapshots()
      .map((snap) => snap.data()?['emailTransportReady'] as bool? ?? false);
});

final _webEodTimeProvider = StreamProvider<String>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null || me.role != UserRole.admin) {
    return Stream.value(ReportService.eodTimeDefault);
  }
  return ref.watch(reportServiceProvider).watchEodTime();
});
