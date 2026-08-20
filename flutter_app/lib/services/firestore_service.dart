import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_notification.dart';
import '../models/daily_report.dart';
import '../models/employee.dart';
import '../models/material_request.dart';
import '../models/project.dart';
import '../models/task.dart';

/// Typed Firestore access. Replaces the Supabase Postgrest calls in
/// AuthViewModel/TaskViewModel/ProjectViewModel, using the redesigned
/// array-field schema (see plan) instead of join tables.
class FirestoreService {
  FirestoreService(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get _employees =>
      _db.collection('employees');
  CollectionReference<Map<String, dynamic>> get _projects =>
      _db.collection('projects');
  CollectionReference<Map<String, dynamic>> get _tasks =>
      _db.collection('tasks');
  CollectionReference<Map<String, dynamic>> get _materialRequests =>
      _db.collection('materialRequests');
  CollectionReference<Map<String, dynamic>> get _dailyReports =>
      _db.collection('dailyReports');
  CollectionReference<Map<String, dynamic>> get _notifications =>
      _db.collection('notifications');

  // ---------------- Employees ----------------

  Future<void> createEmployee(Employee employee) {
    return _employees.doc(employee.id).set(employee.toMap());
  }

  Future<Employee?> fetchEmployee(String uid) async {
    final doc = await _employees.doc(uid).get();
    if (!doc.exists) return null;
    return Employee.fromDoc(doc);
  }

  Stream<Employee?> watchEmployee(String uid) {
    return _employees
        .doc(uid)
        .snapshots()
        .map((doc) => doc.exists ? Employee.fromDoc(doc) : null);
  }

  Future<List<Employee>> fetchAllEmployees() async {
    final snap = await _employees.get();
    return snap.docs.map(Employee.fromDoc).toList();
  }

  Stream<List<Employee>> watchAllEmployees() {
    return _employees.snapshots().map(
          (snap) => snap.docs.map(Employee.fromDoc).toList(),
        );
  }

  Future<List<Employee>> fetchEmployeesByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final results = <Employee>[];
    for (var i = 0; i < ids.length; i += 10) {
      final chunk = ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10);
      final snap = await _employees
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      results.addAll(snap.docs.map(Employee.fromDoc));
    }
    return results;
  }

  Future<void> updateEmployee(String uid, Map<String, dynamic> fields) {
    return _employees.doc(uid).update(fields);
  }

  Future<void> updateEmployeeRole(String uid, String role) {
    return _employees.doc(uid).update({'role': role});
  }

  Future<void> addFcmToken(String uid, String token) {
    return _employees.doc(uid).update({
      'fcmTokens': FieldValue.arrayUnion([token]),
    });
  }

  Future<void> removeFcmToken(String uid, String token) {
    return _employees.doc(uid).update({
      'fcmTokens': FieldValue.arrayRemove([token]),
    });
  }

  /// Employees who share at least one project with any id in [projectIds] —
  /// the manager-scoped equivalent of [watchAllEmployees]. Chunked because
  /// `arrayContainsAny` accepts at most 10 values.
  Stream<List<Employee>> watchEmployeesForProjects(List<String> projectIds) {
    return _mergeByIdChunks(
      projectIds,
      (chunk) => _employees
          .where('projectIds', arrayContainsAny: chunk)
          .snapshots()
          .map((snap) => snap.docs.map(Employee.fromDoc).toList()),
      (e) => e.id,
    );
  }

  /// Projects a given employee (typically a manager) is a member of.
  Stream<List<Project>> watchProjectsForMember(String uid) {
    return _projects
        .where('memberIds', arrayContains: uid)
        .snapshots()
        .map((snap) => snap.docs.map(Project.fromDoc).toList());
  }

  // ---------------- Projects ----------------

  Future<String> createProject(Project project) async {
    final ref = await _projects.add(project.toMap());
    return ref.id;
  }

  Future<List<Project>> fetchAllProjects() async {
    final snap = await _projects.get();
    return snap.docs.map(Project.fromDoc).toList();
  }

  Stream<List<Project>> watchAllProjects() {
    return _projects.snapshots().map(
          (snap) => snap.docs.map(Project.fromDoc).toList(),
        );
  }

  Future<Project?> fetchProject(String projectId) async {
    final doc = await _projects.doc(projectId).get();
    if (!doc.exists) return null;
    return Project.fromDoc(doc);
  }

  Stream<Project?> watchProject(String projectId) {
    return _projects
        .doc(projectId)
        .snapshots()
        .map((doc) => doc.exists ? Project.fromDoc(doc) : null);
  }

  Future<List<Employee>> fetchProjectEmployees(String projectId) async {
    final project = await fetchProject(projectId);
    if (project == null) return [];
    return fetchEmployeesByIds(project.memberIds);
  }

  Future<void> addEmployeeToProject(String projectId, String employeeId) {
    final batch = _db.batch();
    batch.update(_projects.doc(projectId), {
      'memberIds': FieldValue.arrayUnion([employeeId]),
    });
    batch.update(_employees.doc(employeeId), {
      'projectIds': FieldValue.arrayUnion([projectId]),
    });
    return batch.commit();
  }

  Future<void> removeEmployeeFromProject(String projectId, String employeeId) {
    final batch = _db.batch();
    batch.update(_projects.doc(projectId), {
      'memberIds': FieldValue.arrayRemove([employeeId]),
    });
    batch.update(_employees.doc(employeeId), {
      'projectIds': FieldValue.arrayRemove([projectId]),
    });
    return batch.commit();
  }

  /// Sets an employee's full project membership in one shot (admin staff-edit
  /// sheet) — diffs against [currentProjectIds] and batches the add/remove
  /// writes on both sides of the denormalized relationship.
  Future<void> setEmployeeProjects(
    String employeeId, {
    required List<String> currentProjectIds,
    required List<String> newProjectIds,
  }) {
    final toAdd = newProjectIds.where((id) => !currentProjectIds.contains(id));
    final toRemove = currentProjectIds.where((id) => !newProjectIds.contains(id));
    final batch = _db.batch();
    for (final projectId in toAdd) {
      batch.update(_projects.doc(projectId), {
        'memberIds': FieldValue.arrayUnion([employeeId]),
      });
    }
    for (final projectId in toRemove) {
      batch.update(_projects.doc(projectId), {
        'memberIds': FieldValue.arrayRemove([employeeId]),
      });
    }
    batch.update(_employees.doc(employeeId), {'projectIds': newProjectIds});
    return batch.commit();
  }

  // ---------------- Tasks ----------------

  Future<List<Task>> fetchAllTasks() async {
    final snap = await _tasks.get();
    return snap.docs.map(Task.fromDoc).toList();
  }

  Stream<List<Task>> watchAllTasks() {
    return _tasks.snapshots().map(
          (snap) => snap.docs.map(Task.fromDoc).toList(),
        );
  }

  /// Tasks assigned to [uid]. `status != done` filtering happens client-side
  /// to avoid a composite array-contains + not-equal index (see plan).
  Stream<List<Task>> watchMyTasks(String uid) {
    return _tasks
        .where('assigneeIds', arrayContains: uid)
        .snapshots()
        .map((snap) => snap.docs.map(Task.fromDoc).toList());
  }

  Future<int> getActiveTaskCountForEmployee(String uid) async {
    final snap =
        await _tasks.where('assigneeIds', arrayContains: uid).get();
    return snap.docs
        .map(Task.fromDoc)
        .where((t) => t.status != TaskStatus.done)
        .length;
  }

  Future<Task?> fetchTaskById(String taskId) async {
    final doc = await _tasks.doc(taskId).get();
    if (!doc.exists) return null;
    return Task.fromDoc(doc);
  }

  Stream<Task?> watchTaskById(String taskId) {
    return _tasks
        .doc(taskId)
        .snapshots()
        .map((doc) => doc.exists ? Task.fromDoc(doc) : null);
  }

  Stream<List<Task>> watchProjectTasks(String projectId) {
    return _tasks
        .where('projectId', isEqualTo: projectId)
        .snapshots()
        .map((snap) => snap.docs.map(Task.fromDoc).toList());
  }

  Future<List<Employee>> getEmployeesForTask(String taskId) async {
    final task = await fetchTaskById(taskId);
    if (task == null) return [];
    return fetchEmployeesByIds(task.assigneeIds);
  }

  Future<String> addTaskAndAssign(Task task, List<String> employeeIds) async {
    final data = task.toMap();
    data['assigneeIds'] = employeeIds;
    final ref = await _tasks.add(data);
    return ref.id;
  }

  Future<void> deleteTask(String taskId) {
    return _tasks.doc(taskId).delete();
  }

  Future<void> updateTaskStatus(String taskId, String newStatus) {
    return _tasks.doc(taskId).update({'status': newStatus});
  }

  Future<void> updateTask(String taskId, Map<String, dynamic> fields) {
    return _tasks.doc(taskId).update(fields);
  }

  Future<void> completeTask(
    String taskId, {
    required List<String> photoUrls,
    String? note,
  }) {
    return _tasks.doc(taskId).update({
      'status': TaskStatus.done,
      'completionPhotoUrls': photoUrls,
      'completionNote': note,
    });
  }

  // ---------------- Material Requests ----------------

  Future<String> createMaterialRequest(MaterialRequest request) async {
    final ref = await _materialRequests.add(request.toMap());
    return ref.id;
  }

  Future<void> setMaterialRequestPhotos(String requestId, List<String> photoUrls) {
    return _materialRequests.doc(requestId).update({'photoUrls': photoUrls});
  }

  Stream<List<MaterialRequest>> watchMyMaterialRequests(String uid) {
    return _materialRequests
        .where('requestedById', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map(MaterialRequest.fromDoc).toList());
  }

  Stream<List<MaterialRequest>> watchMaterialRequestsForProjects(List<String> projectIds) {
    return _mergeByIdChunks(
      projectIds,
      (chunk) => _materialRequests
          .where('projectId', whereIn: chunk)
          .snapshots()
          .map((snap) => snap.docs.map(MaterialRequest.fromDoc).toList()),
      (r) => r.id,
    );
  }

  Stream<List<MaterialRequest>> watchAllMaterialRequests() {
    return _materialRequests
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(MaterialRequest.fromDoc).toList());
  }

  Stream<MaterialRequest?> watchMaterialRequestById(String requestId) {
    return _materialRequests
        .doc(requestId)
        .snapshots()
        .map((doc) => doc.exists ? MaterialRequest.fromDoc(doc) : null);
  }

  Future<void> decideMaterialRequest(
    String requestId, {
    required String status,
    required String decidedById,
    String? managerNote,
  }) {
    return _materialRequests.doc(requestId).update({
      'status': status,
      'decidedById': decidedById,
      'decidedAt': Timestamp.now(),
      'managerNote': managerNote,
    });
  }

  Future<void> deleteMaterialRequest(String requestId) {
    return _materialRequests.doc(requestId).delete();
  }

  // ---------------- Daily Reports ----------------

  Future<String> createDailyReport(DailyReport report) async {
    final ref = await _dailyReports.add(report.toMap());
    return ref.id;
  }

  Future<void> setDailyReportPhotos(String reportId, List<String> photoUrls) {
    return _dailyReports.doc(reportId).update({'photoUrls': photoUrls});
  }

  Stream<List<DailyReport>> watchMyDailyReports(String uid) {
    return _dailyReports
        .where('submittedById', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map(DailyReport.fromDoc).toList());
  }

  Stream<List<DailyReport>> watchDailyReportsForProjects(List<String> projectIds) {
    return _mergeByIdChunks(
      projectIds,
      (chunk) => _dailyReports
          .where('projectId', whereIn: chunk)
          .snapshots()
          .map((snap) => snap.docs.map(DailyReport.fromDoc).toList()),
      (r) => r.id,
    );
  }

  Stream<List<DailyReport>> watchAllDailyReports() {
    return _dailyReports
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(DailyReport.fromDoc).toList());
  }

  Stream<DailyReport?> watchDailyReportById(String reportId) {
    return _dailyReports
        .doc(reportId)
        .snapshots()
        .map((doc) => doc.exists ? DailyReport.fromDoc(doc) : null);
  }

  Future<void> deleteDailyReport(String reportId) {
    return _dailyReports.doc(reportId).delete();
  }

  // ---------------- Notifications ----------------
  // Written only by Cloud Functions (Admin SDK) — client is read/mark-read only.

  Stream<List<AppNotification>> watchMyNotifications(String uid) {
    return _notifications
        .where('recipientId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(AppNotification.fromDoc).toList());
  }

  Future<void> markNotificationRead(String notificationId) {
    return _notifications.doc(notificationId).update({'read': true});
  }

  Future<void> markAllNotificationsRead(List<String> notificationIds) {
    final batch = _db.batch();
    for (final id in notificationIds) {
      batch.update(_notifications.doc(id), {'read': true});
    }
    return batch.commit();
  }

  Future<void> deleteNotification(String notificationId) {
    return _notifications.doc(notificationId).delete();
  }

  // ---------------- Shared helpers ----------------

  /// Runs a `whereIn`/`arrayContainsAny`-style query in chunks of 10
  /// (Firestore's limit on either clause) and merges the live results into
  /// one deduplicated stream, re-emitting whenever any chunk updates.
  Stream<List<T>> _mergeByIdChunks<T>(
    List<String> ids,
    Stream<List<T>> Function(List<String> chunk) queryChunk,
    String Function(T item) idOf,
  ) {
    if (ids.isEmpty) return Stream.value(const []);
    final chunks = <List<String>>[];
    for (var i = 0; i < ids.length; i += 10) {
      chunks.add(ids.sublist(i, i + 10 > ids.length ? ids.length : i + 10));
    }
    final streams = chunks.map(queryChunk).toList();
    if (streams.length == 1) return streams.first;

    final latest = List<List<T>>.filled(streams.length, const []);
    late final StreamController<List<T>> controller;
    final subs = <StreamSubscription>[];
    controller = StreamController<List<T>>(
      onListen: () {
        for (var i = 0; i < streams.length; i++) {
          subs.add(streams[i].listen((items) {
            latest[i] = items;
            final merged = <String, T>{};
            for (final list in latest) {
              for (final item in list) {
                merged[idOf(item)] = item;
              }
            }
            controller.add(merged.values.toList());
          }));
        }
      },
      onCancel: () async {
        for (final sub in subs) {
          await sub.cancel();
        }
      },
    );
    return controller.stream;
  }
}
