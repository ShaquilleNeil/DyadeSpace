import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_strings.dart';
import '../../models/app_user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/material_requests_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/member_tile.dart';
import '../../widgets/notifications_sheet.dart';
import '../chat_list_screen.dart';
import '../settings_screen.dart';
import '../task_screen.dart';
import 'web_board_screen.dart';
import 'web_crew_screen.dart';
import 'web_hours_screen.dart';
import 'web_overview_screen.dart';
import 'web_reports_screen.dart';
import 'web_requests_screen.dart';
import 'web_shared.dart';
import 'web_sites_screen.dart';

/// The web control center shell, picked up by app.dart through
/// the conditional import (see the typedef at the bottom).
///
/// Layout (mockup, desktop-first):
/// - >= 900px: full sidebar, 232px.
/// - 700..900px: icon rail, 68px.
/// - < 700px (phones): the sidebar becomes a drawer behind a
///   hamburger; the topbar search hides; views reflow (stat
///   cards stack, tables become cards). The phone app stays the
///   main phone experience — this just makes the site usable
///   from a phone (Sam checking from his, the owner on
///   site).
///
/// Non-admin/manager users see a locked screen: the Firestore
/// rules block their manager reads, so a wall of permission
/// errors would be the alternative.
///
/// DECISION (Nov 21, 2026 audit, Area G item 8): the web
/// control center stays admin/manager-only BY DESIGN. The web
/// is the admin control center; workers and delivery drivers
/// use the phone app, which has everything they need —
/// including clock-in, My Day, and the driver screen — and the
/// phone app is what the crew actually carries on site. No
/// worker web access is built; if that ever changes, it needs
/// its own scoped web views plus a rules pass, not just
/// removing this lock.
class ControlCenterShell extends ConsumerStatefulWidget {
  const ControlCenterShell({super.key});

  @override
  ConsumerState<ControlCenterShell> createState() =>
      _ControlCenterShellState();
}

class _ControlCenterShellState extends ConsumerState<ControlCenterShell> {
  ControlCenterSection _section = ControlCenterSection.overview;
  String? _boardSiteId;
  String? _boardQuery;

