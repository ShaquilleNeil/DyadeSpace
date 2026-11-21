/// Hours as "7 h 32 min" instead of a decimal ("7.53 h") so the
/// minutes are visible, not hidden in a fraction. "h" and "min"
/// read the same in English, French and Spanish, so no new
/// strings are needed. Stored values are already rounded to 2
/// decimals (about 36 seconds), so converting back loses at
/// most a minute.
String formatHoursMinutes(double hours) {
  final totalMinutes = (hours * 60).round();
  if (totalMinutes <= 0) return '0 min';
  final h = totalMinutes ~/ 60;
  final m = totalMinutes % 60;
  if (h == 0) return '$m min';
  if (m == 0) return '$h h';
  return '$h h $m min';
}
