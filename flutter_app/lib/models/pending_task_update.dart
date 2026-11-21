/// A task-update post parked in the offline photo queue and not
/// yet a Firestore doc: the detail screen renders it as a
/// pending row ("Sending…") until the queue lands it as a real
/// update. Platform neutral — a local file path plus the post
/// text — so the web stub provider can expose the same type
/// with an always-empty list, and the screen keeps one render
/// path on both platforms.
class PendingTaskUpdate {
  /// Where the photo is parked on this device.
  final String localPath;
  final String authorName;
  final String text;
  final DateTime queuedAt;

  const PendingTaskUpdate({
    required this.localPath,
    required this.authorName,
    required this.text,
    required this.queuedAt,
  });
}
