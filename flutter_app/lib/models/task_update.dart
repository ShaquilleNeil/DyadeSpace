import 'package:cloud_firestore/cloud_firestore.dart';

/// One entry in a task's Updates thread: a note (and optionally
/// a photo) posted by a crew member from the task detail screen.
/// Stored in the tasks/{taskId}/updates subcollection. Updates
/// are immutable - the rules allow create + read only.
class TaskUpdate {
  final String id;
  final String taskId;
  final String authorId;

  /// Display name, snapshotted at post time so the thread still
  /// reads well if the profile is renamed later.
  final String authorName;
  final String text;
  final String? photoUrl;
  final DateTime? createdAt;

  const TaskUpdate({
    required this.id,
    required this.taskId,
    required this.authorId,
    required this.authorName,
    this.text = '',
    this.photoUrl,
    this.createdAt,
  });

  factory TaskUpdate.fromFirestore(DocumentSnapshot doc) {
    return TaskUpdate.fromMap(
      doc.id,
      doc.data() as Map<String, dynamic>? ?? {},
    );
  }

  /// [taskId] is not stored in the doc (it is the parent path),
  /// so it is recovered from the caller when available and left
  /// empty otherwise; pass it when posting via [toMap].
  factory TaskUpdate.fromMap(String id, Map<String, dynamic> map,
      {String taskId = ''}) {
    return TaskUpdate(
      id: id,
      taskId: map['taskId'] as String? ?? taskId,
      authorId: map['authorId'] as String? ?? '',
      authorName: map['authorName'] as String? ?? '',
      text: map['text'] as String? ?? '',
      photoUrl: map['photoUrl'] as String?,
      createdAt:
          map['createdAt'] is Timestamp ? (map['createdAt'] as Timestamp).toDate() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'taskId': taskId,
      'authorId': authorId,
      'authorName': authorName,
      'text': text,
      'photoUrl': photoUrl,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
    };
  }
}
