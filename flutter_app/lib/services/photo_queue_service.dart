import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/delivery_run.dart';
import '../models/run_stop.dart';
import '../models/task_update.dart';
import 'photo_service.dart';

/// One photo waiting to upload. [kind] is:
/// - 'taskDone': a task completion photo (attaches to the task,
///   clears photoPending when it was the last queued one).
/// - 'runStop': a delivery stop completion photo (sets the
///   stop's photoUrl, clears photoPending).
/// - 'taskUpdate': a photo posted in a task's Updates thread
///   (creates the update doc once the photo lands; [authorId],
///   [authorName] and [text] are the post itself, parked with
///   the photo so the post is not lost offline).
/// - 'runFail': a failure photo for a failed stop (attaches the
///   photoUrl only — the stop stays failed, status/reason
///   untouched).
/// - 'runExtra': an extra proof photo on a stop (appended to
///   the stop's photoUrls list).
class PhotoQueueEntry {
  final String id;
  final String kind;

  /// Where the image file is parked on this device (under the
  /// app documents dir, so an OS cache purge cannot eat it).
  final String localPath;

  /// Storage folder the photo belongs to ('taskPhotos' /
  /// 'runPhotos') - uploads reuse PhotoService.uploadFile, so
  /// the final path scheme matches a live upload exactly.
  final String folder;
  final String? taskId;
  final String? runId;
  final String? stopId;

  /// Task-update posts only: the post the photo belongs to.
  final String? authorId;
  final String? authorName;
  final String? text;

  final DateTime queuedAt;

  /// Upload/write attempts so far. A permanently failing entry
  /// is dropped after [PhotoQueueService.maxAttempts] instead
  /// of being retried on every pass forever.
  final int attempts;

  const PhotoQueueEntry({
    required this.id,
    required this.kind,
    required this.localPath,
    required this.folder,
    this.taskId,
    this.runId,
    this.stopId,
    this.authorId,
    this.authorName,
    this.text,
    required this.queuedAt,
    this.attempts = 0,
  });

  PhotoQueueEntry copyWith({int? attempts}) {
    return PhotoQueueEntry(
      id: id,
      kind: kind,
      localPath: localPath,
      folder: folder,
      taskId: taskId,
      runId: runId,
      stopId: stopId,
      authorId: authorId,
      authorName: authorName,
      text: text,
      queuedAt: queuedAt,
      attempts: attempts ?? this.attempts,
    );
  }

  String? get ownerId =>
      kind == 'taskDone' || kind == 'taskUpdate' ? taskId : runId;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind,
      'localPath': localPath,
      'folder': folder,
      'taskId': taskId,
      'runId': runId,
      'stopId': stopId,
      'authorId': authorId,
      'authorName': authorName,
      'text': text,
      'queuedAt': queuedAt.toIso8601String(),
      'attempts': attempts,
    };
  }

  factory PhotoQueueEntry.fromJson(Map<String, dynamic> json) {
    return PhotoQueueEntry(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? '',
      localPath: json['localPath'] as String? ?? '',
      folder: json['folder'] as String? ?? '',
      taskId: json['taskId'] as String?,
      runId: json['runId'] as String?,
      stopId: json['stopId'] as String?,
      authorId: json['authorId'] as String?,
      authorName: json['authorName'] as String?,
      text: json['text'] as String?,
      queuedAt:
          DateTime.tryParse(json['queuedAt'] as String? ?? '') ??
              DateTime.now(),
      attempts: json['attempts'] as int? ?? 0,
    );
  }
}

/// Offline photo queue. When a completion photo cannot upload
/// (no signal in a basement, a parkade...), the task/stop is
/// still closed on the spot with photoPending set, the image is
/// copied somewhere safe on the device, and this service uploads
/// it later - at app start and whenever connectivity returns -
/// then performs the completion write the live flow would have
/// done. Every public method swallows its own errors: the queue
/// must never break the screen that called it.
class PhotoQueueService {
  static const String _prefsKey = 'photo_upload_queue_v1';

