import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../l10n/app_strings.dart';
import '../../models/site.dart';
import '../../models/time_entry.dart';
import '../../providers/locale_provider.dart';
import '../../providers/sites_provider.dart';
import '../../providers/time_entries_provider.dart';
import '../../services/hours_csv.dart';
import '../../theme/app_tokens.dart';
import '../../utils/week_hours.dart';
import '../../widgets/hours_entry_editor.dart';
import '../clock_location_screen.dart';
import 'web_shared.dart';

/// Hours: the mockup's week table. One row per worker, one
/// column per day (Mon–Sun), plus totals — the same live
/// payroll total the phone Hours screen shows (open entries
/// count their hours so far, shifts crossing midnight split
/// across days), so the two views never disagree. Below the
/// table, the week's entries (tap one for the map). Export CSV
/// uses the shared builder, so the file is byte-identical to
/// the phone's. Week math is America/Toronto (see
/// week_hours.dart), never the browser's timezone. Editing
/// entries stays phone-only for now (noted in the report).
class WebHoursScreen extends ConsumerStatefulWidget {
  const WebHoursScreen({super.key});

  @override
  ConsumerState<WebHoursScreen> createState() => _WebHoursScreenState();
}

class _WebHoursScreenState extends ConsumerState<WebHoursScreen> {
  late DateTime _weekStart;
  String? _siteFilter;
  bool _exporting = false;

  @override
  void initState() {
    super.initState();
    _weekStart = weekStartFor(torontoNow());
  }

  DateTime get _weekEnd => _weekStart.add(const Duration(days: 6));

