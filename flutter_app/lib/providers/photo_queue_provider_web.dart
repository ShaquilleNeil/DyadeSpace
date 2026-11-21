import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pending_task_update.dart';

/// Web stand-in for the offline photo queue. The control center
/// is online-first and never queues photos, so enqueue and
/// process are no-ops and the task screen keeps the same call
/// sites on both platforms. The real queue
/// (photo_queue_service.dart) uses dart:io and cannot compile
/// for web, so it stays phone-only behind the conditional import
/// in task_screen.dart.
class WebPhotoQueueService {
  /// Web never parks a photo, so a photo post cannot be queued
  /// — false tells the caller to keep the post and show the
  /// error instead of clearing the composer for a post that
  /// will never land. (Porting the bytes-upload path chat media
  /// uses is the follow-up that makes photo updates work on
  /// web; until then the failure is loud, not silent.)
  Future<bool> enqueue({
    required String kind,
    required String sourcePath,
    required String folder,
    String? taskId,
    String? runId,
    String? stopId,
    String? authorId,
    String? authorName,
    String? text,
  }) async =>
      false;

  Future<void> processQueue() async {}
}

final photoQueueServiceProvider =
    Provider<WebPhotoQueueService>((ref) => WebPhotoQueueService());

final photoQueueSyncProvider = Provider<void>((ref) {});

/// The web queue never parks anything, so there are never
/// pending update rows on the control center.
final pendingTaskUpdatesProvider =
    StreamProvider.family<List<PendingTaskUpdate>, String>(
        (ref, taskId) async* {
  yield const [];
});
