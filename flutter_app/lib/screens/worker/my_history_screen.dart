import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/task_item.dart';
import '../../providers/locale_provider.dart';
import '../../providers/sites_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../widgets/task_card.dart';
import '../task_screen.dart';

/// Tasks this worker has finished, newest first - their own
/// record of what got done (and the photos that prove it).
class MyHistoryScreen extends ConsumerWidget {
  const MyHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    final myAsync = ref.watch(myTasksProvider);
    final siteById = ref.watch(siteByIdProvider);
    return myAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (mine) {
        final done = mine
            .where((t) => t.status == TaskStatus.done)
            .toList()
          ..sort((a, b) => (b.finishedAt ?? DateTime(2000))
              .compareTo(a.finishedAt ?? DateTime(2000)));
        if (done.isEmpty) return Center(child: Text(s.noTasks));
        return ListView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
          children: [
            for (final t in done)
              TaskCard(
                task: t,
                site: siteById[t.siteId],
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => TaskScreen(task: t)),
                ),
              ),
          ],
        );
      },
    );
  }
}
