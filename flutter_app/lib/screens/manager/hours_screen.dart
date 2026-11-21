import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../l10n/app_strings.dart';
import '../../models/app_user.dart';
import '../../models/time_entry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/sites_provider.dart';
import '../../providers/time_entries_provider.dart';
import '../../services/hours_csv.dart';
import '../../theme/app_tokens.dart';
import '../../utils/hours_format.dart';
import '../../utils/week_hours.dart';
import '../../widgets/member_tile.dart';
import '../worker_profile_screen.dart';

/// The managers' Hours screen, reached from the Board's
/// shortcuts row. One card per person (Team-style): photo,
/// name, the week total next to it, and the clock-in status
/// under the name. Tapping a card opens that person's profile
/// on the Clock-in tab — the entries live there now, with the
/// edit button on each history row. Week (Monday–Sunday,
/// current week by default) and site filter sit on top and
/// drive the totals; the week exports as a CSV (entries +
/// per-worker totals) through the system share sheet.
///
/// An entry's hours are the server value when it exists,
/// otherwise the time between clock-in and clock-out — the
/// verify function hasn't run yet for older entries, so
/// without the fallback their hours read "—" and the totals
/// stayed at zero. Open entries count their live hours so far
/// (the same rule as week_hours.dart and the web Hours
/// screen), and a shift crossing midnight counts only its
/// part in this week — so the three views never disagree.
///
/// Times are America/Toronto (see week_hours.dart) — the
/// server's timezone — never device-local. The CSV headers
/// stay in English on purpose: the file is a payroll import,
/// and the columns must be stable whatever the phone's
/// language is.
class HoursScreen extends ConsumerStatefulWidget {
  const HoursScreen({super.key});

  @override
  ConsumerState<HoursScreen> createState() => _HoursScreenState();
}

