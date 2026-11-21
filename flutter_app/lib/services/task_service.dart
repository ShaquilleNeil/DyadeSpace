import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/stage.dart';
import '../models/task_item.dart';
import '../models/task_update.dart';

/// All Firestore access for tasks. Overdue and day filtering are done
/// in Dart on purpose (spec): it keeps the queries simple and avoids
/// composite indexes for a crew this size.
/// The Firestore default is resolved lazily (same pattern as
/// TimeEntryService): FirebaseFirestore.instance throws when
/// Firebase is not initialized, so constructing the service
/// must not touch it — tests construct fakes of this class.
class TaskService {
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  TaskService({FirebaseFirestore? db}) : _dbOverride = db;

  CollectionReference<Map<String, dynamic>> get _tasks =>
      _db.collection('tasks');

  /// Every task - used by the manager board / today / by-person views.
  /// Bounded: earliest due first, 500 max (a crew this size never
  /// gets near it, but the query must not be unbounded).
  Stream<List<TaskItem>> watchAllTasks() {
    return _tasks.orderBy('dueDate').limit(500).snapshots().map((snap) {
      final list = snap.docs.map(TaskItem.fromFirestore).toList();
      list.sort((a, b) =>
          (a.dueDate ?? DateTime(2100)).compareTo(b.dueDate ?? DateTime(2100)));
      return list;
    });
  }

  /// One task by id (used to check a dependency's status).
  Stream<TaskItem?> watchTask(String id) {
    return _tasks
        .doc(id)
        .snapshots()
        .map((doc) => doc.exists ? TaskItem.fromFirestore(doc) : null);
  }

  Future<String> createTask(TaskItem task) async {
    final ref = await _tasks.add(task.toMap());
    return ref.id;
  }

  Future<void> updateTask(TaskItem task) {
    return _tasks.doc(task.id).update(task.toMap());
  }

  /// Deleting a task also clears it as a dependency: any task that
  /// started after this one loses the link instead of pointing at
  /// a task that no longer exists (a dangling link crashes the
  /// editor's "Starts after" dropdown).
  Future<void> deleteTask(String id) async {
    final dependents =
        await _tasks.where('dependsOnTaskId', isEqualTo: id).get();
    final batch = _db.batch();
    batch.delete(_tasks.doc(id));
    for (final doc in dependents.docs) {
      batch.update(doc.reference, {'dependsOnTaskId': null});
    }
    await batch.commit();
  }

  Future<void> startTask(TaskItem task) {
    return _tasks.doc(task.id).update({
      'status': TaskStatus.inProgress.name,
      'startedAt': Timestamp.fromDate(DateTime.now()),
      'blockedReason': null,
      'blockedNote': '',
    });
  }

  /// [photoUrls] must be non-empty when task.photoRequired is true;
  /// the detail screen enforces that before calling this.
  /// [photoPending] is set when a completion photo is waiting in
  /// the offline queue - the queue clears it once the photo lands.
  Future<void> completeTask(TaskItem task, List<String> photoUrls,
      {bool photoPending = false}) {
    return _tasks.doc(task.id).update({
      'status': TaskStatus.done.name,
      'finishedAt': Timestamp.fromDate(DateTime.now()),
      'photoUrls': FieldValue.arrayUnion(photoUrls),
      'photoPending': photoPending,
    });
  }

  /// Targeted one-field update used by the delivery flow: when
  /// Drew completes a drop-off linked to this task, its materials
  /// are on site. (The Firestore rules allow any signed-in user to
  /// change ONLY this field - see firestore.rules.)
  Future<void> markMaterialsOnSite(String taskId) {
    return _tasks.doc(taskId).update({'materialsOnSite': true});
  }

  CollectionReference<Map<String, dynamic>> _updates(String taskId) =>
      _tasks.doc(taskId).collection('updates');

  /// The task's Updates thread, oldest first (the detail screen
  /// renders it top to bottom like a conversation).
  Stream<List<TaskUpdate>> watchUpdates(String taskId) {
    return _updates(taskId).orderBy('createdAt').snapshots().map((snap) => snap
        .docs
        .map((doc) => TaskUpdate.fromMap(doc.id, doc.data(), taskId: taskId))
        .toList());
  }

