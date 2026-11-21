import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../models/team.dart';
import '../providers/locale_provider.dart';
import '../theme/app_tokens.dart';
import 'member_tile.dart';

/// One team as a card row: colour dot, name, a compact overlapping
/// stack of member avatars (+N when more than 4), and the member
/// count. Styling matches [MemberTile] (surface, 16 radius, border).
///
/// Admins/managers get a tap-to-edit and a trailing ⋮ menu
/// (Edit / Delete); everyone else sees the card read-only.
class TeamCard extends ConsumerWidget {
  final Team team;
  final List<AppUser> members;
  final bool canManage;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const TeamCard({
    super.key,
    required this.team,
    required this.members,
    this.canManage = false,
    this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    return GestureDetector(
      onTap: canManage ? onTap : null,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.border),
        ),
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            // Colour dot, derived from the team id (same as sites).
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppTokens.siteTagColorFor(team.id),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (members.isNotEmpty) ...[
                        _AvatarStack(members: members),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        // No dedicated count string exists; reuse
                        // the plural members label ("3 members").
                        '${members.length} ${s.members.toLowerCase()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (canManage) ...[
              const SizedBox(width: 12),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    onEdit?.call();
                  } else if (value == 'delete') {
                    onDelete?.call();
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        const Icon(Icons.edit_outlined, size: 19),
                        const SizedBox(width: 12),
                        Text(s.editTeam),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 19, color: tokens.danger),
                        const SizedBox(width: 12),
                        Text(s.deleteTeam,
                            style: TextStyle(color: tokens.danger)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Up to 4 member avatars overlapped left-to-right, then a "+N"
/// circle for the rest. 24px avatars on a 16px stride, each with a
/// 2px ring in the card's surface colour so overlaps read cleanly.
class _AvatarStack extends StatelessWidget {
  final List<AppUser> members;

  const _AvatarStack({required this.members});

  static const double _size = 24;
  static const double _stride = 16;
  static const int _maxShown = 4;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final shown = members.take(_maxShown).toList();
    final extra = members.length - shown.length;
    final totalWidth = _size + (_stride * (shown.length - 1)) +
        (extra > 0 ? _stride : 0);
    return SizedBox(
      width: totalWidth,
      height: _size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * _stride,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.surface, width: 2),
                ),
                child: RoleAvatar(
                  name: shown[i].name,
                  role: shown[i].role,
                  size: _size,
                ),
              ),
            ),
          if (extra > 0)
            Positioned(
              left: shown.length * _stride,
              child: Container(
                width: _size,
                height: _size,
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  shape: BoxShape.circle,
                  border: Border.all(color: tokens.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
