import 'package:intl/intl.dart';

import '../models/time_entry.dart';

/// The crew's week, shared by the Hours screen, the profile
/// Clock-in tab and the Team tiles: Monday–Sunday, current
/// week by default. One definition only — the Hours screen
/// used to compute the Monday inline; it now calls
/// [weekStartFor] so the three places can never drift apart.
///
/// All week/date math here is pinned to America/Toronto
/// (the server's timezone: the 23:59 auto-close, the report
/// day, and the stored entry `date` are all Toronto). The
/// device's own timezone is never used — a phone or browser
/// in another timezone must agree with the server near
/// midnight Sunday/Monday. There is no `timezone` package in
/// the app, so Toronto is computed by hand: UTC-5 (EST),
/// UTC-4 (EDT) from the second Sunday of March 07:00 UTC to
/// the first Sunday of November 06:00 UTC.

DateTime _nthSunday(int year, int month, int n) {
  final first = DateTime.utc(year, month, 1);
  final daysToSunday = (7 - first.weekday) % 7;
  return first.add(Duration(days: daysToSunday + 7 * (n - 1)));
}

/// True when the UTC instant [utc] falls in Toronto daylight
/// time (second Sunday March 07:00 UTC – first Sunday
/// November 06:00 UTC).
bool _isTorontoDst(DateTime utc) {
  final start = _nthSunday(utc.year, 3, 2).add(const Duration(hours: 7));
  final end = _nthSunday(utc.year, 11, 1).add(const Duration(hours: 6));
  return !utc.isBefore(start) && utc.isBefore(end);
}

/// Toronto's UTC offset in hours at the instant [instant].
int torontoOffsetHours(DateTime instant) =>
    _isTorontoDst(instant.toUtc()) ? -4 : -5;

/// The wall-clock time in Toronto at the instant [instant],
/// as a naive (timezone-free) DateTime — so calendar math
/// (weekday, date, midnight) on the result is Toronto
/// calendar math.
DateTime torontoWallTime(DateTime instant) {
  final shifted = instant.toUtc().add(
      Duration(hours: torontoOffsetHours(instant)));
  return DateTime(
    shifted.year,
    shifted.month,
    shifted.day,
    shifted.hour,
    shifted.minute,
    shifted.second,
    shifted.millisecond,
    shifted.microsecond,
  );
}

/// Toronto wall-clock "now".
DateTime torontoNow() => torontoWallTime(DateTime.now());

/// The Toronto calendar date (yyyy-MM-dd) of the instant
/// [instant]. This is what [TimeEntry.date] stores.
String torontoDateStr(DateTime instant) => _dateStr(torontoWallTime(instant));

/// The UTC instant of midnight Toronto on the Toronto wall
/// date [wallDate] (a naive Toronto date, e.g. a week start).
DateTime torontoMidnightUtc(DateTime wallDate) {
  final midnight = DateTime(wallDate.year, wallDate.month, wallDate.day);
  // EST guess first (UTC-5); if that instant is actually in
  // DST, midnight was UTC-4.
  final estGuess = midnight.add(const Duration(hours: 5));
  if (torontoOffsetHours(estGuess) == -4) {
    return midnight.add(const Duration(hours: 4));
  }
  return estGuess;
}

DateTime weekStartFor(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return d.subtract(Duration(days: d.weekday - 1));
}

DateTime weekEndFor(DateTime weekStart) =>
    weekStart.add(const Duration(days: 6));

String _dateStr(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// The portion of [entry]'s hours falling inside the absolute
/// interval [rangeStartUtc]–[rangeEndUtc] (UTC instants).
/// An open entry counts its live time so far (to [now], or
/// DateTime.now()). When the server has stored `hours` for
/// the entry, that total is distributed across the entry in
/// proportion to time, so an entry wholly inside a range
/// totals exactly its stored hours and a split entry's parts
/// add up to them; without stored hours the portion is the
/// raw clock time. A zero-length entry contributes 0.
double entryHoursInRange(
  TimeEntry entry,
  DateTime rangeStartUtc,
  DateTime rangeEndUtc, {
  DateTime? now,
}) {
  final start = entry.clockInAt.toUtc();
  final end = (entry.clockOutAt ?? now ?? DateTime.now()).toUtc();
  if (!end.isAfter(start)) return 0;
  final overlapStart = start.isAfter(rangeStartUtc) ? start : rangeStartUtc;
  final overlapEnd = end.isBefore(rangeEndUtc) ? end : rangeEndUtc;
  if (!overlapEnd.isAfter(overlapStart)) return 0;
  final overlapMs = overlapEnd.difference(overlapStart).inMilliseconds;
  final totalMs = end.difference(start).inMilliseconds;
  if (entry.hours != null && totalMs > 0) {
    return entry.hours! * overlapMs / totalMs;
  }
  return overlapMs / 3600000;
}

/// The portion of [entry]'s hours falling in the
/// Monday–Sunday week starting at [weekStart] (a Toronto
/// wall date). A shift crossing midnight — or the
/// Sunday/Monday boundary — is split: each week counts only
/// its own part.
double entryHoursInWeek(TimeEntry entry, DateTime weekStart) {
  final startUtc = torontoMidnightUtc(weekStart);
  return entryHoursInRange(
      entry, startUtc, startUtc.add(const Duration(days: 7)));
}

/// The portion of [entry]'s hours falling on the Toronto
/// calendar day [torontoDate] (a naive Toronto date).
double entryHoursOnTorontoDate(TimeEntry entry, DateTime torontoDate) {
  final startUtc = torontoMidnightUtc(torontoDate);
  return entryHoursInRange(
      entry, startUtc, startUtc.add(const Duration(days: 1)));
}

/// The entries with any time in the Monday–Sunday week
/// starting at [weekStart] (Toronto). An entry is in the week
/// when its clock-in/clock-out interval overlaps the week —
/// so a shift crossing midnight into Monday belongs to both
/// weeks (its hours split — see [entryHoursInWeek]), and an
/// entry is never counted wholly in its clock-in week. A
/// zero-length entry counts in the week of its Toronto
/// clock-in date. The stored `date` string is not trusted
/// here: it is device-written, and the timestamps are the
/// source of truth.
List<TimeEntry> entriesInWeek(List<TimeEntry> entries, DateTime weekStart) {
  final startUtc = torontoMidnightUtc(weekStart);
  final endUtc = startUtc.add(const Duration(days: 7));
  final nowUtc = DateTime.now().toUtc();
  final startStr = _dateStr(weekStart);
  final endStr = _dateStr(weekEndFor(weekStart));
  return entries.where((e) {
    final start = e.clockInAt.toUtc();
    final end = (e.clockOutAt ?? nowUtc);
    if (start.isBefore(endUtc) && end.isAfter(startUtc)) return true;
    final d = torontoDateStr(e.clockInAt);
    return d.compareTo(startStr) >= 0 && d.compareTo(endStr) <= 0;
  }).toList();
}

/// Week total for the profile header and the Team tiles:
/// each entry counts only the hours falling in this week
/// (split at midnight — see [entryHoursInWeek]); an entry
/// still open counts its live time so far, so the number
/// moves through the day. Flagged entries count exactly like
/// verified ones — the flag is a review marker, not a
/// deduction.
double weekTotalIncludingLive(List<TimeEntry> entries, DateTime weekStart) {
  var total = 0.0;
  for (final e in entriesInWeek(entries, weekStart)) {
    total += entryHoursInWeek(e, weekStart);
  }
  return total;
}
