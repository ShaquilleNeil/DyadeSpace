import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/app_user.dart';
import '../../models/team.dart';
import '../../models/time_entry.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/runs_provider.dart';
import '../../providers/teams_provider.dart';
import '../../providers/time_entries_provider.dart';
import '../../theme/app_tokens.dart';
import '../../utils/week_hours.dart';
import '../../widgets/bulk_invite_sheet.dart';
import '../../widgets/member_tile.dart';
import '../../widgets/team_card.dart';
import '../chat_screen.dart';
import '../worker_profile_screen.dart';
import 'web_shared.dart';

/// Crew: the mockup's worker table, plus everything the phone
/// People screen does — it is the web's crew management, not a
/// read-only view. One row per person: role, where they are
/// right now (clock-in site + time, or today's run for a
/// driver), and hours this week. Tap a row for the full profile
/// (clock history + map links) — the same screen the phone app
/// opens.
///
/// - Invite (single + bulk) and the pending-invite list
///   (resend by mailto, revoke) use the same AuthService calls
///   as the phone People screen; managers never see the admin
///   role in the invite picker.
/// - Week navigation (previous / next) moves the week the
///   hours column totals; hours are keyed by userId and count
///   live time on open entries, like the phone Team tiles.
/// - Every open entry per user is kept (not just the last one):
///   the row shows today's open entry when there is one,
///   otherwise the earliest still-open entry — someone whose
///   open entry is from an earlier day is labelled "Still
///   clocked in" instead of silently looking not clocked in.
/// - Teams are created / edited / deleted here with the same
///   TeamService calls as the phone screen.
/// - DM shortcut opens a DM with the person; admins can
///   deactivate a member (never themselves) from the row menu.
class WebCrewScreen extends ConsumerStatefulWidget {
  const WebCrewScreen({super.key});

  @override
  ConsumerState<WebCrewScreen> createState() => _WebCrewScreenState();
}

class _WebCrewScreenState extends ConsumerState<WebCrewScreen> {
  late DateTime _weekStart;

