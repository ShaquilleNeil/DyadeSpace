import 'package:intl/intl.dart';
import '../models/time_entry.dart';

/// The hours CSV, shared by the phone Hours screen and the web
/// control center: same columns, same order, same English
/// headers (the file is a payroll import — columns stay stable
/// whatever the app language is). Pure string logic, no Flutter
/// imports, so both screens stay in sync by construction.
/// [totals] is keyed by userId (not name): two workers sharing
/// a name must never merge into one total. Display names come
/// from the entries themselves (first entry per userId wins).
String buildHoursCsv(List<TimeEntry> entries, Map<String, double> totals) {
  final lines = <String>[];
  lines.add('Worker,Date,Site,Clock in,Clock out,Hours,Status');
  for (final e in entries) {
    final status =
        e.flagged ? 'Flagged: ${flagReasonEnglish(e.flagReason)}' : 'Verified';
    lines.add([
      _csvField(e.userName),
      e.date,
      _csvField(e.siteName),
      _timeStr(e.clockInAt),
      e.clockOutAt == null ? '' : _timeStr(e.clockOutAt!),
      e.clockOutAt == null ? '' : e.effectiveHours.toStringAsFixed(2),
      _csvField(status),
    ].join(','));
  }
  lines.add('');
  lines.add('Worker,Total hours');
  final namesById = <String, String>{};
  for (final e in entries) {
    namesById.putIfAbsent(e.userId, () => e.userName);
  }
  final ids = totals.keys.toList()
    ..sort((a, b) => (namesById[a] ?? a).compareTo(namesById[b] ?? b));
  for (final id in ids) {
    lines.add('${_csvField(namesById[id] ?? id)},${totals[id]!.toStringAsFixed(2)}');
  }
  return '${lines.join('\n')}\n';
}

/// CSV field escaping: quote when the value holds a comma, a
/// quote, or a newline.
String _csvField(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

/// English flag reason for the CSV (headers and status stay in
/// English whatever the app language is).
String flagReasonEnglish(String? code) {
  switch (code) {
    case 'outside-radius':
      return 'Outside site radius';
    case 'clock-out-outside-radius':
      return 'Clock-out outside site radius';
    case 'no-location':
      return 'Location unavailable';
    case 'no-site-location':
      return 'No site location set';
    default:
      return 'Flagged';
  }
}

String _timeStr(DateTime d) => DateFormat('HH:mm').format(d);
