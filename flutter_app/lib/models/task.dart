import 'package:cloud_firestore/cloud_firestore.dart';

class TaskStatus {
  static const todo = 'todo';
  // Hyphenated to match the original Supabase schema's stored values.
  static const inProgress = 'in-progress';
  static const done = 'done';

  static const all = [todo, inProgress, done];

  static String label(String status) {
    switch (status) {
      case todo:
        return 'To Do';
      case inProgress:
        return 'In Progress';
      case done:
        return 'Completed';
      default:
        return '';
    }
  }
}

class Task {
  final String id;
  final String title;
  final String? description;
  final String status;
  final DateTime? deadline;
  final DateTime? createdAt;
  final String? projectId;
  final List<String> assigneeIds;

  const Task({
    required this.id,
    required this.title,
    this.description,
    this.status = TaskStatus.todo,
    this.deadline,
    this.createdAt,
    this.projectId,
    this.assigneeIds = const [],
  });

  bool get isDone => status == TaskStatus.done;

  factory Task.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Task(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String?,
      status: data['status'] as String? ?? TaskStatus.todo,
      deadline: (data['deadline'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      projectId: data['projectId'] as String?,
      assigneeIds: List<String>.from(data['assigneeIds'] as List? ?? const []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'status': status,
      'deadline': deadline != null ? Timestamp.fromDate(deadline!) : null,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'projectId': projectId,
      'assigneeIds': assigneeIds,
    };
  }
}
