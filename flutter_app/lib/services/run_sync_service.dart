import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/delivery_run.dart';
import '../models/run_stop.dart';
import '../models/stage.dart';
import '../models/task_item.dart';

/// Result of a run sync: how the run changed.
class RunSyncResult {
  /// Stops appended by rolling over from the previous run.
  final int carriedOver;

  /// Stops removed because they no longer qualify (a stop the
  /// old auto-join added, or a carried stop whose task was done,
  /// reassigned, or whose stage is no longer visible).
  final int dropped;

  /// Carried request-linked stops whose material request could
  /// not be re-pointed at this run (the re-point is retried
  /// once; a persistent failure leaves the request pointing at
  /// the old run — never silently dropped, surfaced to the
  /// caller through this count).
  final int requestRepointFailures;

  const RunSyncResult({
    this.carriedOver = 0,
    this.dropped = 0,
    this.requestRepointFailures = 0,
  });

  bool get changed => carriedOver > 0 || dropped > 0;
}

/// Client-side reconciliation of a delivery run, evaluated when
/// the run is loaded (driver run screen) or saved (manager
/// builder). One job:
///
/// * Carry-over — when a run is first reconciled, unfinished
///   stops from the driver's earlier runs roll over to the end
///   of this run, most recent first. Completed stops never
///   carry.
///
/// There is no scheduled function for this: the run document is
/// the only source of truth, and reconciliation happens at the
/// same evaluation points where the run is already being read,
/// so a run never needs a background trigger.
///
/// Tasks stay separate from runs: a driver task becoming
/// available shows up in his My Day, it never appends a stop
/// to a run. Stops the old auto-join added are dropped by the
/// prune below (unless already completed, in which case they
/// stay as history).
///
/// Sync is idempotent: it never re-carries a stop that is
/// already here, and never resurrects a completed stop. It only
/// touches runs whose date is today or in the future - past
/// runs are history.
class RunSyncService {
  /// Test-only Firestore override (a fake in tests). Production
  /// always uses the real instance: null here means "the real
  /// one", so merely reading [_db] never touches Firebase
  /// before it is initialized.
  static FirebaseFirestore? _testDb;

  @visibleForTesting
  static set testDb(FirebaseFirestore db) => _testDb = db;

  @visibleForTesting
  static void resetTestDb() => _testDb = null;

  static FirebaseFirestore get _db =>
      _testDb ?? FirebaseFirestore.instance;

  static CollectionReference<Map<String, dynamic>> get _runs =>
      _db.collection('runs');

  /// Fresh stop ids use the same convention as the run builder:
  /// a Firestore-generated document id (no extra dependency).
  static String _newStopId() => _runs.doc().id;

