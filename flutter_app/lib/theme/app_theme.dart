import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_tokens.dart';

/// The DyadeSpace themes: one light, one dark, same premium
/// style. Both are built from the same [AppColors] parameter, so
/// the two themes can never drift apart in structure — only the
/// palette differs. [buildAppTheme] is the light theme (the
/// MaterialApp `theme` slot); [buildAppDarkTheme] is the dark
/// theme (the `darkTheme` slot). Manrope is the display font,
/// with tabular figures everywhere so counts and times line up
/// in lists.
TextTheme _buildTextTheme(AppColors c) {
  final base = GoogleFonts.manropeTextTheme(
    TextTheme(
      titleLarge: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: c.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: c.textTertiary,
      ),
      bodyMedium: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: c.textSecondary,
      ),
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: c.textTertiary,
      ),
      labelLarge: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: c.textPrimary,
      ),
    ),
  );

  TextStyle tabular(TextStyle? style) =>
      (style ?? const TextStyle()).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  return base.copyWith(
    titleLarge: tabular(base.titleLarge),
    titleMedium: tabular(base.titleMedium),
    titleSmall: tabular(base.titleSmall),
    bodyMedium: tabular(base.bodyMedium),
    bodySmall: tabular(base.bodySmall),
    labelLarge: tabular(base.labelLarge),
  );
}

ThemeData _buildTheme(AppColors c, Brightness brightness) {
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    extensions: [c],
    colorScheme: ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.accentMuted,
      onPrimaryContainer: c.accentText,
      secondary: c.accent,
      onSecondary: c.onAccent,
      error: c.danger,
      onError: Colors.white,
      surface: c.surface,
      onSurface: c.textPrimary,
      onSurfaceVariant: c.textSecondary,
      surfaceContainerLowest: c.background,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surfaceRaised,
      surfaceContainerHigh: c.surfaceHover,
      surfaceContainerHighest: c.surfaceHover,
      surfaceDim: c.background,
      surfaceBright: c.surfaceRaised,
      outline: c.border,
      outlineVariant: c.borderStrong,
    ),
    scaffoldBackgroundColor: c.background,
    canvasColor: c.surfaceRaised,
    textTheme: _buildTextTheme(c),
    appBarTheme: AppBarThemeData(
      backgroundColor: c.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: c.textPrimary,
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: c.textPrimary,
      ),
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.cardRadius),
        side: BorderSide(color: c.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceRaised,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.inputRadius),
        borderSide: BorderSide(color: c.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.inputRadius),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.inputRadius),
        borderSide: BorderSide(color: c.accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppTokens.inputRadius),
        borderSide: BorderSide(color: c.danger),
      ),
      labelStyle: TextStyle(
        fontSize: 14,
        color: c.textSecondary,
      ),
      hintStyle: TextStyle(
        fontSize: 14,
        color: c.textTertiary,
      ),
      floatingLabelStyle: TextStyle(
        fontSize: 13,
        color: c.textSecondary,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.textPrimary,
        side: BorderSide(color: c.borderStrong),
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.buttonRadius),
        ),
        textStyle: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.textSecondary,
        textStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      trackColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.selected)
            ? c.accent
            : c.borderStrong;
      }),
      thumbColor: WidgetStateProperty.resolveWith<Color?>((states) {
        return states.contains(WidgetState.selected)
            ? c.onAccent
            : c.textTertiary;
      }),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      indicatorColor: c.accentMuted,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? c.accentText : c.textTertiary,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          color: selected ? c.accentText : c.textTertiary,
        );
      }),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: TextStyle(
        fontSize: 14,
        color: c.textPrimary,
      ),
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surfaceRaised),
        elevation: const WidgetStatePropertyAll<double>(6.0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surfaceRaised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      titleTextStyle: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: c.textPrimary,
      ),
      contentTextStyle: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: c.textSecondary,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(16),
        ),
      ),
      showDragHandle: true,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surfaceRaised,
      contentTextStyle: TextStyle(
        fontSize: 14,
        color: c.textPrimary,
      ),
      actionTextColor: c.accentText,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceRaised,
      side: BorderSide(color: c.border),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: c.textSecondary,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.chipRadius),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    ),
    dividerTheme: DividerThemeData(
      color: c.border,
      thickness: 1,
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.accent,
      foregroundColor: c.onAccent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.buttonRadius),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.accent,
    ),
  );
}

/// The light theme — same premium style, warm off-white surfaces.
ThemeData buildAppTheme() => _buildTheme(AppColors.light, Brightness.light);

/// The dark theme — the redesign as shipped, unchanged.
ThemeData buildAppDarkTheme() =>
    _buildTheme(AppColors.dark, Brightness.dark);

/// Theme choices the user can pick, as stored in
/// SharedPreferences (see theme_provider.dart): 'light',
/// 'dark', or 'system' (follow the device). The MaterialApp
/// already takes the mode straight through (`themeMode` in
/// app.dart), so [ThemeMode.system] follows the device with
/// no further wiring — the provider just has to be able to
/// store and load it.
ThemeMode themeModeFromStorage(String? value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'system':
      return ThemeMode.system;
    case 'dark':
    default:
      // Unknown / never saved: dark, the long-standing default.
      return ThemeMode.dark;
  }
}

/// The stored string for a theme choice. Round-trips with
/// [themeModeFromStorage].
String themeModeStorageValue(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.light:
      return 'light';
    case ThemeMode.system:
      return 'system';
    case ThemeMode.dark:
      return 'dark';
  }
}

/// The one card shape used across the app (task cards, run stops,
/// report rows): subtle top-to-bottom gradient, [AppTokens.cardRadius]
/// corners, thin border. Kept as a top-level function so existing
/// call sites keep working unchanged.
BoxDecoration appCardDecoration(
  BuildContext context, {
  Color? borderColor,
  double borderWidth = 1,
}) {
  final tokens = AppTokens.of(context);
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [tokens.surfaceRaised, tokens.surface],
    ),
    borderRadius: BorderRadius.circular(AppTokens.cardRadius),
    border: Border.all(
      color: borderColor ?? tokens.border,
      width: borderWidth,
    ),
  );
}
