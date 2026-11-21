import 'package:flutter/material.dart';

import '../models/app_user.dart';
import '../models/task_item.dart';

/// Theme-aware colour set for DyadeSpace, delivered as a
/// [ThemeExtension] so every widget reads the palette for the
/// *current* brightness via [AppTokens.of].
///
/// The dark set is the "Midnight" theme: rich blue accent
/// (#3D7BFA) with green (#2FBF71) as the secondary accent for
/// progress and completion. The light set keeps the same blue
/// accent family, on cool off-white surfaces with dark text.
/// Where the accent is used as *text* on a light surface,
/// [accentText] is a darker blue — accent-filled buttons keep
/// [accent] with [onAccent] text in both themes.
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHover,
    required this.border,
    required this.borderStrong,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.accent,
    required this.accentMuted,
    required this.accentText,
    required this.onAccent,
    required this.danger,
    required this.dangerBorder,
    required this.statusTodo,
    required this.statusInProgress,
    required this.statusDone,
    required this.statusBlocked,
    required this.statusToConfirm,
    required this.statusPaused,
  });

  // --- Surfaces ---
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceHover;

  // --- Borders ---
  final Color border;
  final Color borderStrong;

  // --- Text ---
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;

  // --- Accent ---
  final Color accent;
  final Color accentMuted;
  final Color accentText;
  final Color onAccent;

  // --- Feedback ---
  final Color danger;
  final Color dangerBorder;

  // --- Task status ---
  final Color statusTodo;
  final Color statusInProgress;
  final Color statusDone;
  final Color statusBlocked;
  final Color statusToConfirm;
  final Color statusPaused;

  /// The dark "Midnight" palette: blue-tinted near-black
  /// surfaces, rich blue accent, green for progress/completion.
  static const dark = AppColors(
    background: Color(0xFF0A0E14),
    surface: Color(0xFF12161D),
    surfaceRaised: Color(0xFF181E28),
    surfaceHover: Color(0xFF202634),
    border: Color(0x14FFFFFF), // white 8%
    borderStrong: Color(0x24FFFFFF), // white 14%
    textPrimary: Color(0xFFF2F4F7),
    textSecondary: Color(0xFF9AA3AF),
    textTertiary: Color(0xFF6B7280),
    accent: Color(0xFF3D7BFA),
    accentMuted: Color(0x243D7BFA), // accent at 14%
    accentText: Color(0xFF6E9BFF),
    onAccent: Color(0xFF0A1120),
    danger: Color(0xFFE5737A),
    dangerBorder: Color(0xFF8A443E),
    statusTodo: Color(0xFF8B93A1),
    statusInProgress: Color(0xFF7AA2F7),
    statusDone: Color(0xFF2FBF71),
    statusBlocked: Color(0xFFE0A458),
    statusToConfirm: Color(0xFF7AA2F7),
    statusPaused: Color(0xFF9B8CE0),
  );

  /// The light palette — same blue accent family, cool off-white
  /// surfaces, dark text. Status colours are one step darker
  /// than their dark-theme twins so dots and labels keep their
  /// contrast on white. The cool base (#F5F7FA) fits the blue
  /// accent better than the old warm off-white.
  static const light = AppColors(
    background: Color(0xFFF5F7FA),
    surface: Color(0xFFFFFFFF),
    surfaceRaised: Color(0xFFEEF1F6),
    surfaceHover: Color(0xFFE3E8F0),
    border: Color(0x14000000), // black 8%
    borderStrong: Color(0x24000000), // black 14%
    textPrimary: Color(0xFF14171C),
    textSecondary: Color(0xFF5B6470),
    textTertiary: Color(0xFF8A919C),
    accent: Color(0xFF3D7BFA),
    accentMuted: Color(0x243D7BFA), // accent at 14%
    accentText: Color(0xFF1E40AF),
    onAccent: Color(0xFF0A1120),
    danger: Color(0xFFE5737A),
    dangerBorder: Color(0xFFD9776F),
    statusTodo: Color(0xFF6B7280),
    statusInProgress: Color(0xFF2B5CB8),
    statusDone: Color(0xFF2E9E6B),
    statusBlocked: Color(0xFFC07F2E),
    statusToConfirm: Color(0xFF2B5CB8),
    statusPaused: Color(0xFF7A6BC8),
  );

  /// Deterministic site-tag palette: a site keeps its colour
  /// everywhere (board, Today, My Day). Same hues in both themes.
  static const List<Color> siteTagPalette = [
    Color(0xFF4FBF8A),
    Color(0xFF4FB3BF),
    Color(0xFFD97A86),
    Color(0xFF9B8CE0),
    Color(0xFF7AA2F7),
    Color(0xFFE0A458),
  ];

  /// FNV-1a hash of [seed] into [siteTagPalette].
  static Color siteTagColorFor(String seed) {
    var hash = 2166136261;
    for (final code in seed.codeUnits) {
      hash ^= code;
      hash = (hash * 16777619) & 0xFFFFFFFF;
    }
    return siteTagPalette[hash % siteTagPalette.length];
  }

  /// Status colour for a [TaskStatus], in this theme.
  Color statusColorFor(TaskStatus status) {
    switch (status) {
      case TaskStatus.todo:
        return statusTodo;
      case TaskStatus.inProgress:
        return statusInProgress;
      case TaskStatus.blocked:
        return statusBlocked;
      case TaskStatus.toConfirm:
        return statusToConfirm;
      case TaskStatus.paused:
        return statusPaused;
      case TaskStatus.done:
        return statusDone;
    }
  }

  /// Avatar wash (bg) + glyph colour (fg) for a [UserRole].
  /// Same hues in both themes.
  ({Color bg, Color fg}) roleAvatarColors(UserRole role) {
    switch (role) {
      case UserRole.admin:
      case UserRole.manager:
        return (bg: accent.withValues(alpha: 0.18), fg: accent);
      case UserRole.worker:
        return (
          bg: const Color(0xFF4FB3BF).withValues(alpha: 0.18),
          fg: const Color(0xFF4FB3BF),
        );
      case UserRole.delivery:
        return (
          bg: const Color(0xFF9B8CE0).withValues(alpha: 0.18),
          fg: const Color(0xFF9B8CE0),
        );
    }
  }

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceHover,
    Color? border,
    Color? borderStrong,
    Color? textPrimary,
    Color? textSecondary,
    Color? textTertiary,
    Color? accent,
    Color? accentMuted,
    Color? accentText,
    Color? onAccent,
    Color? danger,
    Color? dangerBorder,
    Color? statusTodo,
    Color? statusInProgress,
    Color? statusDone,
    Color? statusBlocked,
    Color? statusToConfirm,
    Color? statusPaused,
  }) {
    return AppColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceHover: surfaceHover ?? this.surfaceHover,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      accent: accent ?? this.accent,
      accentMuted: accentMuted ?? this.accentMuted,
      accentText: accentText ?? this.accentText,
      onAccent: onAccent ?? this.onAccent,
      danger: danger ?? this.danger,
      dangerBorder: dangerBorder ?? this.dangerBorder,
      statusTodo: statusTodo ?? this.statusTodo,
      statusInProgress: statusInProgress ?? this.statusInProgress,
      statusDone: statusDone ?? this.statusDone,
      statusBlocked: statusBlocked ?? this.statusBlocked,
      statusToConfirm: statusToConfirm ?? this.statusToConfirm,
      statusPaused: statusPaused ?? this.statusPaused,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceHover: Color.lerp(surfaceHover, other.surfaceHover, t)!,
      border: Color.lerp(border, other.border, t)!,
      borderStrong: Color.lerp(borderStrong, other.borderStrong, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      accentMuted: Color.lerp(accentMuted, other.accentMuted, t)!,
      accentText: Color.lerp(accentText, other.accentText, t)!,
      onAccent: Color.lerp(onAccent, other.onAccent, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      dangerBorder: Color.lerp(dangerBorder, other.dangerBorder, t)!,
      statusTodo: Color.lerp(statusTodo, other.statusTodo, t)!,
      statusInProgress:
          Color.lerp(statusInProgress, other.statusInProgress, t)!,
      statusDone: Color.lerp(statusDone, other.statusDone, t)!,
      statusBlocked: Color.lerp(statusBlocked, other.statusBlocked, t)!,
      statusToConfirm:
          Color.lerp(statusToConfirm, other.statusToConfirm, t)!,
      statusPaused: Color.lerp(statusPaused, other.statusPaused, t)!,
    );
  }
}

/// Design tokens for DyadeSpace.
///
/// Colour values live on [AppColors] and resolve per brightness —
/// read them with [AppTokens.of] inside a build method. The
/// accent, layout and brightness-independent helpers stay static
/// here because they are identical in both themes.
class AppTokens {
  AppTokens._();

  /// The colour set for the current theme. Falls back to dark
  /// when no [AppColors] extension is registered (defensive —
  /// both app themes register one).
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? AppColors.dark;

  // --- Accent (identical in both themes) ---
  static const Color accent = Color(0xFF3D7BFA);
  static const Color accentMuted = Color(0x243D7BFA); // accent at 14%
  static const Color onAccent = Color(0xFF0A1120);

  // --- Brightness-independent helpers (same hues in both themes) ---
  static Color siteTagColorFor(String seed) =>
      AppColors.siteTagColorFor(seed);

  static ({Color bg, Color fg}) roleAvatarColors(UserRole role) =>
      AppColors.dark.roleAvatarColors(role);

  // --- Spacing / radii (identical in both themes) ---
  static const double screenPadding = 20;
  static const double cardRadius = 16;
  static const double inputRadius = 12;
  static const double chipRadius = 8;
  static const double buttonRadius = 14;
}
