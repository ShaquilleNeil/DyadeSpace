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
}