  /// Reconciles [run] against [allTasks] (every task in the
  /// workspace, so a carried stop's task can be checked) and
  /// the stage index. Returns what changed; persists the run
  /// only when something actually changed.
  static Future<RunSyncResult> syncRun(
    DeliveryRun run, {
    required List<TaskItem> allTasks,
    StageIndex? stageIndex,
  }) async {
    final today = DateTime.now();
    final runDay = DateTime(run.date.year, run.date.month, run.date.day);
    final todayDay = DateTime(today.year, today.month, today.day);
    if (runDay.isBefore(todayDay)) {
      // Past runs are history - never rewrite them.
      return const RunSyncResult();
    }

    final byId = {for (final t in allTasks) t.id: t};
    var stops = List<RunStop>.from(run.stops);
    var carriedOver = 0;
    var dropped = 0;

    // ---- 1. Prune stops that no longer qualify ----
    // Dropped ids are tracked so the transactional persist
    // below can re-apply the prune to the fresh doc instead of
    // overwriting it with this (possibly stale) list.
    final droppedIds = <String>{};
    final kept = <RunStop>[];
    for (final stop in stops) {
      if (stop.autoAdded) {
        // Auto-join is off: a stop the old auto-join added no
        // longer belongs on a run. A finished one stays as
        // history; an unfinished one drops off.
        if (stop.status == StopStatus.completed) {
          kept.add(stop);
        } else {
          dropped++;
          droppedIds.add(stop.id);
        }
        continue;
      }
      if (!stop.carriedOver) {
        // A planned stop whose task was deleted leaves a
        // drop-off that can never complete (completing it
        // throws NOT_FOUND on the task write). A still-pending
        // one drops off; a finished one stays as history.
        if (stop.taskId != null &&
            stop.status == StopStatus.pending &&
            !byId.containsKey(stop.taskId!)) {
          dropped++;
          droppedIds.add(stop.id);
          continue;
        }
        kept.add(stop);
        continue;
      }
      if (stop.status == StopStatus.completed) {
        // A finished stop stays finished, wherever it came from.
        kept.add(stop);
        continue;
      }
      final taskId = stop.taskId;
      if (taskId == null) {
        // A stop with no task behind it has nothing to qualify
        // against - keep it and let a person remove it.
        kept.add(stop);
        continue;
      }
      final task = byId[taskId];
      if (task == null ||
          task.status == TaskStatus.done ||
          !task.assigneeIds.contains(run.driverId)) {
        // Done another way, deleted, or reassigned away from
        // this driver - the stop drops off.
        dropped++;
        droppedIds.add(stop.id);
        continue;
      }
      if (stageIndex != null && !stageIndex.isVisibleToday(task)) {
        // Its stage was skipped (or never started) - the task
        // is not available any more.
        dropped++;
        droppedIds.add(stop.id);
        continue;
      }
      kept.add(stop);
    }
    stops = kept;

    // ---- 2. Carry-over: unfinished stops from the previous run ----
    final carried = await _carryOverStops(
      run: run,
      existing: stops,
      byId: byId,
      stageIndex: stageIndex,
    );

    // The final list is built inside the transaction below
    // (fresh doc minus pruned ids, plus these carried stops),
    // so the pre-sync list is not kept around.
    carriedOver = carried.length;

    if (carriedOver == 0 && dropped == 0) {
      return const RunSyncResult();
    }

    // Persist transactionally: read the fresh run doc inside the
    // transaction and merge this sync's changes into it, so a
    // manager edit landing at the same moment (a stop added,
    // edited, or reordered in the builder) is not overwritten.
    // The sync drops only the stops it pruned (by id) and appends
    // only carried stops not already here (by id, or by
    // carriedFromStopId so a stop is never carried twice); any
    // other fresh stop is kept as-is, in its place. With no
    // concurrent edit the result is exactly the list computed
    // above. Renumbering happens on the merged list.
    await _db.runTransaction((tx) async {
      final docRef = _runs.doc(run.id);
      final snap = await tx.get(docRef);
      if (!snap.exists) return;
      final fresh = DeliveryRun.fromFirestore(snap).stops;
      final freshIds = {for (final s in fresh) s.id};
      final alreadyCarriedFrom = {
        for (final s in fresh)
          if (s.carriedFromStopId != null) s.carriedFromStopId!,
      };
      final merged = <RunStop>[
        for (final s in fresh)
          if (!droppedIds.contains(s.id)) s,
        for (final s in carried)
          if (!freshIds.contains(s.id) &&
              (s.carriedFromStopId == null ||
                  !alreadyCarriedFrom.contains(s.carriedFromStopId!)))
            s,
      ];
      final renumbered = [
        for (var i = 0; i < merged.length; i++)
          merged[i].copyWith(orderIndex: i),
      ];
      tx.update(docRef, {
        'stops': renumbered.map((s) => s.toMap()).toList(),
      });
    });
    // A carried request-linked stop moves its request to this
    // run: the request's runId would otherwise keep pointing
    // at yesterday's run. The request stays onRun — only the
    // run changes. Retried once; a persistent failure is
    // reported in the result (and logged) instead of being
    // swallowed — the run is already saved, but the request
    // must not silently keep pointing at the old run.
    var requestRepointFailures = 0;
    final carriedRequestIds = {
      for (final s in carried)
        if (s.materialRequestId != null) s.materialRequestId!,
    };
    if (carriedRequestIds.isNotEmpty) {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final batch = _db.batch();
          for (final requestId in carriedRequestIds) {
            batch.update(
              _db
                  .collection('materialRequests')
                  .doc(requestId),
              {'runId': run.id},
            );
          }
          await batch.commit();
          break;
        } catch (e) {
          if (attempt == 1) {
            requestRepointFailures = carriedRequestIds.length;
            debugPrint(
                'RunSync: could not re-point ${carriedRequestIds.length} '
                'material request(s) to run ${run.id}: $e');
          }
        }
      }
    }
    return RunSyncResult(
      carriedOver: carriedOver,
      dropped: dropped,
      requestRepointFailures: requestRepointFailures,
    );
  }

  /// Unfinished stops from the driver's earlier runs, most
  /// recent first. Pending and failed stops roll over;
  /// completed stops never do. Every earlier run is swept — not
  /// just the most recent one — so a stop missed twice (or
  /// sitting on an older run while a newer run has none) still
  /// rolls forward instead of being stranded. A stop whose task
  /// was done another way or reassigned drops instead. Each
  /// source stop carries over at most once per run (tracked by
  /// carriedFromStopId), and a task already linked on this run
  /// is never carried twice.
  static Future<List<RunStop>> _carryOverStops({
    required DeliveryRun run,
    required List<RunStop> existing,
    required Map<String, TaskItem> byId,
    StageIndex? stageIndex,
  }) async {
    // Runs are read/written directly from Firestore (there is no
    // RunService - the run screens use the collection directly).
    final snap = await _runs
        .where('driverId', isEqualTo: run.driverId)
        .get();
    final previous = snap.docs
        .map((doc) => DeliveryRun.fromFirestore(doc))
        .toList();
    final earlier = previous
        .where((r) => r.id != run.id && r.date.isBefore(run.date))
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (earlier.isEmpty) return const [];

    final alreadyCarried = {
      for (final s in existing)
        if (s.carriedFromStopId != null) s.carriedFromStopId!,
    };
    final linkedTaskIds = {
      for (final s in existing) if (s.taskId != null) s.taskId!,
    };
    final carried = <RunStop>[];
    for (final source in earlier) {
      for (final stop in source.stops) {
        if (stop.status == StopStatus.completed) continue;
        // Already here — either as this exact stop, or as a
        // carry of it from a newer run (a carried stop keeps
        // its source's id in carriedFromStopId).
        if (alreadyCarried.contains(stop.id)) continue;
        if (stop.carriedFromStopId != null &&
            alreadyCarried.contains(stop.carriedFromStopId!)) {
          continue;
        }
        if (stop.taskId != null) {
          if (linkedTaskIds.contains(stop.taskId!)) continue;
          final task = byId[stop.taskId!];
          if (task == null ||
              task.status == TaskStatus.done ||
              !task.assigneeIds.contains(run.driverId)) {
            continue;
          }
          if (stageIndex != null && !stageIndex.isVisibleToday(task)) {
            continue;
          }
        }
        carried.add(RunStop(
          id: _newStopId(),
          orderIndex: 0, // Renumbered by the caller.
          title: stop.title,
          address: stop.address,
          notes: stop.notes,
          kind: stop.kind,
          status: StopStatus.pending,
          scheduledTime: stop.scheduledTime,
          items: stop.items,
          failReason: stop.failReason,
          failNote: stop.failNote,
          taskId: stop.taskId,
          materialRequestId: stop.materialRequestId,
          carriedOver: true,
          carriedFromStopId: stop.id,
        ));
        // A stop carried from this pass must not carry again
        // from an older run holding the same source stop —
        // either the stop itself or the stop it was carried
        // from.
        alreadyCarried.add(stop.id);
        if (stop.carriedFromStopId != null) {
          alreadyCarried.add(stop.carriedFromStopId!);
        }
        if (stop.taskId != null) linkedTaskIds.add(stop.taskId!);
      }
    }
    return carried;
  }
}
