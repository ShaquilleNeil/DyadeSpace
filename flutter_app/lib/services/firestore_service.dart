import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/employee.dart';
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
    return _projects.doc(projectId).update({
      'memberIds': FieldValue.arrayUnion([employeeId]),
    });
  }

  Future<void> removeEmployeeFromProject(String projectId, String employeeId) {
    return _projects.doc(projectId).update({
      'memberIds': FieldValue.arrayRemove([employeeId]),
    });
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
}
