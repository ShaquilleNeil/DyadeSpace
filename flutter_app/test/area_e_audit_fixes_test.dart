import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dyadespace/models/delivery_run.dart';
import 'package:dyadespace/models/material_request.dart';
import 'package:dyadespace/models/run_stop.dart';
import 'package:dyadespace/models/stage.dart';
import 'package:dyadespace/models/task_item.dart';
import 'package:dyadespace/services/material_request_service.dart';
import 'package:dyadespace/services/run_sync_service.dart';
import 'package:dyadespace/services/stage_service.dart';
import 'package:dyadespace/services/task_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// Area E audit fixes (Nov 21, 2026): tolerant model parsing,
/// transactional request attaches, server-timestamp createdAt,
/// template guard return values, chunked deletes, the roadmap
/// claim, multi-run carry-over, and the loading stage lock.
void main() {
  // ---------- Tolerant parsing (audit P1) ----------

  group('tolerant parsing', () {
    test('TaskItem.fromMap drops malformed list elements', () {
      final task = TaskItem.fromMap('t1', {
        'title': 'Paint',
        'siteId': 'site-1',
        'createdBy': 'admin-1',
        // One bad element in each list must not fail the doc.
        'materials': ['Primer', 42, null, {'weird': true}],
        'materialsChecked': ['Primer', 7],
        'photoUrls': ['https://x/y.jpg', 99],
        'assigneeIds': ['worker-1', 5],
      });
      expect(task.materials, ['Primer']);
      expect(task.materialsChecked, ['Primer']);
      expect(task.photoUrls, ['https://x/y.jpg']);
      expect(task.assigneeIds, ['worker-1']);
    });

    test('TaskItem.fromMap treats a non-list as empty', () {
      final task = TaskItem.fromMap('t1', {
        'title': 'Paint',
        'siteId': 'site-1',
        'createdBy': 'admin-1',
        'materials': 'not-a-list',
        'photoUrls': 42,
      });
      expect(task.materials, isEmpty);
      expect(task.photoUrls, isEmpty);
    });

    test('RunStop.fromMap drops malformed items and photoUrls', () {
      final stop = RunStop.fromMap({
        'id': 's1',
        'title': 'Pickup',
        'items': [
          {'label': 'Counter', 'done': true},
          'not-a-map',
          12,
          {'label': 'Sink', 'done': false},
        ],
        'photoUrls': ['https://x/a.jpg', 3, null],
      });
      expect(stop.items.map((i) => i.label), ['Counter', 'Sink']);
      expect(stop.items.first.done, isTrue);
      expect(stop.photoUrls, ['https://x/a.jpg']);
    });

    test('DeliveryRun.fromMap drops malformed stops', () {
      final run = DeliveryRun.fromMap('r1', {
        'date': Timestamp.fromDate(DateTime(2026, 11, 21)),
        'driverId': 'driver-1',
        'stops': [
          {'id': 's1', 'title': 'One'},
          'not-a-map',
          {'id': 's2', 'title': 'Two'},
        ],
      });
      expect(run.stops.map((s) => s.id), ['s1', 's2']);
    });
  });

  // ---------- Span day index (audit P2) ----------

  group('spanDayIndex', () {
    TaskItem task(DateTime? start, DateTime? due) => TaskItem(
          id: 'x',
          title: 't',
          siteId: 's',
          createdBy: 'u',
          startDate: start,
          dueDate: due,
        );

    test('is null when today is outside the window', () {
      final now = DateTime.now();
      expect(
          task(now.subtract(const Duration(days: 5)),
                  now.subtract(const Duration(days: 2)))
              .spanDayIndex,
          isNull);
      expect(
          task(now.add(const Duration(days: 2)),
                  now.add(const Duration(days: 5)))
              .spanDayIndex,
          isNull);
    });

    test('is 1-based inside the window', () {
      final now = DateTime.now();
      final t = task(now.subtract(const Duration(days: 1)),
          now.add(const Duration(days: 2)));
      expect(t.spanTotalDays, 4);
      expect(t.spanDayIndex, 2);
    });
  });

  // ---------- Loading stage index (audit P2) ----------

  group('StageIndex.loading', () {
    test('locks staged tasks, leaves the rest alone', () {
      final index = StageIndex.loading();
      expect(index.isLoading, isTrue);
      final staged = TaskItem(
          id: 't1',
          title: 'a',
          siteId: 's',
          createdBy: 'u',
          stageId: 'stage-1');
      final plain = TaskItem(
          id: 't2', title: 'b', siteId: 's', createdBy: 'u');
      expect(index.isLockedByStage(staged), isTrue);
      expect(index.isLockedByStage(plain), isFalse);
      // Visibility is untouched: nothing hides while loading.
      expect(index.isVisibleToday(staged), isTrue);
      expect(index.stageOf(staged), isNull);
      expect(index.statusOf(const Stage(
          id: 'stage-1', siteId: 's', name: 'S', order: 1)),
          StageStatus.locked);
    });
  });

  // ---------- Material requests (audit P1/P2) ----------

  group('MaterialRequestService', () {
    late FakeFirebaseFirestore db;
    late MaterialRequestService service;

    setUp(() {
      db = FakeFirebaseFirestore();
      service = MaterialRequestService(db: db);
    });

    MaterialRequest request({
      String id = 'req-1',
      MaterialRequestStatus status = MaterialRequestStatus.approved,
    }) =>
        MaterialRequest(
          id: id,
          requesterId: 'worker-1',
          requesterName: 'Wendy Worker',
          siteId: 'site-1',
          item: 'Counter',
          quantity: 2,
          status: status,
          createdAt: DateTime(2020, 1, 1),
        );

    Future<void> seedRun(String id, {List<RunStop> stops = const []}) async {
      await db.collection('runs').doc(id).set(DeliveryRun(
            id: id,
            date: DateTime(2026, 11, 21),
            driverId: 'driver-1',
            stops: stops,
          ).toMap());
    }

    test('attachToRun appends the stop and moves the request', () async {
      await seedRun('run-1');
      await db
          .collection('materialRequests')
          .doc('req-1')
          .set(request().toMap());
      final runDoc =
          await db.collection('runs').doc('run-1').get();
      final run = DeliveryRun.fromFirestore(runDoc);

      await service.attachToRun(
          request: request(), run: run, siteName: 'Maple Court');

      final after = DeliveryRun.fromFirestore(
          await db.collection('runs').doc('run-1').get());
      expect(after.stops.length, 1);
      expect(after.stops.first.materialRequestId, 'req-1');
      expect(after.stops.first.kind, StopKind.pickup);
      final reqDoc = await db
          .collection('materialRequests')
          .doc('req-1')
          .get();
      expect(reqDoc.data()?['status'], 'onRun');
      expect(reqDoc.data()?['runId'], 'run-1');
    });

    test('attachToRun refuses a request that is no longer approved',
        () async {
      await seedRun('run-1');
      await db.collection('materialRequests').doc('req-1').set(
          request(status: MaterialRequestStatus.denied).toMap());

      final run = DeliveryRun.fromFirestore(
          await db.collection('runs').doc('run-1').get());
      await expectLater(
          service.attachToRun(
              request: request(status: MaterialRequestStatus.denied),
              run: run,
              siteName: 'Maple Court'),
          throwsStateError);
      final after = DeliveryRun.fromFirestore(
          await db.collection('runs').doc('run-1').get());
      expect(after.stops, isEmpty);
      final reqDoc = await db
          .collection('materialRequests')
          .doc('req-1')
          .get();
      expect(reqDoc.data()?['status'], 'denied');
    });

    test('attachToRun refuses a missing run', () async {
      await db
          .collection('materialRequests')
          .doc('req-1')
          .set(request().toMap());
      final ghost = DeliveryRun(
          id: 'nope', date: DateTime(2026, 11, 21), driverId: 'driver-1');
      await expectLater(
          service.attachToRun(
              request: request(), run: ghost, siteName: 'Maple Court'),
          throwsStateError);
    });

    test('markOnRun / revertToApproved enforce the status inside the write',
        () async {
      await db
          .collection('materialRequests')
          .doc('req-1')
          .set(request().toMap());
      // Approved -> onRun works.
      await service.markOnRun(request(), 'run-1');
      var doc =
          await db.collection('materialRequests').doc('req-1').get();
      expect(doc.data()?['status'], 'onRun');
      // A second mark fails: it is no longer approved.
      await expectLater(service.markOnRun(request(), 'run-1'),
          throwsStateError);
      // Revert works only while onRun on that run.
      final onRun = request().copyWith(
          status: MaterialRequestStatus.onRun, runId: 'run-1');
      await service.revertToApproved(onRun);
      doc = await db.collection('materialRequests').doc('req-1').get();
      expect(doc.data()?['status'], 'approved');
      expect(doc.data()?['runId'], isNull);
      // Reverting an approved request fails.
      await expectLater(
          service.revertToApproved(request()), throwsStateError);
    });

    test('createdAt comes from the server clock, not the client',
        () async {
      await service.createRequestWithId(request());
      final doc = await db
          .collection('materialRequests')
          .doc('req-1')
          .get();
      final createdAt = doc.data()?['createdAt'];
      expect(createdAt, isA<Timestamp>());
      expect((createdAt as Timestamp).toDate().year, greaterThan(2020));
    });
  });

  // ---------- Stage service (audit P2) ----------

  group('StageService', () {
    late FakeFirebaseFirestore db;
    late StageService stages;
    late TaskService tasks;

    setUp(() {
      db = FakeFirebaseFirestore();
      stages = StageService(db: db);
      tasks = TaskService(db: db);
    });

    Future<int> siteStageCount(String siteId) async {
      final snap = await db
          .collection('stages')
          .where('siteId', isEqualTo: siteId)
          .get();
      return snap.docs.length;
    }

    test('createRoadmapFromTemplate reports whether it wrote', () async {
      expect(await stages.createRoadmapFromTemplate('site-1'), isTrue);
      expect(await siteStageCount('site-1'), 7);
      expect(await stages.createRoadmapFromTemplate('site-1'), isFalse);
      expect(await siteStageCount('site-1'), 7);
    });

    test('saveRoadmapAsTemplate returns empty id for an empty roadmap',
        () async {
      final id = await stages.saveRoadmapAsTemplate(
          siteId: 'site-empty', name: 'Empty', createdBy: 'admin-1');
      expect(id, isEmpty);
    });

    test('deleting a roadmap releases the claim for a fresh one',
        () async {
      expect(await stages.createRoadmapFromTemplate('site-1'), isTrue);
      await stages.deleteRoadmap('site-1');
      expect(await siteStageCount('site-1'), 0);
      expect(await stages.createRoadmapFromTemplate('site-1'), isTrue);
      expect(await siteStageCount('site-1'), 7);
    });

    test('deleteStage chunks past the 500-write batch limit', () async {
      final stageId = await stages.createStage(
          siteId: 'site-1', name: 'Big stage', order: 1);
      for (var i = 0; i < 450; i++) {
        await tasks.createTask(TaskItem(
          id: '',
          title: 'Task $i',
          siteId: 'site-1',
          createdBy: 'admin-1',
          stageId: stageId,
        ));
      }
      // 1 stage delete + 450 task updates = 451 writes: a single
      // batch would throw, the chunked delete must not.
      await stages.deleteStage(stageId);
      final remaining = await db
          .collection('stages')
          .where('siteId', isEqualTo: 'site-1')
          .get();
      expect(remaining.docs, isEmpty);
      final orphaned = await db
          .collection('tasks')
          .where('stageId', isEqualTo: stageId)
          .get();
      expect(orphaned.docs, isEmpty);
    });
  });

  // ---------- Run sync (audit P1/P2) ----------

  group('RunSyncService', () {
    late FakeFirebaseFirestore db;

    setUp(() {
      db = FakeFirebaseFirestore();
      RunSyncService.testDb = db;
    });

    tearDown(() {
      RunSyncService.resetTestDb();
    });

    DeliveryRun run(String id, DateTime date, List<RunStop> stops) =>
        DeliveryRun(
            id: id, date: date, driverId: 'driver-1', stops: stops);

    RunStop stop(String id, String title,
            {String? taskId, bool carriedOver = false}) =>
        RunStop(
            id: id,
            orderIndex: 0,
            title: title,
            taskId: taskId,
            carriedOver: carriedOver);

    Future<DeliveryRun> storedRun(String id) async {
      final doc = await db.collection('runs').doc(id).get();
      return DeliveryRun.fromFirestore(doc);
    }

    test('carries unfinished stops from ALL earlier runs', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final twoDaysAgo = today.subtract(const Duration(days: 2));
      final task = TaskItem(
          id: 'task-1',
          title: 'Install counter',
          siteId: 'site-1',
          createdBy: 'admin-1',
          assigneeIds: const ['driver-1']);
      // Yesterday: a task-less stop. Two days ago: a task-linked
      // stop AND a completed stop (which must never carry).
      await db.collection('runs').doc('run-y').set(
          run('run-y', yesterday, [stop('s-y', 'Yesterday pickup')])
              .toMap());
      await db.collection('runs').doc('run-2d').set(run('run-2d',
          twoDaysAgo, [
        stop('s-2d', 'Two days ago drop-off', taskId: 'task-1'),
        stop('s-done', 'Done long ago')
            .copyWith(status: StopStatus.completed),
      ]).toMap());
      await db.collection('runs').doc('run-today').set(
          run('run-today', today, []).toMap());

      final todayRun = await storedRun('run-today');
      final result = await RunSyncService.syncRun(todayRun,
          allTasks: [task]);
      expect(result.carriedOver, 2);
      final after = await storedRun('run-today');
      expect(after.stops.map((s) => s.title),
          containsAll(['Yesterday pickup', 'Two days ago drop-off']));
      expect(after.stops.map((s) => s.title), isNot(contains('Done long ago')));
      expect(after.stops.every((s) => s.carriedOver), isTrue);
    });

    test('prunes a pending planned stop whose task was deleted', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      await db.collection('runs').doc('run-today').set(run('run-today',
          today, [
        stop('s-gone', 'Drop-off for deleted task', taskId: 'task-gone'),
        stop('s-plain', 'Plain stop'),
      ]).toMap());

      final todayRun = await storedRun('run-today');
      final result =
          await RunSyncService.syncRun(todayRun, allTasks: []);
      expect(result.dropped, 1);
      final after = await storedRun('run-today');
      expect(after.stops.map((s) => s.id), ['s-plain']);
    });

    test('re-points a carried request to the new run', () async {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      await db.collection('materialRequests').doc('req-1').set({
        'requesterId': 'worker-1',
        'requesterName': 'Wendy',
        'siteId': 'site-1',
        'item': 'Counter',
        'quantity': 1,
        'status': 'onRun',
        'runId': 'run-y',
      });
      final carriedStop = RunStop(
          id: 's-req',
          orderIndex: 0,
          title: 'Counter',
          kind: StopKind.pickup,
          materialRequestId: 'req-1');
      await db.collection('runs').doc('run-y').set(
          run('run-y', yesterday, [carriedStop]).toMap());
      await db.collection('runs').doc('run-today').set(
          run('run-today', today, []).toMap());

      final todayRun = await storedRun('run-today');
      final result =
          await RunSyncService.syncRun(todayRun, allTasks: []);
      expect(result.carriedOver, 1);
      expect(result.requestRepointFailures, 0);
      final req =
          await db.collection('materialRequests').doc('req-1').get();
      expect(req.data()?['runId'], 'run-today');
    });
  });
}
