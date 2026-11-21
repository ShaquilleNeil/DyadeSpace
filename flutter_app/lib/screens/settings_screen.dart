import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/theme_provider.dart';
import '../services/auto_clock_service.dart';
import '../services/report_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/member_tile.dart';
import 'privacy_screen.dart';
import 'worker_profile_screen.dart';

/// Settings, reached from the profile sheet (avatar button).
/// Sections: appearance (theme), language, notification
/// toggles, the end-of-day report (admin/manager only),
/// account, and app info. The theme and language controls
/// write the same providers as the profile sheet's toggles,
/// so both stay in sync. Notification toggles live on the
/// user doc (`notifPrefs`, all on by default) and the Cloud
/// Functions read them before sending each type.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: const SettingsBody(),
    );
  }
}

/// The settings content without its own Scaffold, so the web
/// control center can embed it in its Settings view (same
/// controls, same providers, one source of truth).
class SettingsBody extends ConsumerWidget {
  const SettingsBody({super.key});

  /// Fallback while the real version loads (and if it never
  /// does) — keep in step with pubspec.yaml.
  static const _appVersion = '1.0.0 (1)';

  /// Loaded once: PackageInfo.fromPlatform() reads the
  /// version + build number from pubspec.yaml at build time.
  static final _packageInfo = PackageInfo.fromPlatform();

