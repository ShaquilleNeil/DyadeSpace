import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_strings.dart';

/// Current app language: 'en', 'fr' or 'es'. Toggled from the
/// account sheet (avatar button, top right) or the Settings
/// screen. The choice is per-device, persisted in
/// SharedPreferences, and loaded at startup in main.dart before
/// the first frame. When the user has never picked a language,
/// the phone's language is used instead ('fr' for any French
/// variant, 'es' for any Spanish variant, English otherwise).
/// (Also mirrored on the user profile as AppUser.language at sign-up;
/// this provider is the live, in-app switch.)
final localeProvider = StateProvider<String>((ref) => 'en');

const _languageKey = 'app_language';

final stringsProvider = Provider<AppStrings>(
  (ref) => AppStrings(ref.watch(localeProvider)),
);

/// Persists a language choice. Fire-and-forget from the toggle —
/// the provider state is the live value, this is only the disk
/// copy for the next launch.
Future<void> saveLanguage(String lang) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_languageKey, lang);
}

/// Reads the saved language choice; when none was ever picked,
/// falls back to the phone's language ('fr' for any French
/// variant, 'es' for any Spanish variant, English for
/// everything else).
Future<String> loadLanguage() async {
  final prefs = await SharedPreferences.getInstance();
  final saved = prefs.getString(_languageKey);
  if (saved == 'en') return 'en';
  if (saved == 'fr') return 'fr';
  if (saved == 'es') return 'es';
  final code = PlatformDispatcher.instance.locale.languageCode;
  if (code == 'fr') return 'fr';
  if (code == 'es') return 'es';
  return 'en';
}