  Future<void> addUpdate(
    String taskId, {
    required String authorId,
    required String authorName,
    required String text,
    String? photoUrl,
  }) {
    final update = TaskUpdate(
      id: '',
      taskId: taskId,
      authorId: authorId,
      authorName: authorName,
      text: text,
      photoUrl: photoUrl,
    );
    return _updates(taskId).add(update.toMap());
  }

  Future<void> blockTask(TaskItem task, BlockedReason reason, String note) {
    return _tasks.doc(task.id).update({
      'status': TaskStatus.blocked.name,
      'blockedReason': reason.name,
      'blockedNote': note,
    });
  }

  /// Park a task: status becomes paused, remembering where it came
  /// from so resume can restore it. No-op when already paused or
  /// done (the UI hides the action then; this is a backstop).
  Future<void> pauseTask(TaskItem task) async {
    if (task.status == TaskStatus.paused || task.status == TaskStatus.done) {
      return;
    }
    await _tasks.doc(task.id).update({
      'status': TaskStatus.paused.name,
      'pausedFrom': task.status.name,
    });
  }

  /// Resume a paused task: restores the pre-pause status (todo
  /// when unknown) and clears the stored status.
  Future<void> resumeTask(TaskItem task) async {
    if (task.status != TaskStatus.paused) return;
    await _tasks.doc(task.id).update({
      'status': (task.pausedFrom ?? TaskStatus.todo).name,
      'pausedFrom': null,
    });
  }

  /// Tasks relevant "today": due today, overdue, in progress,
  /// blocked, finished today - plus any day inside a multi-day
  /// window (a task with a start date shows from its start
  /// through its due date). Filtering happens here in Dart.
  /// When [stageIndex] is given, tasks in a stage that is not
  /// Active and not Completed are hidden: their stage has not
  /// been started yet, so they are not today's work (and they
  /// do not count for the who's-where crew either).
  static List<TaskItem> tasksForToday(List<TaskItem> all, DateTime day,
      [StageIndex? stageIndex]) {
    bool sameDay(DateTime? d) =>
        d != null &&
        d.year == day.year &&
        d.month == day.month &&
        d.day == day.day;
    final dayOnly = DateTime(day.year, day.month, day.day);
    return all.where((t) {
      if (stageIndex != null && !stageIndex.isVisibleToday(t)) return false;
      if (t.status == TaskStatus.done) return sameDay(t.finishedAt);
      if (sameDay(t.dueDate) ||
          t.isOverdue ||
          t.status == TaskStatus.inProgress ||
          t.status == TaskStatus.blocked ||
          t.status == TaskStatus.paused) {
        return true;
      }
      if (t.startDate != null) {
        if (sameDay(t.startDate)) return true;
        if (t.dueDate != null) {
          final start =
              DateTime(t.startDate!.year, t.startDate!.month, t.startDate!.day);
          final due =
              DateTime(t.dueDate!.year, t.dueDate!.month, t.dueDate!.day);
          if (!dayOnly.isBefore(start) && !dayOnly.isAfter(due)) {
            return true;
          }
        }
      }
      return false;
    }).toList();
  }

  static List<TaskItem> overdueOnly(List<TaskItem> all) =>
      all.where((t) => t.isOverdue).toList();

  /// Every task assigned to [userId], open or done, in provider
  /// order. The My Day / history membership check: a task shows
  /// when the worker's uid is in its assignee list — including
  /// old docs, whose single assignee loads as a one-person list.
  static List<TaskItem> tasksForAssignee(List<TaskItem> all, String userId) =>
      all.where((t) => t.assigneeIds.contains(userId)).toList();

  /// One person's open (not Done) tasks — the same list the By
  /// person screen shows per person: assigned to [userId] and
  /// not finished. Order is the provider's order, as on By
  /// person; the profile's Tasks tab uses this.
  static List<TaskItem> tasksForPerson(List<TaskItem> all, String userId) => all
      .where((t) => t.status != TaskStatus.done && t.assigneeIds.contains(userId))
      .toList();
}
