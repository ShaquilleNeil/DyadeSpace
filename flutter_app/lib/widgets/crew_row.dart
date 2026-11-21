import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../theme/app_tokens.dart';
import 'member_tile.dart';

/// Who's at a site today, as a slim row under the site header:
/// overlapping avatars (at most 5, then a "+N" circle) and the
/// crew's first names. [crew] maps user id -> task count at
/// this site today. [indent] aligns the row with the site name
/// in the header above: 40 on the Board (header padding 2 +
/// chevron 20 + chevron gap 2 + dot 8 + gap 8), 18 on the
/// per-site screen, whose header has no chevron (padding 2 +
/// dot 8 + gap 8).
class CrewRow extends StatelessWidget {
  final Map<String, int> crew;
  final Map<String, String> userName;
  final Map<String, UserRole> userRole;

  /// Profile photo URLs by user id (missing id = initials).
  final Map<String, String?> userPhoto;
  final double indent;

  const CrewRow({
    super.key,
    required this.crew,
    required this.userName,
    required this.userRole,
    this.userPhoto = const {},
    this.indent = 40,
  });

  /// First name only, for the crew row label.
  static String firstName(String name) {
    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? '' : parts.first;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    // Most-loaded first, then by name, so the order is stable.
    final ids = crew.keys.toList()
      ..sort((a, b) {
        final byCount = crew[b]!.compareTo(crew[a]!);
        if (byCount != 0) return byCount;
        return (userName[a] ?? '').compareTo(userName[b] ?? '');
      });
    final shown = ids.take(5).toList();
    final extra = ids.length - shown.length;
    final stackCount = shown.length + (extra > 0 ? 1 : 0);
    final names = shown
        .map((id) => firstName(userName[id] ?? ''))
        .where((n) => n.isNotEmpty)
        .join(', ');
    final label = extra > 0 ? '$names +$extra' : names;
    return Padding(
      padding: EdgeInsets.fromLTRB(indent, 0, 2, 6),
      child: SizedBox(
        height: 28,
        child: Row(
          children: [
            SizedBox(
              width: 24.0 + (stackCount - 1) * 16.0,
              height: 24,
              child: Stack(
                children: [
                  for (var i = 0; i < shown.length; i++)
                    Positioned(
                      left: i * 16.0,
                      child: Container(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: tokens.surface, width: 2),
                        ),
                        child: RoleAvatar(
                          name: userName[shown[i]] ?? '',
                          role: userRole[shown[i]],
                          size: 24,
                          photoUrl: userPhoto[shown[i]],
                        ),
                      ),
                    ),
                  if (extra > 0)
                    Positioned(
                      left: shown.length * 16.0,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: tokens.surfaceRaised,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: tokens.surface, width: 2),
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
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: tokens.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
