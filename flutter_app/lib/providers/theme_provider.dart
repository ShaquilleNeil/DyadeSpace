import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../theme/app_theme.dart';

/// Current app theme: dark (default), light, or system (follow
/// the device). Toggled from the account sheet (avatar button,
/// top right) or the Settings screen. The choice is per-device,
/// persisted in SharedPreferences, and loaded at startup in
/// main.dart before the first frame.
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.dark);

const _themeModeKey = 'theme_mode';

/// Persists a theme choice. Fire-and-forget from the toggle —
/// the provider state is the live value, this is only the disk
/// copy for the next launch.
Future<void> saveThemeMode(ThemeMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_themeModeKey, themeModeStorageValue(mode));
}

/// Reads the saved theme choice, defaulting to dark.
Future<ThemeMode> loadThemeMode() async {
  final prefs = await SharedPreferences.getInstance();
  return themeModeFromStorage(prefs.getString(_themeModeKey));
}