  /// The Firestore default is resolved lazily (same pattern as
  /// TimeEntryService): FirebaseFirestore.instance throws when
  /// Firebase is not initialized, so constructing the service
  /// must not touch it — tests construct fakes of this class.
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  final PhotoService _photos;
  bool _processing = false;

  /// Live view of the parked entries, for screens that show a
  /// pending row while a photo is still uploading. Emits the
  /// current list on listen, then every mutation (every
  /// [_writeEntries] is a mutation, so nothing is missed).
  final StreamController<List<PhotoQueueEntry>> _entriesController =
      StreamController<List<PhotoQueueEntry>>.broadcast();

  Stream<List<PhotoQueueEntry>> watchEntries() async* {
    yield await _readEntries();
    yield* _entriesController.stream;
  }

  PhotoQueueService({FirebaseFirestore? db, PhotoService? photos})
      : _dbOverride = db,
        _photos = photos ?? PhotoService();

  /// Parks [sourcePath] under <app documents>/pending_uploads/
  /// and records the entry. Fire-and-forget safe: also kicks off
  /// a processing pass in case the failure was a blip and we are
  /// actually back online already.
  /// [authorId]/[authorName]/[text] are for 'taskUpdate' only:
  /// the Updates-thread post the photo belongs to.
  /// Returns true when the photo was parked and the entry
  /// recorded; false when parking failed — the caller must keep
  /// the post and show an error, never clear the composer for a
  /// post that will never land. Never throws: the run/task
  /// completion callers fire-and-forget and ignore the result.
  Future<bool> enqueue({
    required String kind,
    required String sourcePath,
    required String folder,
    String? taskId,
    String? runId,
    String? stopId,
    String? authorId,
    String? authorName,
    String? text,
  }) async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory('${docs.path}/pending_uploads');
      await dir.create(recursive: true);
      final id = DateTime.now().microsecondsSinceEpoch.toString();
      final parkedPath = '${dir.path}/$id.jpg';
      await File(sourcePath).copy(parkedPath);
      final entries = await _readEntries();
      entries.add(PhotoQueueEntry(
        id: id,
        kind: kind,
        localPath: parkedPath,
        folder: folder,
        taskId: taskId,
        runId: runId,
        stopId: stopId,
        authorId: authorId,
        authorName: authorName,
        text: text,
        queuedAt: DateTime.now(),
      ));
      await _writeEntries(entries);
      unawaited(processQueue());
      return true;
    } catch (_) {
      // Parking failed (camera temp file gone, storage error...):
      // report it so the caller can keep the post and show an
      // error. The post is lost only if the caller ignores the
      // false — the old code swallowed this and cleared the
      // composer anyway, which is how a photo post vanished
      // with no trace.
      return false;
    }
  }

  /// Max upload/write attempts for one entry before it is
  /// dropped as permanently failed (see [processQueue]).
  static const int maxAttempts = 3;

  /// Uploads queued photos oldest-first and performs each
  /// completion write. A failure no longer wedges the queue
  /// behind one dead entry:
  /// - a parked file that no longer exists is dropped at once
  ///   (it can never upload) and the rest are processed;
  /// - an upload/write failure counts an attempt; at
  ///   [maxAttempts] the entry is dropped instead of being
  ///   retried on every pass forever;
  /// - a dropped entry clears its task/stop photoPending flag,
  ///   so it never stays true forever.
  /// An upload failure still stops the pass (still offline,
  /// presumably) unless the failed entry was just dropped —
  /// a write failure is per-entry, so the pass continues.
  /// Re-entrant calls are no-ops while a pass is running.
  Future<void> processQueue() async {
    if (_processing) return;
    _processing = true;
    try {
      final entries = await _readEntries();
      final remaining = [...entries];
      var changed = false;
      for (final entry in entries) {
        // The parked file is gone (deleted outside the app, an
        // OS purge...): the photo can never upload. Drop the
        // entry now and clear its pending flag instead of
        // retrying the same head entry on every pass forever
        // and blocking every newer photo behind it.
        if (!await File(entry.localPath).exists()) {
          remaining.removeWhere((e) => e.id == entry.id);
          changed = true;
          await _clearPendingFlag(entry, remaining);
          continue;
        }
        final String url;
        try {
          // A hung upload on a flaky connection used to wedge
          // the queue: _processing stayed true and every later
          // pass was a no-op until the app restarted. Cap it —
          // a timeout counts as a failure and the entry waits
          // for the next pass like any other failed upload.
          url = await _photos
              .uploadFile(entry.localPath, entry.folder, entry.ownerId ?? '')
              .timeout(const Duration(seconds: 60));
        } catch (_) {
          // Still offline? Do not count it: an offline pass
          // must never burn attempts toward dropping a photo
          // that only needs signal. Only a failure while
          // online counts — that is an entry-specific problem
          // (oversize file, rejected upload...). A permanently
          // failing upload reaches [maxAttempts] over
          // successive passes and is dropped (below) instead
          // of wedging the queue — and once it is dropped the
          // pass continues past it to the newer photos.
          if (!await _isOnline()) break;
          final dropped = await _recordFailure(entry, remaining);
          changed = true;
          if (dropped) continue;
          break;
        }
        try {
          await _writeCompletion(
            entry,
            url,
            others: remaining.where((e) => e.id != entry.id).toList(),
          );
        } catch (_) {
          // A write failure is per-entry (the upload already
          // landed): count it and move on to the next photo
          // instead of stopping the whole pass.
          await _recordFailure(entry, remaining);
          changed = true;
          continue;
        }
        remaining.removeWhere((e) => e.id == entry.id);
        changed = true;
        try {
          await File(entry.localPath).delete();
        } catch (_) {
          // A leftover file is harmless; the entry is gone.
        }
      }
      if (changed) await _writeEntries(remaining);
    } catch (_) {
      // Never throw to callers (app start, connectivity listener).
    } finally {
      _processing = false;
    }
  }

  /// True when the device reports any connection. Only used
  /// to tell "still offline" apart from "this photo will
  /// never upload": an offline pass must not burn attempts.
  /// When the check itself fails, assume online — a failure
  /// the OS cannot explain is more likely entry-specific.
  Future<bool> _isOnline() async {
    try {
      final results = await Connectivity().checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return true;
    }
  }

  /// Counts one failed attempt for [entry] in [remaining]. At
  /// [maxAttempts] the entry is dropped as permanently failed
  /// and its task/stop pending flag is cleared, so a dead photo
  /// can never keep photoPending true forever or block the
  /// photos behind it. Returns true when the entry was dropped.
  Future<bool> _recordFailure(
      PhotoQueueEntry entry, List<PhotoQueueEntry> remaining) async {
    final idx = remaining.indexWhere((e) => e.id == entry.id);
    if (idx < 0) return false;
    final attempts = entry.attempts + 1;
    if (attempts >= maxAttempts) {
      remaining.removeAt(idx);
      await _clearPendingFlag(entry, remaining);
      try {
        await File(entry.localPath).delete();
      } catch (_) {
        // A leftover parked file is harmless; the entry is gone.
      }
      return true;
    }
    remaining[idx] = entry.copyWith(attempts: attempts);
    return false;
  }

  /// A dropped entry must not leave its task/stop claiming a
  /// photo is still coming: clear the pending flag (for a task,
  /// only when no other queued photo for it remains).
  Future<void> _clearPendingFlag(
      PhotoQueueEntry entry, List<PhotoQueueEntry> remaining) async {
    try {
      if (entry.kind == 'taskDone') {
        final ref = _db.collection('tasks').doc(entry.taskId);
        final snap = await ref.get();
        if (!snap.exists) return;
        final stillQueued = remaining.any(
            (e) => e.kind == 'taskDone' && e.taskId == entry.taskId);
        await ref.update({'photoPending': stillQueued});
        return;
      }
      if (entry.kind == 'runStop' || entry.kind == 'runFail') {
        await _updateRunStop(
          entry.runId,
          entry.stopId,
          (s) => s.copyWith(photoPending: false),
        );
      }
      // 'taskUpdate' posts and 'runExtra' photos carry no
      // pending flag, and unknown kinds were never placed
      // anywhere: the drop itself is the whole cleanup.
    } catch (_) {
      // Best effort: a failed clear must not break the pass.
    }
  }

  /// The write the live flow would have done, now that the photo
  /// is up. A task/run that no longer exists is treated as
  /// handled (the entry is dropped) rather than retried forever.
  /// Unknown kinds are also dropped: an entry this build cannot
  /// place must not block the rest of the queue forever.
  Future<void> _writeCompletion(
    PhotoQueueEntry entry,
    String url, {
    required List<PhotoQueueEntry> others,
  }) async {
    if (entry.kind == 'taskDone') {
      final ref = _db.collection('tasks').doc(entry.taskId);
      final snap = await ref.get();
      if (!snap.exists) return;
      // Only clear the pending flag when this was the task's
      // last queued photo.
      final stillQueued = others
          .any((e) => e.kind == 'taskDone' && e.taskId == entry.taskId);
      await ref.update({
        'photoUrls': FieldValue.arrayUnion([url]),
        'photoPending': stillQueued,
      });
      return;
    }
    if (entry.kind == 'taskUpdate') {
      final ref = _db.collection('tasks').doc(entry.taskId);
      final snap = await ref.get();
      if (!snap.exists) return;
      // The post itself was parked with the photo: create the
      // Updates-thread doc the live flow would have posted.
      await ref.collection('updates').add(TaskUpdate(
        id: '',
        taskId: entry.taskId ?? '',
        authorId: entry.authorId ?? '',
        authorName: entry.authorName ?? '',
        text: entry.text ?? '',
        photoUrl: url,
      ).toMap());
      return;
    }
    if (entry.kind == 'runStop') {
      await _updateRunStop(
        entry.runId,
        entry.stopId,
        (s) => s.copyWith(photoUrl: url, photoPending: false),
      );
      return;
    }
    if (entry.kind == 'runFail') {
      // Failure evidence only: attach the photo, leave the
      // stop failed with its reason/note untouched.
      await _updateRunStop(
        entry.runId,
        entry.stopId,
        (s) => s.copyWith(photoUrl: url, photoPending: false),
      );
      return;
    }
    if (entry.kind == 'runExtra') {
      // Extra proof photo: appended to the stop's photo list,
      // never replacing the completion photo.
      await _updateRunStop(
        entry.runId,
        entry.stopId,
        (s) => s.copyWith(photoUrls: [...s.photoUrls, url]),
      );
      return;
    }
  }

  /// Applies [change] to one stop of one run (whole-array write,
  /// the same write the driver screen uses). A run/stop that no
  /// longer exists is a no-op — the entry is dropped, not
  /// retried forever.
  Future<void> _updateRunStop(
    String? runId,
    String? stopId,
    RunStop Function(RunStop stop) change,
  ) async {
    final ref = _db.collection('runs').doc(runId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final run = DeliveryRun.fromFirestore(snap);
    if (!run.stops.any((s) => s.id == stopId)) return;
    final stops = run.stops
        .map((s) => s.id == stopId ? change(s) : s)
        .toList();
    await ref.update({'stops': stops.map((s) => s.toMap()).toList()});
  }

  Future<List<PhotoQueueEntry>> _readEntries() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => PhotoQueueEntry.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeEntries(List<PhotoQueueEntry> entries) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(entries.map((e) => e.toJson()).toList()));
    // Every mutation is a mutation of the live list too: screens
    // showing pending rows update from this, so a parked post
    // appears at once and disappears the moment it lands.
    if (!_entriesController.isClosed) {
      _entriesController.add(List.unmodifiable(entries));
    }
  }
}
