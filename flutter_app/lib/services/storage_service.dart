import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

/// Avatar upload/replace — mirrors `AuthViewModel.uploadProfileImage`,
/// which deleted the old Supabase Storage object before uploading the new one.
class StorageService {
  StorageService(this._storage);

  final FirebaseStorage _storage;

  Future<String> uploadAvatar({
    required String uid,
    required File file,
    String? oldAvatarUrl,
  }) async {
    if (oldAvatarUrl != null && oldAvatarUrl.isNotEmpty) {
      try {
        await _storage.refFromURL(oldAvatarUrl).delete();
      } catch (_) {
        // old file may already be gone — safe to ignore, matches prior behavior
      }
    }

    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref('avatars/$uid/$fileName');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  Future<String> uploadProjectPhoto(File file) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref('project_photos/$fileName');
    await ref.putFile(file);
    return ref.getDownloadURL();
  }

  Future<List<String>> uploadTaskPhotos({
    required String taskId,
    required List<File> files,
  }) {
    return _uploadPhotos(folder: 'task_photos', id: taskId, files: files);
  }

  Future<List<String>> uploadMaterialRequestPhotos({
    required String requestId,
    required List<File> files,
  }) {
    return _uploadPhotos(folder: 'material_request_photos', id: requestId, files: files);
  }

  Future<List<String>> uploadDailyReportPhotos({
    required String reportId,
    required List<File> files,
  }) {
    return _uploadPhotos(folder: 'daily_report_photos', id: reportId, files: files);
  }

  Future<List<String>> _uploadPhotos({
    required String folder,
    required String id,
    required List<File> files,
  }) async {
    final urls = <String>[];
    for (var i = 0; i < files.length; i++) {
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
      final ref = _storage.ref('$folder/$id/$fileName');
      await ref.putFile(files[i]);
      urls.add(await ref.getDownloadURL());
    }
    return urls;
  }
}