  void _navigate(ControlCenterSection section,
      {String? siteId, String? query}) {
    setState(() {
      _section = section;
      _boardSiteId = siteId;
      _boardQuery = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    if (me == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!me.isAdminOrManager) {
      // Locked by design (see the class doc): the web control
      // center is admin/manager-only; workers use the phone app.
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: WebCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(s.managersOnly,
                        style: const TextStyle(fontSize: 15)),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () =>
                          ref.read(authServiceProvider).signOut(),
                      child: Text(s.signOut),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final narrow = width < kWebDrawerBreakpoint;
      final rail = !narrow && width < kWebRailBreakpoint;
      final content = _content(context, s, me, width, narrow);
      if (narrow) {
        return Scaffold(
          drawer: Drawer(
            child: _nav(context, s, me, rail: false, onSelect: (section) {
              Navigator.of(context).pop();
              _navigate(section);
            }),
          ),
          body: content,
        );
      }
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: rail ? 68 : 232,
              child: _nav(context, s, me, rail: rail,
                  onSelect: (section) => _navigate(section)),
            ),
            Expanded(child: content),
          ],
        ),
      );
    });
  }

  Widget _content(BuildContext context, AppStrings s, AppUser me,
      double width, bool narrow) {
    return Column(
      children: [
        _topbar(context, s, width, narrow),
        Expanded(child: _sectionView()),
      ],
    );
  }

  Widget _topbar(
      BuildContext context, AppStrings s, double width, bool narrow) {
    final tokens = AppTokens.of(context);
    // Unread notification count for the bell badge (in-app
    // list only — no push on web).
    final unread = ref.watch(notificationsProvider).valueOrNull
            ?.where((n) => !n.read)
            .length ??
        0;
    return Container(
      padding: EdgeInsets.fromLTRB(
          narrow ? 8 : 20, 12, narrow ? 12 : 20, 12),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          if (narrow)
            Builder(
              builder: (context) => IconButton(
                tooltip: s.controlCenter,
                icon: const Icon(Icons.menu),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _sectionTitle(s, _section),
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                if (!narrow)
                  Text(
                    DateFormat('EEEE, MMM d', s.lang).format(DateTime.now()),
                    style: TextStyle(
                        fontSize: 12, color: tokens.textSecondary),
                  ),
              ],
            ),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                tooltip: s.notifications,
                icon: const Icon(Icons.notifications_outlined),
                onPressed: _openNotifications,
              ),
              if (unread > 0)
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: tokens.danger,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      unread > 99 ? '99+' : '$unread',
                      style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
          // The topbar search hides below 900px (mockup): the
          // Board has its own working search.
          if (width >= kWebRailBreakpoint) ...[
            SizedBox(
              width: 240,
              child: TextField(
                onSubmitted: (value) {
                  if (value.trim().isEmpty) return;
                  _navigate(ControlCenterSection.board,
                      query: value.trim());
                },
                decoration: InputDecoration(
                  hintText: s.searchTasksHint,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: tokens.border),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 8),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          width < 560
              ? IconButton(
                  tooltip: s.newTask,
                  onPressed: _newTask,
                  icon: const Icon(Icons.add),
                )
              : FilledButton.icon(
                  onPressed: _newTask,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(s.newTask),
                  // The app theme gives every FilledButton
                  // minimumSize Size.fromHeight(52) = an INFINITE
                  // minimum width. In this Row that made the button
                  // take infinite width, starving the Expanded title
                  // to 0px (title invisible, date one letter per
                  // line) and clipping the button itself — the
                  // live-site topbar bug (Nov 15). Bound it to its
                  // content, same as the bulk-invite sheet fix.
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                ),
        ],
      ),
    );
  }

  void _newTask() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const TaskScreen()),
    );
  }

  /// The bell inbox: the same notifications list as the phone,
  /// in a dialog (max 560px wide). Tapping a notification
  /// navigates through the shared router; on web, material
  /// requests land on the Requests section and runs open the
  /// web run screen.
  void _openNotifications() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SizedBox(
            height: 600,
            child: NotificationsSheet(
              onWebSection: (section) => _navigate(section),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionView() {
    switch (_section) {
      case ControlCenterSection.overview:
        return WebOverviewScreen(onNavigate: _navigate);
      case ControlCenterSection.board:
        return WebBoardScreen(
          initialQuery: _boardQuery,
          initialSiteId: _boardSiteId,
        );
      case ControlCenterSection.crew:
        return const WebCrewScreen();
      case ControlCenterSection.hours:
        return const WebHoursScreen();
      case ControlCenterSection.reports:
        return const WebReportsScreen();
      case ControlCenterSection.requests:
        return const WebRequestsScreen();
      case ControlCenterSection.sites:
        return WebSitesScreen(onNavigate: _navigate);
      case ControlCenterSection.settings:
        // The settings screen's Scaffold is phone-shaped; the
        // body (SettingsBody) is shared, so embed it here.
        return const _WebSettingsView();
      case ControlCenterSection.chats:
        // The phone Chats tab, as-is: DMs, team channels and
        // broadcast, with text + photo sending and voice notes
        // (record supports web). It has no AppBar of its own,
        // only a floating new-message button, so it sits under
        // the shell topbar like any other section.
        return const ChatListScreen();
    }
  }

  String _sectionTitle(AppStrings s, ControlCenterSection section) {
    switch (section) {
      case ControlCenterSection.overview:
        return s.overview;
      case ControlCenterSection.board:
        return s.board;
      case ControlCenterSection.crew:
        return s.crew;
      case ControlCenterSection.hours:
        return s.hours;
      case ControlCenterSection.reports:
        return s.reports;
      case ControlCenterSection.requests:
        return s.materialRequests;
      case ControlCenterSection.sites:
        return s.sites;
      case ControlCenterSection.settings:
        return s.settings;
      case ControlCenterSection.chats:
        return s.chats;
    }
  }

  Widget _nav(BuildContext context, AppStrings s, AppUser me,
      {required bool rail,
      required void Function(ControlCenterSection) onSelect}) {
    final tokens = AppTokens.of(context);
    final crewCount = ref.watch(allUsersProvider).valueOrNull?.length ?? 0;
    final openRequests = ref.watch(openMaterialRequestsCountProvider);
    return Container(
      color: tokens.surface,
      child: Column(
        crossAxisAlignment:
            rail ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                rail ? 0 : 20, 20, rail ? 0 : 20, 8),
            child: rail
                ? Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      'D',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'DyadeSpace',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Control Center · app.dyademanagement.com',
                        style: TextStyle(
                            fontSize: 11, color: tokens.textSecondary),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _navGroupLabel(s, tokens, s.manage, rail),
                  _navItem(context, s, tokens, rail,
                      section: ControlCenterSection.overview,
                      icon: Icons.dashboard_outlined,
                      label: s.overview,
                      onSelect: onSelect),
                  _navItem(context, s, tokens, rail,
                      section: ControlCenterSection.board,
                      icon: Icons.view_kanban_outlined,
                      label: s.board,
                      onSelect: onSelect),
                  _navItem(context, s, tokens, rail,
                      section: ControlCenterSection.crew,
                      icon: Icons.people_outline,
                      label: s.crew,
                      badge: crewCount,
                      onSelect: onSelect),
                  _navItem(context, s, tokens, rail,
                      section: ControlCenterSection.hours,
                      icon: Icons.schedule_outlined,
                      label: s.hours,
                      onSelect: onSelect),
                  _navItem(context, s, tokens, rail,
                      section: ControlCenterSection.reports,
                      icon: Icons.summarize_outlined,
                      label: s.reports,
                      onSelect: onSelect),
                  _navItem(context, s, tokens, rail,
                      section: ControlCenterSection.requests,
                      icon: Icons.inventory_2_outlined,
                      label: s.materialRequests,
                      badge: openRequests,
                      onSelect: onSelect),
                  const SizedBox(height: 12),
                  _navGroupLabel(s, tokens, s.workspace, rail),
                  _navItem(context, s, tokens, rail,
                      section: ControlCenterSection.sites,
                      icon: Icons.location_on_outlined,
                      label: s.sites,
                      onSelect: onSelect),
                  _navItem(context, s, tokens, rail,
                      section: ControlCenterSection.settings,
                      icon: Icons.settings_outlined,
                      label: s.settings,
                      onSelect: onSelect),
                  _navItem(context, s, tokens, rail,
                      section: ControlCenterSection.chats,
                      icon: Icons.chat_bubble_outline,
                      label: s.chats,
                      onSelect: onSelect),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: tokens.border),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: rail ? 0 : 12, vertical: 12),
            child: rail
                ? IconButton(
                    tooltip: s.signOut,
                    onPressed: () =>
                        ref.read(authServiceProvider).signOut(),
                    icon: const Icon(Icons.logout, size: 20),
                  )
                : Row(
                    children: [
                      RoleAvatar(
                          name: me.name,
                          role: me.role,
                          size: 36,
                          photoUrl: me.photoUrl),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(me.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis),
                            Text(
                              me.role == UserRole.admin
                                  ? s.roleAdmin
                                  : s.roleManager,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: tokens.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: s.signOut,
                        onPressed: () =>
                            ref.read(authServiceProvider).signOut(),
                        icon: const Icon(Icons.logout, size: 20),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _navGroupLabel(
      AppStrings s, AppColors tokens, String label, bool rail) {
    if (rail) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: tokens.textTertiary,
        ),
      ),
    );
  }

  Widget _navItem(
    BuildContext context,
    AppStrings s,
    AppColors tokens,
    bool rail, {
    required ControlCenterSection section,
    required IconData icon,
    required String label,
    int badge = 0,
    required void Function(ControlCenterSection) onSelect,
  }) {
    final selected = _section == section;
    final bg = selected ? tokens.accentMuted : Colors.transparent;
    final fg = selected ? tokens.accentText : tokens.textPrimary;
    final content = Container(
      margin:
          EdgeInsets.symmetric(horizontal: rail ? 8 : 12, vertical: 2),
      padding: EdgeInsets.symmetric(
          horizontal: rail ? 0 : 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: rail
          ? Stack(
              alignment: Alignment.center,
              children: [
                Icon(icon, color: fg, size: 22),
                if (badge > 0)
                  Positioned(
                    right: 6,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: tokens.danger,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '$badge',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white),
                      ),
                    ),
                  ),
              ],
            )
          : Row(
              children: [
                Icon(icon, color: fg, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                        color: fg,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.normal),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (badge > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: tokens.danger,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
    );
    return Tooltip(
      message: rail ? label : '',
      child: InkWell(
        onTap: () => onSelect(section),
        borderRadius: BorderRadius.circular(10),
        child: content,
      ),
    );
  }
}

/// The web Settings view: the same SettingsBody the phone
/// Settings screen wraps, constrained for a wide screen.
class _WebSettingsView extends StatelessWidget {
  const _WebSettingsView();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 720),
        child: SettingsBody(),
      ),
    );
  }
}

/// app.dart resolves its home through a conditional import:
/// `HomeShell` is the phone shell on mobile and this shell on
/// web (dart.library.js_interop is true on both web renderers
/// and false on mobile).
typedef HomeShell = ControlCenterShell;
