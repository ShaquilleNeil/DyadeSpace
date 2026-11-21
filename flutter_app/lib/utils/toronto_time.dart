/// America/Toronto wall-clock helpers, in pure Dart (the app has
/// no timezone database dependency).
///
/// The server computes every report/automation date in Toronto
/// time; a device in another timezone must agree with it, so
/// client-side report dates are derived here instead of from
/// the device-local clock. Toronto is UTC-5 (EST) in winter and
/// UTC-4 (EDT) in summer: DST runs from the second Sunday of
/// March at 07:00 UTC to the first Sunday of November at
/// 06:00 UTC.

/// The UTC offset in minutes for Toronto at this UTC instant.
int torontoOffsetMinutes(DateTime utcInstant) {
  final utc = utcInstant.toUtc();
  final year = utc.year;
  // Second Sunday of March, 07:00 UTC (02:00 local -> 03:00).
  final marchFirst = DateTime.utc(year, 3, 1);
  final firstSundayMarch = 1 + ((7 - marchFirst.weekday) % 7);
  final dstStart = DateTime.utc(year, 3, firstSundayMarch + 7, 7);
  // First Sunday of November, 06:00 UTC (02:00 local -> 01:00).
  final novFirst = DateTime.utc(year, 11, 1);
  final firstSundayNov = 1 + ((7 - novFirst.weekday) % 7);
  final dstEnd = DateTime.utc(year, 11, firstSundayNov, 6);
  final inDst =
      !utc.isBefore(dstStart) && utc.isBefore(dstEnd);
  return inDst ? -240 : -300;
}

/// Toronto wall-clock components of an instant, as a
/// (year, month, day) record.
({int year, int month, int day}) torontoDateParts(DateTime instant) {
  final shifted =
      instant.toUtc().add(Duration(minutes: torontoOffsetMinutes(instant)));
  return (year: shifted.year, month: shifted.month, day: shifted.day);
}

/// Toronto calendar date of an instant, `yyyy-MM-dd` — the
/// same id the Cloud Functions use for dayReports.
String torontoDateId(DateTime instant) {
  final p = torontoDateParts(instant);
  final m = p.month.toString().padLeft(2, '0');
  final d = p.day.toString().padLeft(2, '0');
  return '${p.year}-$m-$d';
}

/// True when [instant]'s Toronto calendar day is the Toronto
/// day [year]/[month]/[day].
bool isSameTorontoDay(DateTime instant, int year, int month, int day) {
  final p = torontoDateParts(instant);
  return p.year == year && p.month == month && p.day == day;
}
