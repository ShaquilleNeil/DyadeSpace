import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../l10n/app_strings.dart';
import '../models/app_user.dart';
import '../models/chat.dart';
import '../models/team.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/teams_provider.dart';
import '../services/chat_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/empty_state.dart';
import '../widgets/member_tile.dart';
import '../widgets/section_label.dart';
import '../widgets/skeleton_card.dart';
import 'broadcast_screen.dart';
import 'chat_screen.dart';

/// Chats tab: DMs, team channels, and broadcast conversations,
/// newest activity first. Team channels are ensured (created
/// and kept in sync) the first time this tab opens with the
/// teams loaded — see [_maybeEnsureTeamChannels].
class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

/// `HH:mm` for today, otherwise `MMM d` — same as the
/// notifications sheet.
String _timeLabel(DateTime t) {
  final now = DateTime.now();
  final isToday =
      t.year == now.year && t.month == now.month && t.day == now.day;
  return isToday
      ? DateFormat('HH:mm').format(t)
      : DateFormat('MMM d').format(t);
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  bool _ensuredTeams = false;
  bool _ensureFailedShown = false;

  void _maybeEnsureTeamChannels() {
    if (_ensuredTeams) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_ensuredTeams || !mounted) return;
      final me = ref.read(currentUserProvider).valueOrNull;
      final teamsAsync = ref.read(teamsProvider);
      final usersAsync = ref.read(allUsersProvider);
      if (me == null || !teamsAsync.hasValue || !usersAsync.hasValue) {
        return; // data still loading — a later build retries.
      }
      final teams = teamsAsync.valueOrNull ?? [];
      final users = usersAsync.valueOrNull ?? [];
      final adminManagerIds =
          users.where((u) => u.isAdminOrManager).map((u) => u.id).toList();
      unawaited(_ensureTeamChannels(
        teams,
        adminManagerIds,
        me,
        ref.read(chatServiceProvider),
      ));
    });
  }

  /// Ensures one channel per team I can see, in order. A failed
  /// run leaves [_ensuredTeams] false so a later build retries
  /// (for example once a rules deploy lands), and the user sees
  /// one plain message instead of a silent miss. The failure
  /// message shows at most once per mount so a persistent
  /// failure never spams snackbars.
  Future<void> _ensureTeamChannels(
    List<Team> teams,
    List<String> adminManagerIds,
    AppUser me,
    ChatService service,
  ) async {
    var failed = false;
    for (final team in teams) {
      if (!me.isAdminOrManager && !team.memberIds.contains(me.id)) {
        continue; // only my teams (admins/managers see all).
      }
      try {
        await service.ensureTeamChannel(
          team: team,
          adminManagerIds: adminManagerIds,
          createdBy: me.id,
        );
      } catch (_) {
        failed = true;
      }
    }
    if (!mounted) return;
    if (failed) {
      if (!_ensureFailedShown) {
        _ensureFailedShown = true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(ref.read(stringsProvider).couldNotOpenChat)),
        );
      }
      return; // _ensuredTeams stays false: a later build retries.
    }
    _ensuredTeams = true;
  }

  /// Shared group avatar for a team channel (list row and the
  /// new-message sheet use the same one).
  Widget _teamAvatar(String seed) {
    final color = AppTokens.siteTagColorFor(seed);
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      alignment: Alignment.center,
      child:
          const Icon(Icons.group_outlined, size: 20, color: Colors.white),
    );
  }

  void _openChat(Conversation conversation) {
    HapticFeedback.lightImpact();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: conversation.id,
          conversation: conversation,
        ),
      ),
    );
  }

  Future<void> _openDm(AppUser me, AppUser other) async {
    final String id;
    try {
      id = await ref
          .read(chatServiceProvider)
          .findOrCreateDm(me.id, other.id);
    } catch (_) {
      // Rules or connection failure: say so plainly instead of
      // silently opening nothing.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(stringsProvider).couldNotOpenChat)),
      );
      return;
    }
    if (!mounted) return;
    final conversations = ref.read(conversationsProvider).valueOrNull ?? [];
    final existing =
        conversations.where((c) => c.id == id).firstOrNull;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: id,
          conversation: existing ??
              Conversation(
                id: id,
                type: 'dm',
                participantIds: [me.id, other.id],
                createdBy: me.id,
              ),
        ),
      ),
    );
  }

  void _showNewChatSheet(
    AppUser me,
    List<AppUser> users,
    AppStrings s,
    List<Conversation> conversations,
    Map<String, Team> teamById,
  ) {
    final teamConversations = conversations.where((c) => c.isTeam).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (me.isAdminOrManager) ...[
                  ListTile(
                    leading: const Icon(Icons.campaign_outlined),
                    title: Text(s.newBroadcast),
                    subtitle: Text(s.broadcastHint),
                    onTap: () {
                      Navigator.of(sheetContext).pop();
                      Navigator.of(context).push(
                        MaterialPageRoute(
                            builder: (_) => const BroadcastScreen()),
                      );
                    },
                  ),
                  const Divider(),
                ],
                // Team channels that already exist (created lazily
                // when the Chats tab opens): tap to open one.
                if (teamConversations.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                    child: SectionLabel(s.team),
                  ),
                  for (final conv in teamConversations)
                    ListTile(
                      leading: _teamAvatar(conv.teamId ?? conv.id),
                      title: Text(conv.title ??
                          teamById[conv.teamId]?.name ??
                          s.team),
                      subtitle: Text(s.membersCount(
                          teamById[conv.teamId]?.memberIds.length ??
                              conv.participantIds.length)),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _openChat(conv);
                      },
                    ),
                  const Divider(),
                ],
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: SectionLabel(s.messageSomeone),
                ),
                for (final u in users.where((u) => u.id != me.id))
                  ListTile(
                    leading:
                        RoleAvatar(name: u.name, role: u.role, size: 40),
                    title: Text(u.name),
                    subtitle: Text(roleLabel(s, u.role)),
                    onTap: () async {
                      Navigator.of(sheetContext).pop();
                      await _openDm(me, u);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final teams = ref.watch(teamsProvider).valueOrNull ?? [];
    final userById = {for (final u in users) u.id: u};
    final teamById = {for (final t in teams) t.id: t};
    final conversationsAsync = ref.watch(conversationsProvider);

    _maybeEnsureTeamChannels();

    if (me == null) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20, 96),
        child: SkeletonList(count: 6),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        tooltip: s.newMessage,
        onPressed: () {
          HapticFeedback.lightImpact();
          _showNewChatSheet(me, users, s,
              conversationsAsync.valueOrNull ?? [], teamById);
        },
        child: const Icon(Icons.add),
      ),
      body: conversationsAsync.when(
        loading: () => const Padding(
          padding: EdgeInsets.fromLTRB(20, 8, 20, 96),
          child: SkeletonList(count: 6),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Text(
              '$error',
              textAlign: TextAlign.center,
              style: TextStyle(color: tokens.textSecondary),
            ),
          ),
        ),
        data: (conversations) {
          if (conversations.isEmpty) {
            return EmptyState(
              icon: Icons.chat_bubble_outline,
              title: s.noChats,
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
            itemCount: conversations.length,
            separatorBuilder: (_, __) =>
                Divider(color: tokens.border, height: 1),
            itemBuilder: (context, index) {
              final conv = conversations[index];
              return _conversationRow(
                  context, conv, me, userById, teamById, s, tokens);
            },
          );
        },
      ),
    );
  }

  Widget _conversationRow(
    BuildContext context,
    Conversation conv,
    AppUser me,
    Map<String, AppUser> userById,
    Map<String, Team> teamById,
    AppStrings s,
    AppColors tokens,
  ) {
    final isUnread = conv.isUnreadBy(me.id);
    final String title;
    final Widget avatar;
    if (conv.isTeam) {
      final team = conv.teamId == null ? null : teamById[conv.teamId];
      title = conv.title ?? team?.name ?? s.team;
      avatar = _teamAvatar(conv.teamId ?? conv.id);
    } else {
      final otherId = conv.participantIds
          .firstWhere((id) => id != me.id, orElse: () => me.id);
      final other = userById[otherId];
      title = other?.name ?? s.formerMember;
      avatar = RoleAvatar(
          name: title, role: other?.role ?? UserRole.worker, size: 40);
    }
    final String preview;
    if (conv.lastMessage.isEmpty) {
      preview = '';
    } else if (conv.lastSenderId == me.id) {
      preview = '${s.you}: ${conv.lastMessage}';
    } else if (conv.isTeam) {
      final sender = conv.lastSenderId == null
          ? null
          : userById[conv.lastSenderId];
      final firstName = (sender?.name ?? '').split(' ').first;
      preview = firstName.isEmpty
          ? conv.lastMessage
          : '$firstName: ${conv.lastMessage}';
    } else {
      preview = conv.lastMessage;
    }
    return InkWell(
      onTap: () => _openChat(conv),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            avatar,
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: isUnread
                                ? FontWeight.w700
                                : FontWeight.w600,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      if (conv.isBroadcast) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.campaign_outlined,
                            size: 16, color: tokens.textTertiary),
                      ],
                      if (conv.updatedAt != null) ...[
                        const SizedBox(width: 8),
                        Text(
                          _timeLabel(conv.updatedAt!),
                          style: TextStyle(
                            fontSize: 12,
                            color: tokens.textTertiary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (preview.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      preview,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isUnread ? FontWeight.w600 : FontWeight.w400,
                        color: isUnread
                            ? tokens.textPrimary
                            : tokens.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isUnread) ...[
              const SizedBox(width: 10),
              Container(
                width: 10,
                height: 10,
                margin: const EdgeInsets.only(top: 6),
                decoration: const BoxDecoration(
                  color: AppTokens.accent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