  String _dateStr(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  List<TimeEntry> _inPeriod(List<TimeEntry> all) {
    return entriesInWeek(all, _weekStart);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final all = ref.watch(allTimeEntriesProvider).valueOrNull ?? [];
    final sites = ref.watch(sitesProvider).valueOrNull ?? [];
    final inPeriod = _inPeriod(all);
    final filtered = _siteFilter == null
        ? inPeriod
        : inPeriod.where((e) => e.siteId == _siteFilter).toList();

    // Per-worker, per-day hours + totals, keyed by userId
    // (two workers sharing a name never merge — names are
    // display only). An entry counts its server hours when
    // present, otherwise the time between clock-in and
    // clock-out — same rule as the phone Hours screen, so the
    // two views never disagree. Open entries count their live
    // hours so far, and a shift crossing midnight splits
    // across the days it touches.
    final dayHours = <String, Map<String, double>>{};
    final totals = <String, double>{};
    final namesById = <String, String>{};
    final days = List.generate(7, (i) => _weekStart.add(Duration(days: i)));
    for (final e in filtered) {
      namesById.putIfAbsent(e.userId, () => e.userName);
      for (final d in days) {
        final h = entryHoursOnTorontoDate(e, d);
        if (h <= 0) continue;
        final byDay = dayHours.putIfAbsent(e.userId, () => {});
        byDay[_dateStr(d)] = (byDay[_dateStr(d)] ?? 0) + h;
      }
      final weekH = entryHoursInWeek(e, _weekStart);
      if (weekH > 0) {
        totals[e.userId] = (totals[e.userId] ?? 0) + weekH;
      }
    }
    final workerIds = totals.keys.toList()
      ..sort((a, b) => (namesById[a] ?? a).compareTo(namesById[b] ?? b));
    final dayFmt = DateFormat('EEE');

    final entriesSorted = List<TimeEntry>.from(filtered)
      ..sort((a, b) {
        final c = a.date.compareTo(b.date);
        return c == 0
            ? a.clockInAt.compareTo(b.clockInAt)
            : c;
      });

    return ListView(
      padding: webContentPadding(MediaQuery.sizeOf(context).width),
      children: [
        LayoutBuilder(builder: (context, constraints) {
          // On phones the week nav and the actions stack: one row
          // of chevrons + dropdown + Export would overflow 390px.
          final narrow = constraints.maxWidth < kWebDrawerBreakpoint;
          final nav = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: s.hoursPreviousWeek,
                onPressed: () => setState(() => _weekStart =
                    _weekStart.subtract(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_left),
              ),
              Text(
                s.hoursWeekLabel(
                  DateFormat('MMM d').format(_weekStart),
                  DateFormat('MMM d').format(_weekEnd),
                ),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700),
              ),
              IconButton(
                tooltip: s.hoursNextWeek,
                onPressed: () => setState(
                    () => _weekStart = _weekStart.add(const Duration(days: 7))),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _siteDropdown(s, tokens, sites),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed:
                    _exporting ? null : () => _exportCsv(filtered, totals),
                icon: const Icon(Icons.download, size: 18),
                label: Text(s.hoursExportCsv),
                // The theme gives every FilledButton an infinite minimum
                // width — bound it to its content (same fix as the
                // topbar button).
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                ),
              ),
            ],
          );
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                nav,
                const SizedBox(height: 8),
                actions,
              ],
            );
          }
          return Row(children: [nav, const Spacer(), actions]);
        }),
        const SizedBox(height: 14),
        WebCard(
          child: WebResponsiveTable(
            headers: [
              s.crew,
              ...days.map((d) => dayFmt.format(d)),
              s.totalHours,
            ],
            rows: workerIds.map((id) {
              final byDay = dayHours[id] ?? {};
              return [
                Text(namesById[id] ?? id,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
                ...days.map((d) {
                  final h = byDay[_dateStr(d)] ?? 0;
                  return Text(h == 0 ? '—' : webHours(h));
                }),
                Text(
                  webHours(totals[id]!),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ];
            }).toList(),
            flex: const [2, 1, 1, 1, 1, 1, 1, 1, 1],
            emptyText: s.hoursNoEntries,
          ),
        ),
        const SizedBox(height: 22),
        WebSectionHeader(title: s.hours),
        const SizedBox(height: 10),
        if (entriesSorted.isEmpty)
          Text(s.hoursNoEntries,
              style: TextStyle(color: tokens.textSecondary))
        else
          WebCard(
            child: Column(
              children: [
                for (var i = 0; i < entriesSorted.length; i++) ...[
                  _entryRow(context, s, tokens, entriesSorted[i]),
                  if (i < entriesSorted.length - 1)
                    Divider(height: 1, color: tokens.border),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _siteDropdown(
      AppStrings s, AppColors tokens, List<Site> sites) {
    return DropdownButton<String?>(
      value: _siteFilter,
      underline: const SizedBox.shrink(),
      items: [
        DropdownMenuItem<String?>(
            value: null, child: Text(s.hoursAllSites)),
        for (final site in sites)
          DropdownMenuItem<String?>(
              value: site.id, child: Text(site.name)),
      ],
      onChanged: (v) => setState(() => _siteFilter = v),
    );
  }

  Widget _entryRow(
      BuildContext context, AppStrings s, AppColors tokens, TimeEntry e) {
    final hours = e.effectiveHours;
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ClockLocationScreen(entry: e)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(e.userName,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  Text(
                    '${e.date} · ${e.siteName} · ${webTime(e.clockInAt)} – ${e.clockOutAt == null ? s.hoursStillClockedIn : webTime(e.clockOutAt!)}',
                    style:
                        TextStyle(fontSize: 12, color: tokens.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(webHours(hours),
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            if (e.auto)
              WebPill(label: s.autoTag, color: tokens.accent),
            if (e.auto) const SizedBox(width: 10),
            e.flagged
                ? WebPill(label: s.hoursFlagged, color: tokens.danger)
                : WebPill(label: s.hoursVerified, color: tokens.statusDone),
            // Edit the entry's site/times — the same dialog the
            // phone Hours screen uses. The button handles its
            // own tap, so it does not open the map.
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              tooltip: s.hoursEditEntry,
              onPressed: () => showEditTimeEntry(context, ref, e),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportCsv(
      List<TimeEntry> entries, Map<String, double> totals) async {
    final s = ref.read(stringsProvider);
    setState(() => _exporting = true);
    try {
      final csv = buildHoursCsv(entries, totals);
      final filename =
          'dyadespace-hours-${_dateStr(_weekStart)}-to-${_dateStr(_weekEnd)}.csv';
      await SharePlus.instance.share(ShareParams(files: [
        XFile.fromData(utf8.encode(csv),
            name: filename, mimeType: 'text/csv'),
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
}
