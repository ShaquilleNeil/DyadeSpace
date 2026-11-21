import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/site.dart';
import '../models/time_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/sites_provider.dart';
import '../providers/time_entries_provider.dart';
import '../theme/app_tokens.dart';

/// The hours-entry edit dialog, shared by the phone Hours
/// screen and the web control center's Hours section — one
/// implementation so both stay identical. Managers can correct
/// an entry's site and times, or close a forgotten open entry.
/// Closing the entry needs a clock-out after the clock-in;
/// leaving it open needs nothing more. The save goes through
/// the time-entry service (which writes the hours-audit trail).
Future<void> showEditTimeEntry(
    BuildContext context, WidgetRef ref, TimeEntry entry) async {
  final s = ref.read(stringsProvider);
  final me = ref.read(currentUserProvider).valueOrNull;
  if (me == null) return;
  final siteById = ref.read(siteByIdProvider);
  final sites = siteById.values.toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  // No early return when there are no sites: the entry can
  // still be edited (times, or kept as a day entry) — the
  // dropdown then offers only "No site".
  DateTime inDay = DateTime(
      entry.clockInAt.year, entry.clockInAt.month, entry.clockInAt.day);
  TimeOfDay inTime = TimeOfDay.fromDateTime(entry.clockInAt);
  DateTime? outDay = entry.clockOutAt == null
      ? null
      : DateTime(entry.clockOutAt!.year, entry.clockOutAt!.month,
          entry.clockOutAt!.day);
  TimeOfDay? outTime = entry.clockOutAt == null
      ? null
      : TimeOfDay.fromDateTime(entry.clockOutAt!);
  // Null means a day entry (no site). An entry whose site was
  // deleted keeps its site id/name as a placeholder item, so
  // saving the dialog never silently re-sites it to the first
  // site in the list — the manager sees the old site name and
  // must actively pick another site (or "No site") to change
  // it.
  Site? site;
  if (entry.siteId.isEmpty) {
    site = null;
  } else if (siteById.containsKey(entry.siteId)) {
    site = siteById[entry.siteId];
  } else {
    site = Site(
      id: entry.siteId,
      name: entry.siteName.isEmpty ? entry.siteId : entry.siteName,
    );
  }
  bool stillIn = entry.clockOutAt == null;

  DateTime combine(DateTime day, TimeOfDay time) =>
      DateTime(day.year, day.month, day.day, time.hour, time.minute);

  String timeStr(DateTime d) => DateFormat('HH:mm').format(d);

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Future<void> pickDay(bool isIn) async {
          final picked = await showDatePicker(
            context: ctx,
            initialDate: isIn ? inDay : (outDay ?? inDay),
            firstDate: DateTime(2024),
            lastDate: DateTime.now().add(const Duration(days: 1)),
          );
          if (picked != null) {
            setDialogState(() {
              if (isIn) {
                inDay = picked;
              } else {
                outDay = picked;
              }
            });
          }
        }

        Future<void> pickTime(bool isIn) async {
          final picked = await showTimePicker(
            context: ctx,
            initialTime: isIn ? inTime : (outTime ?? inTime),
          );
          if (picked != null) {
            setDialogState(() {
              if (isIn) {
                inTime = picked;
              } else {
                outTime = picked;
              }
            });
          }
        }

        final inAt = combine(inDay, inTime);
        final outAt = stillIn || outDay == null || outTime == null
            ? null
            : combine(outDay!, outTime!);
        final timesOk = stillIn || (outAt != null && outAt.isAfter(inAt));
        return AlertDialog(
          title: Text(s.hoursEditEntry),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.userName,
                    style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: site?.id ?? '',
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: s.site,
                    border: const OutlineInputBorder(),
                  ),
                  items: [
                    DropdownMenuItem(
                      value: '',
                      child: Text(s.noSite),
                    ),
                    // A deleted site the entry still points at:
                    // shown by its stored name so it survives a
                    // save unchanged unless actively changed.
                    if (site != null && !siteById.containsKey(site!.id))
                      DropdownMenuItem(
                        value: site!.id,
                        child: Text(site!.name,
                            overflow: TextOverflow.ellipsis),
                      ),
                    for (final st in sites)
                      DropdownMenuItem(
                        value: st.id,
                        child: Text(st.name,
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setDialogState(() {
                      if (v.isEmpty) {
                        site = null;
                      } else if (siteById[v] != null) {
                        site = siteById[v];
                      }
                      // A deleted-site placeholder value: keep
                      // the current site (it is already `site`).
                    });
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pickDay(true),
                        child: Text(
                          '${s.hoursClockInTime}\n${DateFormat('MMM d').format(inDay)}',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => pickTime(true),
                        child: Text(timeStr(inAt)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Checkbox(
                      value: stillIn,
                      onChanged: (v) =>
                          setDialogState(() => stillIn = v ?? stillIn),
                    ),
                    Expanded(
                      child: Text(s.hoursStillClockedIn),
                    ),
                  ],
                ),
                if (!stillIn) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => pickDay(false),
                          child: Text(
                            '${s.hoursClockOutTime}\n${outDay == null ? '—' : DateFormat('MMM d').format(outDay!)}',
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => pickTime(false),
                          child: Text(
                              outTime == null ? '—' : outTime!.format(ctx)),
                        ),
                      ),
                    ],
                  ),
                ],
                if (!timesOk) ...[
                  const SizedBox(height: 8),
                  Text(
                    s.hoursInvalidTimes,
                    style: TextStyle(
                        color: AppTokens.of(ctx).danger, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed:
                  timesOk ? () => Navigator.of(ctx).pop(true) : null,
              // The theme gives every FilledButton an infinite minimum
              // width — bound it to its content (same fix as the
              // topbar button).
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
              ),
              child: Text(s.save),
            ),
          ],
        );
      },
    ),
  );
  if (saved != true) return;
  final inAt = combine(inDay, inTime);
  final outAt = stillIn || outDay == null || outTime == null
      ? null
      : combine(outDay!, outTime!);
  if (!stillIn && (outAt == null || !outAt.isAfter(inAt))) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.hoursInvalidTimes)),
      );
    }
    return;
  }
  try {
    await ref.read(timeEntryServiceProvider).updateEntry(
          entry,
          clockInAt: inAt,
          clockOutAt: outAt,
          site: site,
          editedBy: me.id,
        );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.hoursEntrySaved)),
      );
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.hoursEntrySaveFailed('$e'))),
      );
    }
  }
}
