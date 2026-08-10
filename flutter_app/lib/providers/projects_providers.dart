import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/employee.dart';
import '../models/project.dart';
import 'firebase_providers.dart';

final allProjectsProvider = StreamProvider<List<Project>>((ref) {
  return ref.watch(firestoreServiceProvider).watchAllProjects();
});

final projectByIdProvider = StreamProvider.family<Project?, String>((ref, projectId) {
  return ref.watch(firestoreServiceProvider).watchProject(projectId);
});

/// Refetches assigned employees whenever the project doc's `memberIds`
/// changes — replaces the manual `fetchProjectEmployees` refresh calls the
/// Kotlin ViewModel needed after every add/remove.
final projectEmployeesProvider = StreamProvider.family<List<Employee>, String>((ref, projectId) {
  final firestore = ref.watch(firestoreServiceProvider);
  return firestore.watchProject(projectId).asyncMap((project) async {
    if (project == null) return <Employee>[];
    return firestore.fetchEmployeesByIds(project.memberIds);
  });
});

final projectControllerProvider = Provider<ProjectController>((ref) => ProjectController(ref));

class ProjectController {
  ProjectController(this._ref);

  final Ref _ref;

  Future<void> addEmployeeToProject(String projectId, String employeeId) {
    return _ref.read(firestoreServiceProvider).addEmployeeToProject(projectId, employeeId);
  }

  Future<void> removeEmployeeFromProject(String projectId, String employeeId) {
    return _ref.read(firestoreServiceProvider).removeEmployeeFromProject(projectId, employeeId);
  }

  Future<String> createProject({
    required String name,
    String? description,
    String? address,
    File? photoFile,
  }) async {
    String? photoUrl;
    if (photoFile != null) {
      photoUrl = await _ref.read(storageServiceProvider).uploadProjectPhoto(photoFile);
    }
    return _ref.read(firestoreServiceProvider).createProject(
          Project(
            id: '',
            name: name,
            description: description,
            address: address,
            photoUrl: photoUrl,
          ),
        );
  }
}