  /// Notification-pref write. Errors used to be swallowed:
  /// the toggle is driven by the user-doc stream, so a failed
  /// write left the switch showing the old value with no
  /// explanation. Now the failure surfaces as a snackbar and
  /// the switch (still bound to the unchanged stream value)
  /// visibly stays where it was.
  Future<void> _setPref(
      BuildContext context, WidgetRef ref, AppUser me, String key, bool value) async {
    final next = Map<String, bool>.from(me.notifPrefs)..[key] = value;
    try {
      await ref
          .read(authServiceProvider)
          .updateNotifPrefs(uid: me.id, prefs: next);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(ref.read(stringsProvider).settingsSaveFailed)),
        );
      }
    }
  }

  /// End-of-day channel/time writes, with the same
  /// surface-the-failure rule as _setPref (both used to be
  /// fire-and-forget, so a failed save looked saved).
  Future<void> _saveEodChannel(
      BuildContext context, WidgetRef ref, String channel) async {
    try {
      await ref.read(reportServiceProvider).saveEodChannel(channel);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(ref.read(stringsProvider).settingsSaveFailed)),
        );
      }
    }
  }

  Future<void> _saveEodTime(
      BuildContext context, WidgetRef ref, String time) async {
    try {
      await ref.read(reportServiceProvider).saveEodTime(time);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(ref.read(stringsProvider).settingsSaveFailed)),
        );
      }
    }
  }

  /// Self-service account deletion (Settings → Account). Two
  /// explicit steps: this row, then the confirmation dialog's
  /// delete button — no single tap ever deletes. The server
  /// function removes the Auth user, the profile doc, the
  /// photo and the notifications; time entries, tasks and
  /// chat messages stay (see the dialog text). On success the
  /// notice is armed for the sign-in screen and the local
  /// session is signed out; on failure the error shows and
  /// the user stays signed in.
  Future<void> _deleteAccount(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final tokens = AppTokens.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteAccountTitle),
        content: Text(s.deleteAccountBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            // The theme gives every FilledButton an infinite minimum
            // width — bound it to its content (same fix as the
            // topbar button).
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              backgroundColor: tokens.danger,
            ),
            child: Text(s.deleteMyAccount),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(authServiceProvider).deleteMyAccount();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.deleteAccountFailed)),
        );
      }
      return;
    }
    ref.read(deletedAccountNoticeProvider.notifier).state =
        s.accountDeleted;
    await ref.read(authServiceProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final lang = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final channel =
        ref.watch(_eodChannelProvider).valueOrNull ?? 'both';
    final emailReady =
        ref.watch(_eodEmailReadyProvider).valueOrNull ?? false;
    final eodTime =
        ref.watch(_eodTimeProvider).valueOrNull ?? '18:00';

    return me == null
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: [
                _sectionLabel(context, s.appearance),
                _card(
                  context,
                  tokens,
                  SegmentedButton<ThemeMode>(
                    segments: [
                      ButtonSegment<ThemeMode>(
                          value: ThemeMode.light,
                          label: Text(s.themeLight)),
                      ButtonSegment<ThemeMode>(
                          value: ThemeMode.dark,
                          label: Text(s.themeDark)),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      final next = selection.first;
                      ref.read(themeModeProvider.notifier).state = next;
                      unawaited(saveThemeMode(next));
                    },
                  ),
                ),
                const SizedBox(height: 20),
                _sectionLabel(context, s.language),
                _card(
                  context,
                  tokens,
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(
                          value: 'en', label: Text('EN')),
                      ButtonSegment<String>(
                          value: 'fr', label: Text('FR')),
                      ButtonSegment<String>(
                          value: 'es', label: Text('ES')),
                    ],
                    selected: {lang},
                    onSelectionChanged: (selection) {
                      if (selection.isEmpty) return;
                      final next = selection.first;
                      ref.read(localeProvider.notifier).state = next;
                      unawaited(saveLanguage(next));
                    },
                  ),
                ),
                // Auto clock-in is mobile-only: Workmanager and
                // background location do not exist on web, and
                // the web control center embeds this same body.
                if (!kIsWeb) ...[
                  const SizedBox(height: 20),
                  _sectionLabel(context, s.clockIn),
                  _card(
                    context,
                    tokens,
                    _AutoClockTile(me: me),
                  ),
                ],
                const SizedBox(height: 20),
                _sectionLabel(context, s.notifications),
                _card(
                  context,
                  tokens,
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _prefTile(
                        context,
                        s.notifTaskAssigned,
                        me.notifEnabled('taskAssigned'),
                        (v) => _setPref(context, ref, me, 'taskAssigned', v),
                      ),
                      _prefTile(
                        context,
                        s.notifClockInOut,
                        me.notifEnabled('clockInOut'),
                        (v) => _setPref(context, ref, me, 'clockInOut', v),
                      ),
                      _prefTile(
                        context,
                        s.notifChatMessages,
                        me.notifEnabled('chatMessages'),
                        (v) => _setPref(context, ref, me, 'chatMessages', v),
                      ),
                      _prefTile(
                        context,
                        s.notifEodReport,
                        me.notifEnabled('eodReport'),
                        (v) => _setPref(context, ref, me, 'eodReport', v),
                      ),
                    ],
                  ),
                ),
                if (me.isAdminOrManager) ...[
                  const SizedBox(height: 20),
                  _sectionLabel(context, s.reports),
                  _card(
                    context,
                    tokens,
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.sendChannel,
                          style: TextStyle(
                            fontSize: 13,
                            color: tokens.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        SegmentedButton<String>(
                          segments: [
                            ButtonSegment<String>(
                                value: 'push',
                                label: Text(s.channelPush)),
                            // Email options stay hidden until the
                            // email transport exists (see
                            // _eodEmailReadyProvider): the stored
                            // channel value itself is untouched.
                            if (emailReady)
                              ButtonSegment<String>(
                                  value: 'email',
                                  label: Text(s.channelEmail)),
                            if (emailReady)
                              ButtonSegment<String>(
                                  value: 'both',
                                  label: Text(s.channelBoth)),
                          ],
                          selected: {emailReady ? channel : 'push'},
                          onSelectionChanged: (selection) {
                            if (selection.isEmpty) return;
                            unawaited(_saveEodChannel(
                                context, ref, selection.first));
                          },
                        ),
                        if (!emailReady) ...[
                          const SizedBox(height: 8),
                          Text(
                            s.eodEmailUnavailable,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(s.eodReportTime),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                eodTime,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: tokens.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(Icons.chevron_right,
                                  size: 20, color: tokens.textTertiary),
                            ],
                          ),
                          onTap: () async {
                            final parts = eodTime.split(':');
                            final initial = TimeOfDay(
                              hour: int.tryParse(
                                      parts.isNotEmpty ? parts[0] : '') ??
                                  18,
                              minute: int.tryParse(parts.length > 1
                                      ? parts[1]
                                      : '') ??
                                  0,
                            );
                            final picked = await showTimePicker(
                              context: context,
                              initialTime: initial,
                            );
                            if (picked == null) return;
                            final time =
                                '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                            if (!context.mounted) return;
                            await _saveEodTime(context, ref, time);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                _sectionLabel(context, s.privacyNoticeTitle),
                _card(
                  context,
                  tokens,
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.privacyNoticeBody,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: tokens.textSecondary,
                        ),
                      ),
                      const Divider(height: 24),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.privacy_tip_outlined),
                        title: Text(s.privacyPolicy),
                        trailing: Icon(Icons.chevron_right,
                            size: 20, color: tokens.textTertiary),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const PrivacyScreen(),
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _sectionLabel(context, s.account),
                _card(
                  context,
                  tokens,
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: RoleAvatar(
                          name: me.name,
                          role: me.role,
                          size: 40,
                          photoUrl: me.photoUrl,
                        ),
                        title: Text(me.name),
                        subtitle: Text(
                          '${roleLabel(s, me.role)} · ${me.email}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.person_outline),
                        title: Text(s.viewProfile),
                        trailing: Icon(Icons.chevron_right,
                            size: 20, color: tokens.textTertiary),
                        onTap: () {
                          HapticFeedback.lightImpact();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  WorkerProfileScreen(user: me),
                            ),
                          );
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.logout,
                            color: tokens.danger),
                        title: Text(
                          s.signOut,
                          style: TextStyle(color: tokens.danger),
                        ),
                        onTap: () async {
                          HapticFeedback.lightImpact();
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text(s.confirmSignOut),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: Text(s.cancel),
                                ),
                                FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, true),
                                  // The theme gives every FilledButton an infinite minimum
                                  // width — bound it to its content (same fix as the
                                  // topbar button).
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(0, 52),
                                  ),
                                  child: Text(s.confirm),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await ref
                                .read(authServiceProvider)
                                .signOut();
                          }
                        },
                      ),
                      const Divider(height: 1),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(Icons.delete_outline,
                            color: tokens.danger),
                        title: Text(
                          s.deleteMyAccount,
                          style: TextStyle(color: tokens.danger),
                        ),
                        onTap: () => _deleteAccount(context, ref),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _sectionLabel(context, s.appTitle),
                _card(
                  context,
                  tokens,
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(s.appVersion),
                    trailing: FutureBuilder<PackageInfo>(
                      future: _packageInfo,
                      builder: (context, snap) {
                        final info = snap.data;
                        final text = info == null
                            ? _appVersion
                            : '${info.version} (${info.buildNumber})';
                        return Text(
                          text,
                          style: TextStyle(
                            fontSize: 14,
                            color: tokens.textSecondary,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _card(BuildContext context, AppColors tokens, Widget child) {
    // A Material, not a decorated Container: ListTile paints
    // its background and ink splashes on the nearest Material
    // ancestor, and a Container with a background colour in
    // between hides them — Flutter reports that as an error
    // in debug builds. The Material carries the same surface
    // colour, rounded corners and border, so it looks
    // identical and the ListTiles inside it work.
    return Material(
      color: tokens.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.cardRadius),
        side: BorderSide(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: child,
      ),
    );
  }

  Widget _prefTile(
    BuildContext context,
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      value: value,
      onChanged: (v) {
        HapticFeedback.lightImpact();
        onChanged(v);
      },
    );
  }
}

/// Auto clock-in toggle (mobile only — see the kIsWeb guard
/// where it is used). Opt-in: turning it on first shows the
/// Law 25 background-location consent, then requests location
/// "Always". Denied permission leaves the toggle off with an
/// explanation; the worker can enable it later from the phone
/// Settings. The on/off state lives in SharedPreferences (a
/// per-device setting — background monitoring is per device),
/// and turning it on registers the ~15-minute Workmanager
/// check (see AutoClockService).
class _AutoClockTile extends ConsumerStatefulWidget {
  final AppUser me;
  const _AutoClockTile({required this.me});

  @override
  ConsumerState<_AutoClockTile> createState() => _AutoClockTileState();
}

class _AutoClockTileState extends ConsumerState<_AutoClockTile> {
  bool _enabled = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final enabled = await AutoClockService.isEnabled();
    if (mounted) setState(() => _enabled = enabled);
  }

  Future<void> _onChanged(bool value) async {
    final s = ref.read(stringsProvider);
    if (_busy) return;
    if (!value) {
      setState(() => _busy = true);
      try {
        await AutoClockService.setEnabled(false);
      } catch (_) {
        // A failed disable used to leave _busy true forever,
        // so the toggle stayed disabled with no feedback.
        // Restore the toggle and say so instead.
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.settingsSaveFailed)),
        );
        return;
      }
      if (!mounted) return;
      setState(() {
        _enabled = false;
        _busy = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.autoClockDisabled)),
      );
      return;
    }
    // Turning on: Law 25 background consent first.
    final allowed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.autoClockConsentTitle),
        content: Text(s.autoClockConsentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.consentNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            // The theme gives every FilledButton an infinite minimum
            // width — bound it to its content (same fix as the
            // topbar button).
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
            ),
            child: Text(s.consentAllow),
          ),
        ],
      ),
    );
    if (allowed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AutoClockService.saveConsent(true);
      // "Always" location: on Android 11+ the system may only
      // offer it in the phone Settings — a denial here is not
      // fatal, the snackbar explains where to turn it on.
      var status = await Permission.locationAlways.status;
      if (!status.isGranted) {
        status = await Permission.locationAlways.request();
      }
      if (!status.isGranted) {
        if (!mounted) return;
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.autoClockPermissionDenied)),
        );
        return;
      }
      await AutoClockService.setEnabled(true, uid: widget.me.id);
    } catch (_) {
      // Same stuck-toggle guard as the disable path: _busy is
      // always restored and the failure is shown.
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.settingsSaveFailed)),
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _enabled = true;
      _busy = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.autoClockEnabled)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(s.autoClockInTitle),
      subtitle: Text(s.autoClockInSubtitle),
      value: _enabled,
      onChanged: _busy ? null : _onChanged,
    );
  }
}

/// The end-of-day send channel (admin only — the Reports
/// screen's send controls share this provider shape).
final _eodChannelProvider = StreamProvider<String>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null || !me.isAdminOrManager) {
    return Stream.value(ReportService.eodChannelDefault);
  }
  return ref.watch(reportServiceProvider).watchEodChannel();
});

/// Whether the end-of-day email transport exists yet:
/// `settings/eodReport.emailTransportReady`, set server-side
/// once the Firebase Trigger Email extension is installed.
/// Missing doc/field means false — the email/both channel
/// options stay hidden until then (the stored channel value
/// itself is never changed by hiding them).
final _eodEmailReadyProvider = StreamProvider<bool>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null || !me.isAdminOrManager) {
    return Stream.value(false);
  }
  return FirebaseFirestore.instance
      .collection('settings')
      .doc('eodReport')
      .snapshots()
      .map((snap) => snap.data()?['emailTransportReady'] as bool? ?? false);
});

/// The end-of-day send time ("HH:mm", Toronto time).
final _eodTimeProvider = StreamProvider<String>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null || !me.isAdminOrManager) {
    return Stream.value(ReportService.eodTimeDefault);
  }
  return ref.watch(reportServiceProvider).watchEodTime();
});
