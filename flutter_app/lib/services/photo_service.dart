import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';

/// Takes photos with the camera and uploads them to Firebase Storage.
/// Paths: taskPhotos/{taskId}/..., runPhotos/{runId}/...
/// The Storage default is resolved lazily (same pattern as
/// TimeEntryService): FirebaseStorage.instance throws when
/// Firebase is not initialized, so constructing the service
/// must not touch it — tests construct fakes of this class.
class PhotoService {
  final ImagePicker _picker;
  final FirebaseStorage? _storageOverride;

  FirebaseStorage get _storage =>
      _storageOverride ?? FirebaseStorage.instance;

  PhotoService({ImagePicker? picker, FirebaseStorage? storage})
      : _picker = picker ?? ImagePicker(),
        _storageOverride = storage;

  /// Compresses image bytes to at most 1600 px on the long side
  /// at quality 80, so uploads stay small (and under the 10 MB
  /// storage-rule cap). Falls back to the original bytes when
  /// compression fails (e.g. a non-image file) — the upload
  /// must never fail because compression did.
  /// Shared helper: the chat-media and profile-photo services
  /// upload through their own Storage calls, not through here,
  /// so they should call this before uploading if they want the
  /// same treatment (see the audit report).
  static Future<Uint8List> compressImageBytes(Uint8List bytes) async {
    try {
      return await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1600,
        minHeight: 1600,
        quality: 80,
      );
    } catch (_) {
      return bytes;
    }
  }

  /// Opens the camera only - returns the picked image, or null
  /// if the user cancels. Split out from the upload so callers
  /// can tell "user cancelled" apart from "upload failed" (the
  /// offline photo queue depends on that distinction).
  Future<XFile?> takePhoto() {
    return _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70, // job-site photos do not need full resolution
    );
  }

  /// Uploads one local image file and returns its download URL.
  /// This is THE upload path: the camera flow above and the
  /// offline queue both go through here, so the storage layout
  /// ($folder/$ownerId/<timestamp>.jpg) stays identical.
  /// The bytes are compressed first (see [compressImageBytes])
  /// so task photos, run photos and every queued photo all
  /// upload small.
  Future<String> uploadFile(
      String localPath, String folder, String ownerId) async {
    final fileName = '${DateTime.now().millisecondsSinceEpoch}.jpg';
    final ref = _storage.ref().child('$folder/$ownerId/$fileName');
    // Bytes, not File: dart:io cannot compile for web, and
    // XFile.readAsBytes works on phones and on web (blob URLs
    // included). putData stores the same bytes as putFile did.
    final bytes =
        await compressImageBytes(await XFile(localPath).readAsBytes());
    await ref.putData(bytes);
    return ref.getDownloadURL();
  }

  /// Opens the camera, uploads the photo, returns its download URL.
  /// Returns null if the user cancels the camera. Throws when the
  /// upload itself fails (e.g. no connection).
  Future<String?> takePhotoAndUpload(String folder, String ownerId) async {
    final picked = await takePhoto();
    if (picked == null) return null;
    return uploadFile(picked.path, folder, ownerId);
  }
}