class _HoursScreenState extends ConsumerState<HoursScreen> {
  late DateTime _weekStart; // Monday, day only.
  String _siteFilter = 'all';
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    // Monday, day only — the shared week definition (see
    // week_hours.dart), in Toronto time: the profile header
    // and Team tiles total the same week.
    _weekStart = weekStartFor(torontoNow());
  }

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 6));

  String _dateStr(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  /// Per-worker totals for the period, keyed by userId (two
  /// workers sharing a name never merge — names are display
  /// only). Each entry counts only the hours falling in this
  /// week (split at midnight), server hours when present,
  /// otherwise the time between clock-in and clock-out; an
  /// open entry counts its live time so far.
  static Map<String, double> _totalsFor(
      List<TimeEntry> entries, DateTime weekStart) {
    final totals = <String, double>{};
    for (final e in entries) {
      final h = entryHoursInWeek(e, weekStart);
      if (h <= 0) continue;
      totals.update(e.userId, (v) => v + h, ifAbsent: () => h);
    }
    return totals;
  }

  void _shiftWeek(int weeks) {
    setState(() => _weekStart = _weekStart.add(Duration(days: 7 * weeks)));
  }

  List<TimeEntry> _inPeriod(List<TimeEntry> all) {
    // Overlap with the Toronto week (a shift crossing
    // midnight belongs to both weeks, split by the totals) —
    // then the site filter.
    return entriesInWeek(all, _weekStart).where((e) {
      if (_siteFilter != 'all' && e.siteId != _siteFilter) return false;
      return true;
    }).toList();
  }

  Future<void> _exportCsv(
      List<TimeEntry> entries, Map<String, double> totals) async {
    final s = ref.read(stringsProvider);
    setState(() => _exporting = true);
    try {
      final csv = buildHoursCsv(entries, totals);
      final filename =
          'dyadespace-hours-${_dateStr(_weekStart)}-to-${_dateStr(_weekEnd)}.csv';
      // In-memory bytes, not a temp file: same share sheet on
      // phones, and it works on web too (the browser downloads
      // the file).
      await SharePlus.instance.share(ShareParams(files: [
        XFile.fromData(utf8.encode(csv), name: filename, mimeType: 'text/csv'),
      ]));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.hoursCsvShared)),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.hoursCsvFailed)),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final entriesAsync = ref.watch(allTimeEntriesProvider);
    final siteById = ref.watch(siteByIdProvider);
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final userById = {for (final u in users) u.id: u};
    final sites = siteById.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    return Scaffold(
      appBar: AppBar(
        title: Text(s.hours),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download_outlined),
            tooltip: s.hoursExportCsv,
            onPressed: _exporting
                ? null
                : () {
                    final all = entriesAsync.valueOrNull ?? [];
                    final entries = _inPeriod(all);
                    _exportCsv(entries, _totalsFor(entries, _weekStart));
                  },
          ),
        ],
      ),
      body: entriesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (all) {
          final entries = _inPeriod(all);
          final totals = _totalsFor(entries, _weekStart);
          final byWorker = <String, List<TimeEntry>>{};
          for (final e in entries) {
            byWorker.putIfAbsent(e.userId, () => []).add(e);
          }
          final workerIds = byWorker.keys.toList()
            ..sort((a, b) => (byWorker[a]!.first.userName)
                .compareTo(byWorker[b]!.first.userName));
          final weekLabel = s.hoursWeekLabel(
            DateFormat('MMM d').format(_weekStart),
            DateFormat('MMM d, yyyy').format(_weekEnd),
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            children: [
              Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left),
                    tooltip: s.hoursPreviousWeek,
                    onPressed: () => _shiftWeek(-1),
                  ),
                  Expanded(
                    child: Text(
                      weekLabel,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right),
                    tooltip: s.hoursNextWeek,
                    onPressed: () => _shiftWeek(1),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _siteFilter,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: s.site,
                  border: const OutlineInputBorder(),
                ),
                items: [
                  DropdownMenuItem(value: 'all', child: Text(s.hoursAllSites)),
                  for (final site in sites)
                    DropdownMenuItem(
                      value: site.id,
                      child: Text(site.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _siteFilter = v);
                },
              ),
              const SizedBox(height: 16),
              if (entries.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 32),
                    child: Text(s.hoursNoEntries),
                  ),
                )
              else
                for (final workerId in workerIds) ...[
                  _personCard(
                    context,
                    s,
                    tokens,
                    byWorker[workerId]!,
                    totals[workerId] ?? 0,
                    userById[workerId],
                  ),
                  const SizedBox(height: 12),
                ],
            ],
          );
        },
      ),
    );
  }

  /// One card per person (Team-style): photo, name, the week
  /// total next to it, and the clock-in status under the name.
  /// Tapping the card opens the person's profile on the
  /// Clock-in tab — the entries live there now, with the edit
  /// button on each history row. An open entry in the week
  /// shows its live "so far" time; otherwise the card counts
  /// the week's entries.
  Widget _personCard(
    BuildContext context,
    AppStrings s,
    AppColors tokens,
    List<TimeEntry> entries,
    double total,
    AppUser? user,
  ) {
    final name = entries.first.userName;
    TimeEntry? open;
    for (final e in entries) {
      if (e.isOpen) {
        open = e;
        break;
      }
    }
    return MemberTile(
      title: name,
      subtitle: user?.email,
      role: user?.role ?? UserRole.worker,
      photoUrl: user?.photoUrl,
      statusText: open != null
          ? s.clockedInFor(formatHoursMinutes(open.hoursSoFar))
          : s.hoursEntriesCount(entries.length),
      statusActive: open != null,
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            s.totalHours,
            style: TextStyle(fontSize: 11, color: tokens.textTertiary),
          ),
          Text(
            formatHoursMinutes(total),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: tokens.accentText,
            ),
          ),
        ],
      ),
      onTap: user == null
          ? null
          : () {
              HapticFeedback.lightImpact();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WorkerProfileScreen(
                    user: user,
                    initialTabIndex: 1,
                  ),
                ),
              );
            },
    );
  }
}
