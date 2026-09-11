import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/app_notification.dart';
import '../../providers/notifications_providers.dart';
import '../../theme/app_spacing.dart';
import '../../utils/friendly_error.dart';

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  void _open(BuildContext context, WidgetRef ref, AppNotification notification) {
    if (!notification.read) {
      ref.read(notificationControllerProvider).markRead(notification.id);
    }
    if (notification.deepLink != null) {
      context.push(notification.deepLink!);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(myNotificationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if ((notificationsAsync.value ?? const []).any((n) => !n.read))
            TextButton(
              onPressed: () {
                final unreadIds = notificationsAsync.value!
                    .where((n) => !n.read)
                    .map((n) => n.id)
                    .toList();
                ref.read(notificationControllerProvider).markAllRead(unreadIds);
              },
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: SafeArea(
        child: notificationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text(friendlyErrorMessage(e))),
          data: (notifications) {
            if (notifications.isEmpty) {
              return const Center(child: Text('No notifications yet'));
            }
            return ListView.separated(
              itemCount: notifications.length,
              separatorBuilder: (context, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return Dismissible(
                  key: ValueKey(notification.id),
                  direction: DismissDirection.endToStart,
                  onDismissed: (_) =>
                      ref.read(notificationControllerProvider).delete(notification.id),
                  background: Container(
                    color: Theme.of(context).colorScheme.errorContainer,
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                    child: const Icon(Icons.delete_outline),
                  ),
                  child: ListTile(
                    tileColor: notification.read
                        ? null
                        : Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.35),
                    title: Text(
                      notification.title,
                      style: TextStyle(fontWeight: notification.read ? FontWeight.normal : FontWeight.bold),
                    ),
                    subtitle: Text(notification.body),
                    trailing: notification.createdAt != null
                        ? Text(
                            DateFormat('MMM d').format(notification.createdAt!),
                            style: Theme.of(context).textTheme.labelSmall,
                          )
                        : null,
                    onTap: () => _open(context, ref, notification),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
