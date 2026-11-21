import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pending_task_update.dart';
import '../services/photo_queue_service.dart';
import 'tasks_provider.dart';

final photoQueueServiceProvider = Provider<PhotoQueueService>(
  (ref) => PhotoQueueService(photos: ref.watch(photoServiceProvider)),
);

/// Task-update posts still parked in the offline queue for one
/// task — the detail screen renders them as pending rows
/// ("Sending…") until the queue lands them as real updates, so
/// a photo post is visible from the moment Post is tapped
/// instead of only once its upload finishes.
final pendingTaskUpdatesProvider =
    StreamProvider.family<List<PendingTaskUpdate>, String>((ref, taskId) {
  return ref.watch(photoQueueServiceProvider).watchEntries().map((list) => list
      .where((e) => e.kind == 'taskUpdate' && e.taskId == taskId)
      .map((e) => PendingTaskUpdate(
            localPath: e.localPath,
            authorName: e.authorName ?? '',
            text: e.text ?? '',
            queuedAt: e.queuedAt,
          ))
      .toList());
});

/// Keeps the offline photo queue draining for the whole
/// session. Watched once from the home shell
/// (home_shell.dart, in the shell's build — not from the app
/// root as this comment used to say):
/// - one processing pass right away (covers photos queued in a
///   previous session - "app start" is this watch being built),
/// - another pass every time connectivity comes back (any
///   result other than "none": wifi, mobile, ethernet...).
/// Passes are cheap and internally guarded against overlap, so
/// firing on every connectivity event is safe.
final photoQueueSyncProvider = Provider<void>((ref) {
  final service = ref.watch(photoQueueServiceProvider);
  unawaited(service.processQueue());
  final sub = Connectivity().onConnectivityChanged.listen((results) {
    if (results.any((r) => r != ConnectivityResult.none)) {
      unawaited(service.processQueue());
    }
  });
  ref.onDispose(sub.cancel);
});
