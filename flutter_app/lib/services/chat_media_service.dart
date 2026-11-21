import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'photo_service.dart';

/// Picks, records and uploads chat media — photos, videos and
/// voice notes — to `chatMedia/<folder>/<messageId>.<ext>`.
/// For a 1:1 or team chat [folder] is the conversation id; for
/// a broadcast (one message, many conversations) it is
/// 'broadcast' and the same URL is shared by every recipient.
///
/// Uploads carry an explicit content type so the storage rules
/// (image/*, video/*, audio/* under chatMedia/) match. Voice
/// notes are chat-only: nothing here touches tasks.
class ChatMediaService {
  final ImagePicker _picker;
  final FirebaseStorage _storage;
  final AudioRecorder _recorder;

  ChatMediaService(
      {ImagePicker? picker, FirebaseStorage? storage, AudioRecorder? recorder})
      : _picker = picker ?? ImagePicker(),
        _storage = storage ?? FirebaseStorage.instance,
        _recorder = recorder ?? AudioRecorder();

  UploadTask? _currentTask;

  /// A client-side id for the storage path: the message doc
  /// itself does not exist yet when the file is uploaded.
  static String newMessageId() =>
      '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}';

  /// MIME type for a local file, from its extension. Unknown
  /// extensions fall back to octet-stream (the rules will deny
  /// those — only image/video/audio may be stored).
  static String contentTypeFor(String path) {
    final ext = path.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'm4a':
        return 'audio/mp4';
      case 'aac':
        return 'audio/aac';
      default:
        return 'application/octet-stream';
    }
  }

  /// Storage caps chat media at 10 MB: anything bigger fails
  /// server-side after a long upload, so the size is checked
  /// up front (see [uploadChatMedia] / [uploadChatMediaBytes])
  /// and the user is told before any bytes go up.
  static const int maxUploadBytes = 10 * 1024 * 1024;

    /// Cancels the upload in progress, if any. The awaiting
  /// [uploadChatMedia] throws a FirebaseException with code
  /// 'canceled' — callers treat that as a user cancel, not a
  /// failure, so no retry is offered for it.
  void cancelUpload() {
    _currentTask?.cancel();
    _currentTask = null;
  }

  /// Uploads one local file and returns its download URL.
  /// [onProgress] reports 0.0–1.0 as bytes land. Throws when
  /// the upload fails (or is cancelled — see [cancelUpload]).
  Future<String> uploadChatMedia({
    required String localPath,
    required String folder,
    required String messageId,
    void Function(double progress)? onProgress,
  }) async {
    final ext = localPath.split('.').last.toLowerCase();
    final ref =
        _storage.ref().child('chatMedia/$folder/$messageId.$ext');
    // Photos are compressed before upload so the stored file
    // stays small; video and audio go up untouched.
    final UploadTask task;
    if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'heic') {
      final bytes = await PhotoService.compressImageBytes(
          await File(localPath).readAsBytes());
      // The stored file is the compressed bytes: check those.
      if (bytes.length > maxUploadBytes) {
        throw ChatMediaTooLargeException(bytes.length);
      }
      task = ref.putData(
        bytes,
        SettableMetadata(contentType: contentTypeFor(localPath)),
      );
    } else {
      // Video/audio go up untouched: check the file before a
      // long upload that the 10 MB cap would reject anyway.
      final size = await File(localPath).length();
      if (size > maxUploadBytes) {
        throw ChatMediaTooLargeException(size);
      }
      task = ref.putFile(
        File(localPath),
        SettableMetadata(contentType: contentTypeFor(localPath)),
      );
    }
    return _completeUpload(ref, task, onProgress);
  }

  /// Uploads already-read bytes and returns the download URL —
  /// the web path. On web there is no local file behind the
  /// picker's blob URL, so `File(localPath)` cannot read it;
  /// callers read the picked file's bytes (XFile.readAsBytes
  /// works on both platforms) and pass them here instead.
  /// Photos are compressed the same way as the path upload.
  Future<String> uploadChatMediaBytes({
    required Uint8List bytes,
    required String filename,
    required String folder,
    required String messageId,
    void Function(double progress)? onProgress,
  }) async {
    final ext = filename.split('.').last.toLowerCase();
    final ref =
        _storage.ref().child('chatMedia/$folder/$messageId.$ext');
    final UploadTask task;
    if (ext == 'jpg' || ext == 'jpeg' || ext == 'png' || ext == 'heic') {
      final compressed = await PhotoService.compressImageBytes(bytes);
      if (compressed.length > maxUploadBytes) {
        throw ChatMediaTooLargeException(compressed.length);
      }
      task = ref.putData(
        compressed,
        SettableMetadata(contentType: contentTypeFor(filename)),
      );
    } else {
      // Video/audio go up untouched: check before the upload
      // starts, not after it fails against the 10 MB cap.
      if (bytes.length > maxUploadBytes) {
        throw ChatMediaTooLargeException(bytes.length);
      }
      task = ref.putData(
        bytes,
        SettableMetadata(contentType: contentTypeFor(filename)),
      );
    }
    return _completeUpload(ref, task, onProgress);
  }

  /// Shared tail of both uploads: progress reporting, await,
  /// and the download URL. (Extracted so the phone path and the
  /// web bytes path cannot drift apart.)
  Future<String> _completeUpload(
    Reference ref,
    UploadTask task,
    void Function(double progress)? onProgress,
  ) async {
    _currentTask = task;
    final sub = task.snapshotEvents.listen((snap) {
      if (snap.totalBytes > 0) {
        onProgress?.call(snap.bytesTransferred / snap.totalBytes);
      }
    });
    try {
      await task;
    } finally {
      await sub.cancel();
      _currentTask = null;
    }
    return ref.getDownloadURL();
  }

  /// Camera or gallery photo, downscaled like task photos
  /// (quality 70). Null when the user cancels.
  Future<XFile?> pickPhoto(ImageSource source) {
    return _picker.pickImage(source: source, imageQuality: 70);
  }

  /// Camera or gallery video, capped at 2 minutes by the
  /// picker itself. Null when the user cancels.
  Future<XFile?> pickVideo(ImageSource source) {
    return _picker.pickVideo(
      source: source,
      maxDuration: const Duration(seconds: 120),
    );
  }

  /// Reads a local video file's length without playing it, so
  /// the bubble can show the duration before anyone taps play.
  /// Null when the file cannot be read.
  Future<int?> videoDurationSeconds(String localPath) async {
    final controller = VideoPlayerController.file(File(localPath));
    try {
      await controller.initialize();
      return controller.value.duration.inSeconds;
    } catch (_) {
      return null;
    } finally {
      await controller.dispose();
    }
  }

  // --- Voice notes (chat only) ---

  /// True when the OS will let us record (asks for the mic
  /// permission the first time).
  Future<bool> get canRecord async => _recorder.hasPermission();

  /// Starts recording to a temp .m4a file (AAC-LC) and returns
  /// its path. Throws when recording cannot start.
  Future<String> startVoiceNote() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    return path;
  }

  /// Stops recording and returns the file path, or null when
  /// nothing was recorded.
  Future<String?> stopVoiceNote() => _recorder.stop();

  /// Stops and deletes the in-progress recording (drag-away
  /// cancel). Never throws.
  Future<void> discardVoiceNote() async {
    try {
      await _recorder.cancel();
    } catch (_) {
      // Nothing to discard — already stopped or never started.
    }
  }

  /// Release the recorder when the app no longer needs it.
  /// The service lives for the app session, so this is rarely
  /// called — it exists so tests and a future sign-out can
  /// clean up.
  Future<void> disposeRecorder() => _recorder.dispose();
}

/// Thrown before an upload starts when the file is over the
/// 10 MB storage cap. Callers show [AppStrings.mediaTooLarge]
/// for this instead of the generic upload failure — the user
/// needs to know the file itself is too big, not that the
/// network failed. Carries the size so the message can name it.
class ChatMediaTooLargeException implements Exception {
  final int bytes;
  const ChatMediaTooLargeException(this.bytes);
  @override
  String toString() => 'Chat media too large: $bytes bytes';
}
