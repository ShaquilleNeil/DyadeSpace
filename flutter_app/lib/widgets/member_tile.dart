import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../l10n/app_strings.dart';
import '../models/app_user.dart';
import '../providers/locale_provider.dart';
import '../theme/app_tokens.dart';

/// A person's photo in a circle when they set one, otherwise
/// their initials in a circle coloured by their role.
class RoleAvatar extends StatelessWidget {
  final String name;
  final UserRole? role;
  final double size;

  /// Profile photo download URL. Null (or a failed load) falls
  /// back to the initials circle.
  final String? photoUrl;

  const RoleAvatar({
    super.key,
    required this.name,
    this.role,
    this.size = 40,
    this.photoUrl,
  });

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final p = parts.first;
      return (p.length > 1 ? p.substring(0, 2) : p).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTokens.roleAvatarColors(role ?? UserRole.worker);
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(
          photoUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: colors.bg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(name),
              style: TextStyle(
                fontSize: size * 0.36,
                fontWeight: FontWeight.w700,
                color: colors.fg,
              ),
            ),
          ),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.bg,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        _initials(name),
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w700,
          color: colors.fg,
        ),
      ),
    );
  }
}

/// Localized label for a user role.
String roleLabel(AppStrings s, UserRole role) {
  switch (role) {
    case UserRole.admin:
      return s.roleAdmin;
    case UserRole.manager:
      return s.roleManager;
    case UserRole.worker:
      return s.roleWorker;
    case UserRole.delivery:
      return s.roleDelivery;
  }
}

/// One team member (or pending invite) as a card row: avatar,
/// name + subtitle, and the role label (or a custom trailing
/// widget) on the right. Pending rows render dimmed with a mail
/// icon instead of initials.
class MemberTile extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final UserRole role;
  final bool pending;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Clock-in status line under the subtitle, e.g. "Clocked in
  /// at Maple Court · 08:04" (green) or "Not clocked in" (muted).
  /// Null hides the line.
  final String? statusText;

  /// Week-hours line under the status line, e.g. "This week:
  /// 24 h 30 min" (Team tiles, Hours person cards). Null
  /// hides the line.
  final String? weekHoursText;

  /// Green status text when true (clocked in), muted otherwise.
  final bool statusActive;

  /// Profile photo URL — shown instead of initials when set.
  final String? photoUrl;

  const MemberTile({
    super.key,
    required this.title,
    this.subtitle,
    required this.role,
    this.pending = false,
    this.trailing,
    this.onTap,
    this.statusText,
    this.weekHoursText,
    this.statusActive = false,
    this.photoUrl,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.border),
        ),
        padding: const EdgeInsets.all(12),
        child: Opacity(
          opacity: pending ? 0.65 : 1,
          child: Row(
            children: [
              if (pending)
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: tokens.surfaceRaised,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.mail_outline,
                    size: 19,
                    color: tokens.textSecondary,
                  ),
                )
              else
                RoleAvatar(
                    name: title, role: role, size: 40, photoUrl: photoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: tokens.textPrimary,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: tokens.textSecondary,
                        ),
                      ),
                    if (statusText != null)
                      Text(
                        statusText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: statusActive
                              ? tokens.statusDone
                              : tokens.textTertiary,
                        ),
                      ),
                    if (weekHoursText != null)
                      Text(
                        weekHoursText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textTertiary,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              trailing ??
                  Text(
                    roleLabel(s, role).toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: tokens.textTertiary,
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}