  @override
  void initState() {
    super.initState();
    _weekStart = weekStartFor(DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final now = DateTime.now();
    final me = ref.watch(currentUserProvider).valueOrNull;
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final entries = ref.watch(allTimeEntriesProvider).valueOrNull ?? [];
    final runs = ref.watch(allRunsProvider).valueOrNull ?? [];
    final invites = ref.watch(pendingInvitesProvider).valueOrNull ?? [];
    final teams = ref.watch(teamsProvider).valueOrNull ?? [];

    final weekEnd = weekEndFor(_weekStart);
    final weekFmt = DateFormat('yyyy-MM-dd');
    final todayStr = weekFmt.format(now);
    // All open entries per user, earliest first — never just
    // the last one (the old code overwrote the map entry, so a
    // second open entry hid the first and its hours).
    final openByUser = <String, List<TimeEntry>>{};
    for (final e in entries) {
      if (e.isOpen) (openByUser[e.userId] ??= []).add(e);
    }
    for (final list in openByUser.values) {
      list.sort((a, b) => a.clockInAt.compareTo(b.clockInAt));
    }
    // Week hours per userId (never by name — same-name workers
    // must not merge), counting live time on open entries.
    final weekHours = <String, double>{};
    for (final e in entriesInWeek(entries, _weekStart)) {
      weekHours[e.userId] =
          (weekHours[e.userId] ?? 0) + e.effectiveHours;
    }
    final todaysRuns = runs.where((r) => isSameDay(r.date, now)).toList();

    final sorted = List<AppUser>.from(users)
      ..sort((a, b) => a.name.compareTo(b.name));
    // A stale invite for someone who already has an account
    // must never render (same filter as the phone screen).
    final memberEmails =
        users.map((u) => u.email.trim().toLowerCase()).toSet();
    final pending = invites
        .where((inv) => !memberEmails.contains(
            (inv['email'] as String? ?? '').trim().toLowerCase()))
        .toList();
    final isAdmin = me?.role == UserRole.admin;

    return ListView(
      padding: webContentPadding(MediaQuery.sizeOf(context).width),
      children: [
        WebSectionHeader(
          title: s.crew,
          subtitle: s.hoursWeekLabel(
            DateFormat('MMM d').format(_weekStart),
            DateFormat('MMM d').format(weekEnd),
          ),
          trailing: Wrap(
            spacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: s.hoursPreviousWeek,
                onPressed: () => setState(() =>
                    _weekStart = _weekStart.subtract(const Duration(days: 7))),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: s.hoursNextWeek,
                onPressed: () => setState(() =>
                    _weekStart = _weekStart.add(const Duration(days: 7))),
              ),
              const SizedBox(width: 4),
              FilledButton.icon(
                onPressed: () => _invite(context, ref),
                icon: const Icon(Icons.person_add, size: 18),
                label: Text(s.invite),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                ),
              ),
              const SizedBox(width: 4),
              OutlinedButton.icon(
                onPressed: () => _bulkInvite(context, ref),
                icon: const Icon(Icons.group_add_outlined, size: 18),
                label: Text(s.bulkInvite),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 52),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        WebCard(
          child: WebResponsiveTable(
            headers: [s.crew, s.role, s.clockIn, s.hoursThisWeek, ''],
            rows: sorted.map((u) {
              final open = openByUser[u.id] ?? const <TimeEntry>[];
              // Today's open entry when there is one; otherwise
              // the earliest still-open entry (stale — the
              // person never clocked out).
              final entry = open
                      .where((e) => e.date == todayStr)
                      .firstOrNull ??
                  open.firstOrNull;
              final stillClockedIn =
                  entry != null && entry.date != todayStr;
              final run = u.role == UserRole.delivery
                  ? todaysRuns
                      .where((r) => r.driverId == u.id)
                      .firstOrNull
                  : null;
              final done = run == null
                  ? 0
                  : run.stops
                      .where((st) => st.status.name == 'completed')
                      .length;
              return [
                Row(
                  children: [
                    RoleAvatar(
                        name: u.name,
                        role: u.role,
                        size: 32,
                        photoUrl: u.photoUrl),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        u.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Text(roleLabel(s, u.role)),
                run != null
                    ? Row(
                        children: [
                          WebPill(label: s.onRun, color: tokens.accent),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '$done / ${run.stops.length}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : entry == null
                        ? Text(s.notClockedIn,
                            style:
                                TextStyle(color: tokens.textSecondary))
                        : Row(
                            children: [
                              if (stillClockedIn) ...[
                                WebPill(
                                    label: s.hoursStillClockedIn,
                                    color: tokens.danger),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Text(
                                  '${entry.siteName} · ${webTime(entry.clockInAt)}'
                                  '${stillClockedIn ? ' · ${entry.date}' : ''}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (entry.flagged) ...[
                                const SizedBox(width: 8),
                                WebPill(
                                    label: s.hoursFlagged,
                                    color: tokens.danger),
                              ],
                            ],
                          ),
                Text(webHours(weekHours[u.id] ?? 0)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (me != null && u.id != me.id)
                      IconButton(
                        icon: const Icon(Icons.chat_bubble_outline, size: 20),
                        color: tokens.textSecondary,
                        tooltip: s.message,
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _openDm(context, ref, u),
                      ),
                    if (isAdmin && me != null && u.id != me.id && u.active)
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert, size: 20),
                        tooltip: s.deactivateUser,
                        onSelected: (value) {
                          if (value == 'deactivate') {
                            _deactivateUser(context, ref, u);
                          }
                        },
                        itemBuilder: (ctx) => [
                          PopupMenuItem(
                            value: 'deactivate',
                            child: Row(
                              children: [
                                Icon(Icons.person_off_outlined,
                                    size: 19, color: tokens.danger),
                                const SizedBox(width: 12),
                                Text(s.deactivateUser,
                                    style: TextStyle(color: tokens.danger)),
                              ],
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ];
            }).toList(),
            flex: const [3, 2, 4, 1, 1],
            onRowTap: (i) {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => WorkerProfileScreen(user: sorted[i]),
                ),
              );
            },
            emptyText: s.noWorkersYet,
          ),
        ),
        if (pending.isNotEmpty) ...[
          const SizedBox(height: 24),
          WebSectionHeader(
              title: '${s.pendingInvites} (${pending.length})'),
          const SizedBox(height: 10),
          for (final inv in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: WebCard(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: MemberTile(
                  title: inv['email'] as String? ?? '',
                  subtitle:
                      '${s.pending} · ${roleLabel(s, userRoleFromString(inv['role'] as String?))}',
                  role: userRoleFromString(inv['role'] as String?),
                  pending: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'resend') {
                        _sendInviteEmail(context, ref, inv);
                      } else if (value == 'revoke') {
                        _revokeInvite(context, ref, inv['id'] as String);
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'resend',
                        child: Row(
                          children: [
                            const Icon(Icons.mail_outline, size: 19),
                            const SizedBox(width: 12),
                            Text(s.resend),
                          ],
                        ),
                      ),
                      PopupMenuItem(
                        value: 'revoke',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline,
                                size: 19, color: tokens.danger),
                            const SizedBox(width: 12),
                            Text(s.revoke,
                                style: TextStyle(color: tokens.danger)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
        const SizedBox(height: 24),
        WebSectionHeader(
          title: teams.isEmpty ? s.teams : '${s.teams} (${teams.length})',
          trailing: me == null
              ? null
              : TextButton.icon(
                  onPressed: () =>
                      _editTeam(context, ref, users: users, me: me),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(s.newTeam),
                  style: TextButton.styleFrom(
                    foregroundColor: tokens.accentText,
                  ),
                ),
        ),
        const SizedBox(height: 10),
        if (teams.isEmpty)
          Text(s.noTeams,
              style: TextStyle(fontSize: 13, color: tokens.textTertiary))
        else
          for (final team in teams) ...[
            TeamCard(
              team: team,
              members: users
                  .where((u) => team.memberIds.contains(u.id))
                  .toList(),
              canManage: me?.isAdminOrManager ?? false,
              onTap: me == null
                  ? null
                  : () =>
                      _editTeam(context, ref, team: team, users: users, me: me),
              onEdit: me == null
                  ? null
                  : () =>
                      _editTeam(context, ref, team: team, users: users, me: me),
              onDelete: () => _deleteTeam(context, ref, team),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  /// Single invite: email + role, same AuthService call as the
  /// phone People screen. Managers never see the admin role in
  /// the picker (the service also refuses it server-side).
  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    final s = ref.read(stringsProvider);
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    final emailCtrl = TextEditingController();
    UserRole role = UserRole.worker;
    final roles = me.role == UserRole.admin
        ? UserRole.values
        : UserRole.values.where((r) => r != UserRole.admin).toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.invite),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(labelText: s.email),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<UserRole>(
              initialValue: role,
              isExpanded: true,
              items: [
                for (final r in roles)
                  DropdownMenuItem(
                    value: r,
                    child:
                        Text(roleLabel(s, r), overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => role = v ?? role,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.confirm)),
        ],
      ),
    );
    emailCtrl.dispose();
    if (ok != true || emailCtrl.text.trim().isEmpty) return;
    try {
      await ref.read(authServiceProvider).createInvite(
            email: emailCtrl.text,
            role: role,
            invitedBy: me.id,
          );
    } on StateError catch (e) {
      if (!context.mounted) return;
      final message = e.message == 'already-member'
          ? s.alreadyMember
          : e.message == 'already-invited'
              ? s.alreadyInvited
              : e.message == 'admin-invite-requires-admin'
                  ? s.inviteAdminRequiresAdmin
                  : e.message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${s.invite}: ${emailCtrl.text.trim()}')),
      );
    }
  }

  /// Bulk invite: the same sheet as the phone People screen
  /// (paste emails or import a CSV); the sheet does the parsing
  /// and the summary.
  Future<void> _bulkInvite(BuildContext context, WidgetRef ref) async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    await showBulkInviteSheet(context, ref, invitedBy: me.id);
  }

  /// Opens the device mail app pre-addressed to the invitee.
  /// This only COMPOSES the email — the manager still presses
  /// send in their own mail app (no SMTP/server sending yet).
  Future<void> _sendInviteEmail(
      BuildContext context, WidgetRef ref, Map<String, dynamic> invite) async {
    final s = ref.read(stringsProvider);
    final email = invite['email'] as String? ?? '';
    final role = invite['role'] as String? ?? UserRole.worker.name;
    final uri = Uri.parse(
      'mailto:${Uri.encodeComponent(email)}'
      '?subject=${Uri.encodeComponent(s.inviteEmailSubject)}'
      '&body=${Uri.encodeComponent(s.inviteEmailBody(email, role))}',
    );
    var launched = false;
    if (await canLaunchUrl(uri)) {
      launched = await launchUrl(uri);
    }
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.noMailApp)),
      );
    }
  }

  Future<void> _revokeInvite(
      BuildContext context, WidgetRef ref, String inviteId) async {
    final s = ref.read(stringsProvider);
    try {
      await ref.read(authServiceProvider).revokeInvite(inviteId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.inviteRevoked)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  /// Deactivates a member (admin only): first disables their
  /// Auth account via the 'disableUser' callable Cloud Function,
  /// then marks their users doc active=false. The Firestore
  /// write only happens when the function succeeded; any failure
  /// shows a friendly message, never raw error text.
  Future<void> _deactivateUser(
      BuildContext context, WidgetRef ref, AppUser member) async {
    final s = ref.read(stringsProvider);
    final tokens = AppTokens.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deactivateUser),
        content: Text(s.confirmDeactivate),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.confirm),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFunctions.instance
          .httpsCallable('disableUser')
          .call({'targetUid': member.id});
      await FirebaseFirestore.instance
          .collection('users')
          .doc(member.id)
          .update({'active': false});
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.deactivateFailed)),
        );
      }
      return;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.userDeactivated)),
      );
    }
  }

  /// DM shortcut: opens (or creates) a DM with this person.
  Future<void> _openDm(
      BuildContext context, WidgetRef ref, AppUser user) async {
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    final id =
        await ref.read(chatServiceProvider).findOrCreateDm(me.id, user.id);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(conversationId: id)),
    );
  }

  /// Team editor: name + member picker. [team] null creates a new
  /// team; otherwise the dialog opens pre-filled. Any user of any
  /// role can be picked, and a person may belong to several teams.
  Future<void> _editTeam(
    BuildContext context,
    WidgetRef ref, {
    Team? team,
    required List<AppUser> users,
    required AppUser me,
  }) async {
    final s = ref.read(stringsProvider);
    final nameCtrl = TextEditingController(text: team?.name ?? '');
    final selected = <String>{...?team?.memberIds};
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) {
          final nameOk = nameCtrl.text.trim().isNotEmpty;
          return AlertDialog(
            title: Text(team == null ? s.newTeam : s.editTeam),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: InputDecoration(labelText: s.teamName),
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 320,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: users.length,
                      itemBuilder: (ctx, i) {
                        final u = users[i];
                        final checked = selected.contains(u.id);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: RoleAvatar(
                              name: u.name,
                              role: u.role,
                              size: 32,
                              photoUrl: u.photoUrl),
                          title: Text(u.name),
                          subtitle: Text(roleLabel(s, u.role)),
                          trailing: Checkbox(
                            value: checked,
                            onChanged: (v) => setState(() {
                              if (v == true) {
                                selected.add(u.id);
                              } else {
                                selected.remove(u.id);
                              }
                            }),
                          ),
                          onTap: () => setState(() {
                            if (checked) {
                              selected.remove(u.id);
                            } else {
                              selected.add(u.id);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text(s.cancel)),
              FilledButton(
                onPressed: nameOk ? () => Navigator.pop(ctx, true) : null,
                child: Text(s.save),
              ),
            ],
          );
        },
      ),
    );
    nameCtrl.dispose();
    if (saved != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    try {
      if (team == null) {
        await ref.read(teamServiceProvider).createTeam(
              name: name,
              memberIds: selected.toList(),
              createdBy: me.id,
            );
      } else {
        await ref.read(teamServiceProvider).updateTeam(
            team.copyWith(name: name, memberIds: selected.toList()));
      }
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.teamSaved)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  /// Deletes ONLY the team doc — members keep their accounts.
  Future<void> _deleteTeam(
      BuildContext context, WidgetRef ref, Team team) async {
    final tokens = AppTokens.of(context);
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteTeam),
        content: Text(s.deleteTeamConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(teamServiceProvider).deleteTeam(team.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.teamDeleted)),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }
}
