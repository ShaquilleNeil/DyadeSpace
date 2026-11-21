import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_strings.dart';
import '../models/app_user.dart';
import '../models/time_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/notification_provider.dart';
import '../providers/notifications_provider.dart';
import '../providers/photo_queue_provider.dart';
import '../providers/push_navigation_provider.dart';
import '../providers/theme_provider.dart';
import '../providers/time_entries_provider.dart';
import '../services/auto_clock_service.dart';
import '../services/route_tracking_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/clock_in_button.dart';
import '../widgets/member_tile.dart';
import '../widgets/notifications_sheet.dart';
import '../widgets/skeleton_card.dart';
import 'chat_list_screen.dart';
import 'delivery/run_screen.dart';
import 'manager/board_screen.dart';
import 'manager/people_screen.dart';
import 'manager/reports_screen.dart';
import 'settings_screen.dart';
import 'worker/my_day_screen.dart';
import 'worker/my_history_screen.dart';

/// Bottom-navigation shell. Which tabs exist depends on the role:
/// - admin/manager: Board, Reports, Team, Chats (the old
///   Today tab lives on as the Board's Today filter; the old
///   By person tab was merged into Team in Nov 2026 — tap a
///   person there to see their tasks + clock-in history)
/// - worker: My Day, History, Chats
/// - delivery: Run, My Day, Chats (a driver is a worker with a
///   route - they can also be assigned tasks like anyone else)
///
/// The AppBar shows the current tab's title. The bell (top right)
/// opens the notifications sheet; the account sheet (avatar button)
/// holds the language and theme toggles and sign-out. The Chats
/// tab carries an unread badge, like the bell.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // Auto clock-in also checks on every foreground/resume:
    // the ~15-minute background tick is the backstop, the
    // resume check is what makes arrival detection feel
    // quick when the worker opens the app on site.
    _lifecycleListener = AppLifecycleListener(
      onResume: () => unawaited(AutoClockService().checkAndUpdate()),
    );
    // Resume the route trail if the app opens while clocked
    // in (covers auto clock-ins that fired while closed),
    // and run one auto-clock check at startup.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final open = ref.read(openTimeEntryProvider).valueOrNull;
      if (open != null) {
        final s = ref.read(stringsProvider);
        unawaited(RouteTrackingService.ensureRunning(
          entryId: open.id,
          notificationTitle: s.trackingNotificationTitle,
          notificationText: s.trackingNotificationText,
        ));
      }
      unawaited(AutoClockService().checkAndUpdate());
    });
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  void _showAccountSheet(BuildContext context, AppUser user, AppStrings s,
      String lang, ThemeMode themeMode) {
    final tokens = AppTokens.of(context);
    showModalBottomSheet<void>(
      context: context,
      // Scroll-controlled + scrollable content: without this the
      // sheet is capped at 9/16 of the screen height and the
      // account sheet overflows by ~27px on his phone, cutting
      // off the Sign out button. With the cap lifted the sheet
      // sizes to its content; the scroll view covers any shorter
      // screen or larger font scale.
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                RoleAvatar(
                    name: user.name,
                    role: user.role,
                    size: 56,
                    photoUrl: user.photoUrl),
                const SizedBox(height: 12),
                Text(
                  user.name,
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  roleLabel(s, user.role).toUpperCase(),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: tokens.textTertiary),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: Text(s.settings),
                  trailing: Icon(Icons.chevron_right,
                      size: 20, color: tokens.textTertiary),
                  onTap: () {
                    HapticFeedback.lightImpact();
                    Navigator.of(sheetContext).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SettingsScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment<String>(value: 'en', label: Text('EN')),
                    ButtonSegment<String>(value: 'fr', label: Text('FR')),
                    ButtonSegment<String>(value: 'es', label: Text('ES')),
                  ],
                  selected: {lang},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    final value = selection.first;
                    // Close the sheet BEFORE the app-wide rebuild:
                    // the sheet's widgets depend on Theme and
                    // Localizations, and flipping the language
                    // rebuilds MaterialApp and notifies those
                    // InheritedWidgets. If the sheet is still
                    // mounted when the notification lands, the
                    // framework asserts on the stale dependent.
                    // Apply the change on the next frame, once the
                    // sheet is unmounted.
                    Navigator.of(sheetContext).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      ref.read(localeProvider.notifier).state = value;
                      unawaited(saveLanguage(value));
                    });
                  },
                ),
                const SizedBox(height: 12),
                SegmentedButton<ThemeMode>(
                  segments: [
                    ButtonSegment<ThemeMode>(
                        value: ThemeMode.light, label: Text(s.themeLight)),
                    ButtonSegment<ThemeMode>(
                        value: ThemeMode.dark, label: Text(s.themeDark)),
                  ],
                  selected: {themeMode},
                  onSelectionChanged: (selection) {
                    if (selection.isEmpty) return;
                    final value = selection.first;
                    // Same as the language toggle above: close the
                    // sheet first, apply the theme change on the
                    // next frame once the sheet is unmounted, so no
                    // stale dependent is left when Theme notifies.
                    Navigator.of(sheetContext).pop();
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (!mounted) return;
                      ref.read(themeModeProvider.notifier).state = value;
                      unawaited(saveThemeMode(value));
                    });
                  },
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: TextButton.icon(
                    icon: const Icon(Icons.logout),
                    label: Text(s.signOut),
                    style: TextButton.styleFrom(foregroundColor: tokens.danger),
                    onPressed: () async {
                      Navigator.of(sheetContext).pop();
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Text(s.confirmSignOut),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(s.cancel),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: Text(s.confirm),
                            ),
                          ],
                        ),
                      );
                      if (ok == true && mounted) {
                        ref.read(authServiceProvider).signOut();
                      }
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Chats tab icon with the unread badge (count of
  /// conversations with unread messages), mirroring the bell.
  Widget _chatIcon(int unread) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        const Icon(Icons.chat_bubble_outline),
        if (unread > 0)
          Positioned(
            right: -6,
            top: -4,
            child: Container(
              constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: const BoxDecoration(
                color: AppTokens.accent,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTokens.onAccent,
                ),
              ),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Session wiring that used to live in app.dart: FCM topic
    // sync, the offline photo queue drain, and push-tap routing.
    // HomeShell only ever builds while signed in (app.dart shows
    // it only then), so this fires exactly as before. Phone-only:
    // these providers pull in dart:io (photo queue) and FCM
    // navigation, so app.dart must not watch them on web — the
    // web shell has no push and no offline queue.
    ref.watch(notificationSyncProvider);
    ref.watch(photoQueueSyncProvider);
    ref.watch(pushNavigationProvider);
    // Route trail follows the open entry: start the foreground
    // tracking service when an entry opens (manual or auto),
    // stop it when it closes. Idempotent — repeated emissions
    // for the same entry are no-ops.
    ref.listen<AsyncValue<TimeEntry?>>(openTimeEntryProvider, (previous, next) {
      final entry = next.valueOrNull;
      if (entry == null) {
        unawaited(RouteTrackingService.stop());
      } else {
        final strings = ref.read(stringsProvider);
        unawaited(RouteTrackingService.ensureRunning(
          entryId: entry.id,
          notificationTitle: strings.trackingNotificationTitle,
          notificationText: strings.trackingNotificationText,
        ));
      }
    });
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final user = ref.watch(currentUserProvider).valueOrNull;
    if (user == null) {
      return Scaffold(
        body: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 96),
          child: SkeletonList(count: 6),
        ),
      );
    }

    final List<Widget> pages;
    final List<NavigationDestination> destinations;
    final unreadChats = ref.watch(unreadChatsProvider);
    switch (user.role) {
      case UserRole.admin:
      case UserRole.manager:
        pages = const [
          BoardScreen(),
          ReportsScreen(),
          PeopleScreen(),
          ChatListScreen(),
        ];
        destinations = [
          NavigationDestination(
              icon: const Icon(Icons.view_kanban_outlined), label: s.board),
          NavigationDestination(
              icon: const Icon(Icons.summarize_outlined), label: s.reports),
          NavigationDestination(
              icon: const Icon(Icons.group_outlined), label: s.team),
          NavigationDestination(icon: _chatIcon(unreadChats), label: s.chats),
        ];
        break;
      case UserRole.worker:
        pages = const [MyDayScreen(), MyHistoryScreen(), ChatListScreen()];
        destinations = [
          NavigationDestination(
              icon: const Icon(Icons.home_repair_service_outlined),
              label: s.myDay),
          NavigationDestination(
              icon: const Icon(Icons.history), label: s.history),
          NavigationDestination(icon: _chatIcon(unreadChats), label: s.chats),
        ];
        break;
      case UserRole.delivery:
        pages = const [RunScreen(), MyDayScreen(), ChatListScreen()];
        destinations = [
          NavigationDestination(
              icon: const Icon(Icons.local_shipping_outlined), label: s.run),
          NavigationDestination(
              icon: const Icon(Icons.home_repair_service_outlined),
              label: s.myDay),
          NavigationDestination(icon: _chatIcon(unreadChats), label: s.chats),
        ];
        break;
    }

    final lang = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final unreadCount = ref
            .watch(notificationsProvider)
            .valueOrNull
            ?.where((n) => !n.read)
            .length ??
        0;
    final currentIndex = _index.clamp(0, pages.length - 1);
    // The clock-in/out button sits next to the title on the
    // Board and My Day tabs only — one tap clocks in (at the
    // nearest site, or for the day when outside every fence)
    // or out, no sheet. Delivery drivers clock in too now
    // (day entries + visits), so they see it on their first
    // tab like everyone else.
    final showClockButton = ((user.isAdminOrManager && currentIndex == 0) ||
        (user.role == UserRole.worker && currentIndex == 0) ||
        (user.role == UserRole.delivery && currentIndex == 0));
    return Scaffold(
      appBar: AppBar(
        title: showClockButton
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      destinations[currentIndex].label,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const ClockInButton(),
                ],
              )
            : Text(destinations[currentIndex].label),
        actions: [
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined),
                if (unreadCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: const BoxDecoration(
                        color: AppTokens.accent,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        unreadCount > 99 ? '99+' : '$unreadCount',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: AppTokens.onAccent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            tooltip: s.notifications,
            onPressed: () => showNotificationsSheet(context),
          ),
          IconButton(
            icon: RoleAvatar(name: user.name, role: user.role, size: 32),
            tooltip: user.name,
            onPressed: () =>
                _showAccountSheet(context, user, s, lang, themeMode),
          ),
        ],
      ),
      body: pages[currentIndex],
      bottomNavigationBar: destinations.length < 2
          ? null
          : Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: tokens.border)),
              ),
              child: NavigationBar(
                selectedIndex: currentIndex,
                onDestinationSelected: (i) => setState(() => _index = i),
                destinations: destinations,
              ),
            ),
    );
  }
}
