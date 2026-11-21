import 'dart:math';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'photo_service.dart';

/// Profile photos: one file per upload, `profilePhotos/<uid>/…`.
/// Pick from camera or gallery (downscaled, quality 70, like
/// task photos — the picker returns JPEG), upload as
/// image/jpeg, and return the download URL for the caller to
/// save on the user doc with AuthService.updatePhotoUrl. The
/// storage rules only allow a user to write their own files.
///
/// Audit P1 — never overwrite in place: the old layout
/// (`profilePhotos/<uid>.jpg`) revoked the previous download
/// token the moment a new upload landed, so if the user-doc
/// write after the upload failed, the doc kept a dead URL and
/// the avatar was broken until the next upload. Each upload
/// now goes to a unique path, so the old URL keeps working
/// until the doc write succeeds; the caller deletes the old
/// file only after that write (see WorkerProfileScreen).
/// NOTE: the unique path needs storage.rules to match
/// `profilePhotos/{uid}/{fileName}` gated on
/// `uid == request.auth.uid` — the old rule only allowed the
/// single `<uid>.jpg` file. Until that rule lands, uploads to
/// the new path are denied.
class ProfilePhotoService {
  final FirebaseStorage _storage;
  final ImagePicker _picker;

  ProfilePhotoService({FirebaseStorage? storage, ImagePicker? picker})
      : _storage = storage ?? FirebaseStorage.instance,
        _picker = picker ?? ImagePicker();

  /// Camera or gallery photo, downscaled like task photos.
  /// Null when the user cancels.
  Future<XFile?> pickPhoto(ImageSource source) {
    return _picker.pickImage(source: source, imageQuality: 70);
  }

  /// Uploads the picked photo for [uid] to a unique path and
  /// returns its download URL. The path is unique per upload
  /// (milliseconds + random suffix) so re-uploading never
  /// invalidates the URL already on the user doc. Throws when
  /// the upload fails.
  Future<String> uploadPhoto({
    required String uid,
    required XFile file,
  }) async {
    final unique =
        '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}';
    final ref = _storage.ref().child('profilePhotos/$uid/$unique.jpg');
    // Bytes, not File: dart:io cannot compile for web.
    // putData with the same content type stores the same file.
    // Compressed first so the stored file stays small.
    final bytes =
        await PhotoService.compressImageBytes(await file.readAsBytes());
    await ref.putData(
      bytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );
    return ref.getDownloadURL();
  }

  /// Deletes the file behind a profile-photo download URL.
  /// Best-effort: a missing file (or an unparseable URL) is a
  /// no-op, never a throw — the caller uses this to clean up
  /// the previous photo after the doc write succeeded, and a
  /// cleanup failure must never surface as an upload failure.
  Future<void> deletePhotoByUrl(String url) async {
    try {
      await _storage.refFromURL(url).delete();
    } catch (_) {
      // Already gone, or not a Storage URL — nothing to do.
    }
  }
}
