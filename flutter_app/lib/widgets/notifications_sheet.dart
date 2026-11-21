import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models/app_user.dart';
import '../models/notification_item.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/notifications_provider.dart';
import '../screens/web/web_shared.dart';
import '../services/notification_router.dart';
import '../theme/app_tokens.dart';
import 'empty_state.dart';
import 'skeleton_card.dart';

/// Opens the notifications sheet: header (title + mark-all-read)
/// over the newest-first list, ~75% of screen height. The web
/// control center passes [onWebSection] so material-request and
/// run taps land on the web sections/screens instead of the
/// phone ones (see openNotification).
void showNotificationsSheet(BuildContext context,
    {void Function(ControlCenterSection section)? onWebSection}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SizedBox(
      height: MediaQuery.of(sheetContext).size.height * 0.75,
      child: NotificationsSheet(onWebSection: onWebSection),
    ),
  );
}

/// `HH:mm` for today's notifications, otherwise `MMM d`.
String _timeLabel(DateTime t) {
  final now = DateTime.now();
  final isToday =
      t.year == now.year && t.month == now.month && t.day == now.day;
  return isToday
      ? DateFormat('HH:mm').format(t)
      : DateFormat('MMM d').format(t);
}

class NotificationsSheet extends ConsumerWidget {
  final void Function(ControlCenterSection section)? onWebSection;
  const NotificationsSheet({super.key, this.onWebSection});

  /// Marks the notification read first, then navigates through
  /// the shared router (same routing as an FCM push tap):
  /// clock-in/out -> map, chat -> conversation, material
  /// request -> requests screen, task -> task screen, run ->
  /// run progress. Marking read must never block the
  /// navigation, so a failure there is swallowed; a target
  /// that no longer exists opens nothing.
  Future<void> _openNotification(
      BuildContext context, AppUser me, AppNotification n) async {
    try {
      await markNotificationRead(n.id);
    } catch (_) {
      // Read receipts are best-effort — the tap still navigates.
    }
    if (!context.mounted) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    navigator.pop(); // closes this sheet
    await openNotification(navigator, n, me,
        onWebSection: onWebSection);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final notificationsAsync = ref.watch(notificationsProvider);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
          child: Row(
            children: [
              Text(
                s.notifications,
                style:  TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: me == null
                    ? null
                    : () => markAllNotificationsRead(me.id),
                child: Text(s.markAllRead),
              ),
            ],
          ),
        ),
         Divider(color: tokens.border, height: 1),
        Expanded(
          child: notificationsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.only(top: 16),
              child: SkeletonList(count: 6),
            ),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '$error',
                  textAlign: TextAlign.center,
                  style:  TextStyle(color: tokens.textSecondary),
                ),
              ),
            ),
            data: (items) {
              if (items.isEmpty) {
                return EmptyState(
                  icon: Icons.notifications_outlined,
                  title: s.noNotifications,
                );
              }
              return ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                     Divider(color: tokens.border, height: 1),
                itemBuilder: (context, index) {
                  final n = items[index];
                  return InkWell(
                    onTap: me == null
                        ? null
                        : () => _openNotification(context, me, n),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!n.read) ...[
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(top: 6),
                              decoration: const BoxDecoration(
                                color: AppTokens.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  n.title,
                                  style:  TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: tokens.textPrimary,
                                  ),
                                ),
                                if (n.body.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    n.body,
                                    style:  TextStyle(
                                      fontSize: 14,
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            _timeLabel(n.createdAt),
                            style:  TextStyle(
                              fontSize: 12,
                              color: tokens.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
