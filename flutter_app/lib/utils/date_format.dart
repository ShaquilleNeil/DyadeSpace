import 'package:intl/intl.dart';

/// User-facing date formatting, in the user's language.
///
/// Every display date in the app must go through here (or a
/// caller passing the same locale) instead of a bare
/// `DateFormat(pattern)` — a bare DateFormat always renders
/// month/weekday names in English, whatever language the app
/// is in. [locale] is the app language code ('en', 'fr', 'es');
/// anything else falls back to 'en'. If the locale's date data
/// is not loaded, the format falls back to English rather
/// than throwing — a wrong-language date beats a crash.
///
/// Patterns that are numbers only ('yyyy-MM-dd', 'HH:mm')
/// need no locale and are left as bare DateFormat calls at
/// their sites: they render identically in every language.
String _normalizeLocale(String? locale) {
  if (locale == null) return 'en';
  if (locale.startsWith('fr')) return 'fr';
  if (locale.startsWith('es')) return 'es';
  return 'en';
}

String _format(String pattern, DateTime date, String? locale) {
  final lang = _normalizeLocale(locale);
  try {
    return DateFormat(pattern, lang).format(date);
  } catch (_) {
    // Locale data not loaded (e.g. a test without
    // initializeDateFormatting): English instead of a crash.
    return DateFormat(pattern, 'en').format(date);
  }
}

/// 'Tue Nov 18, 2026' / 'mar. 18 nov. 2026' — the standard
/// full display date (date fields, report titles, run dates).
String formatDisplayDate(DateTime date, String? locale) =>
    _format('EEE MMM d, yyyy', date, locale);

/// 'Nov 18, 2026' — medium date, no weekday.
String formatMediumDate(DateTime date, String? locale) =>
    _format('MMM d, yyyy', date, locale);

/// 'Nov 18' / 'Tue Nov 18' — short date for list rows.
String formatShortDate(DateTime date, String? locale) =>
    _format('MMM d', date, locale);

/// 'Tue Nov 18' — short date with weekday.
String formatShortDateWithWeekday(DateTime date, String? locale) =>
    _format('EEE MMM d', date, locale);

/// 'Tue' — short weekday name (week headers, day columns).
String formatWeekdayShort(DateTime date, String? locale) =>
    _format('EEE', date, locale);

/// 'Tuesday, Nov 18' — long date for headers and report rows.
String formatFullDate(DateTime date, String? locale) =>
    _format('EEEE, MMM d', date, locale);

/// 'Tue, Nov 18' — long date with a comma (web day labels).
String formatFullDateComma(DateTime date, String? locale) =>
    _format('EEE, MMM d', date, locale);
