import 'dart:async';
import 'dart:convert';
import 'dart:io'
    show
        Directory,
        File,
        HttpClient,
        HttpClientRequest,
        HttpClientResponse,
        HttpClientResponseCompressionState,
        HttpOverrides,
        Platform,
        SecurityContext;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/app_user.dart';
import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/models/task_item.dart';
import 'package:dyadespace/models/task_update.dart';
import 'package:dyadespace/providers/auth_provider.dart';
import 'package:dyadespace/providers/locale_provider.dart';
import 'package:dyadespace/providers/photo_queue_provider.dart';
import 'package:dyadespace/providers/sites_provider.dart';
import 'package:dyadespace/providers/stages_provider.dart';
import 'package:dyadespace/providers/tasks_provider.dart';
import 'package:dyadespace/providers/units_provider.dart';
import 'package:dyadespace/screens/task_screen.dart';
import 'package:dyadespace/services/photo_queue_service.dart';
import 'package:dyadespace/services/photo_service.dart';
import 'package:dyadespace/services/task_service.dart';
import 'package:dyadespace/theme/app_theme.dart';

/// Audit fixes, Nov 21 2026 (P0-7, P0-8 + the task_screen P1/P2
/// items): the photo queue must never wedge behind one dead
/// entry, the editor must never save over unloaded streams,
/// Done must stamp finishedAt and need its photo, the status
/// dropdown must respect chain/stage locks, "Starts after"
/// must not close a dependency cycle, the Done button must
/// fail loudly, a lost completion photo must block closing,
/// and a deleted task must read as gone — not as a stale copy.

const _me = AppUser(
  id: 'me',
  name: 'Alex Morgan',
  email: 'alex@example.com',
  role: UserRole.admin,
);

const _worker = AppUser(
  id: 'w1',
  name: 'Chris',
  email: 'walter@example.com',
  role: UserRole.worker,
);

const _site = Site(
  id: 'site1',
  name: 'Maple Court',
  address: '617 Saint-Rémi',
);

TaskItem _task({
  required String id,
  required String title,
  TaskStatus status = TaskStatus.todo,
  String? dependsOnTaskId,
  bool photoRequired = false,
  BlockedReason? blockedReason,
  String blockedNote = '',
  bool photoPending = false,
}) {
  return TaskItem(
    id: id,
    title: title,
    siteId: 'site1',
    assigneeIds: ['me'],
    createdBy: 'me',
    status: status,
    dependsOnTaskId: dependsOnTaskId,
    photoRequired: photoRequired,
    blockedReason: blockedReason,
    blockedNote: blockedNote,
    photoPending: photoPending,
  );
}

const _kTinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// Records creates/updates/completions instead of touching
/// Firestore; [completeShouldThrow] makes Done fail on demand.
class _FakeTaskService extends TaskService {
  TaskItem? created;
  TaskItem? updated;
  TaskItem? completed;
  bool completeShouldThrow = false;
  Object? completeError;

  @override
  Future<String> createTask(TaskItem task) async {
    created = task;
    return 'new-id';
  }

  @override
  Future<void> updateTask(TaskItem task) async {
    updated = task;
  }

  @override
  Future<void> completeTask(TaskItem task, List<String> photoUrls,
      {bool photoPending = false}) async {
    if (completeShouldThrow) {
      throw completeError ?? Exception('boom');
    }
    completed = task;
  }
}

/// The queue, under the test's control: enqueue records the
/// call and reports success or failure.
class _FakePhotoQueueService extends PhotoQueueService {
  bool enqueueResult = true;
  final List<PhotoQueueEntry> enqueued = [];
  final StreamController<List<PhotoQueueEntry>> entriesController =
      StreamController<List<PhotoQueueEntry>>.broadcast();
  List<PhotoQueueEntry> current = [];

  @override
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
    if (!enqueueResult) return false;
    final entry = PhotoQueueEntry(
      id: 'q${enqueued.length}',
      kind: kind,
      localPath: sourcePath,
      folder: folder,
      taskId: taskId,
      runId: runId,
      stopId: stopId,
      authorId: authorId,
      authorName: authorName,
      text: text,
      queuedAt: DateTime.now(),
    );
    enqueued.add(entry);
    current = [...current, entry];
    entriesController.add(current);
    return true;
  }

  @override
  Stream<List<PhotoQueueEntry>> watchEntries() async* {
    yield current;
    yield* entriesController.stream;
  }
}

class _MemoryXFile extends XFile {
  final Uint8List _bytes;
  _MemoryXFile(super.path, this._bytes);

  @override
  Future<Uint8List> readAsBytes() async => _bytes;
}

class _FakePhotoService extends PhotoService {
  String? photoPath;
  Uint8List? photoBytes;
  bool uploadShouldThrow = false;
  String uploadUrl = 'https://example.com/photo.jpg';

  @override
  Future<XFile?> takePhoto() async {
    if (photoPath == null) return null;
    return _MemoryXFile(photoPath!, photoBytes ?? Uint8List(0));
  }

  @override
  Future<String> uploadFile(
      String localPath, String folder, String ownerId) async {
    if (uploadShouldThrow) throw Exception('offline');
    return uploadUrl;
  }
}

/// Uploads for the real queue, under the test's control: fails
/// for paths in [failPaths], succeeds everywhere else.
class _ControllablePhotoService extends PhotoService {
  final Set<String> failPaths = {};
  int uploadCalls = 0;

  @override
  Future<String> uploadFile(
      String localPath, String folder, String ownerId) async {
    uploadCalls++;
    if (failPaths.contains(localPath)) throw Exception('upload failed');
    return 'https://example.com/${Uri.file(localPath).pathSegments.last}';
  }
}

class _FakeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async =>
      _FakeHttpClientRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  int get statusCode => 200;

  @override
  int get contentLength => _kTinyPng.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(void Function(List<int> event)? onData,
          {Function? onError, void Function()? onDone, bool? cancelOnError}) =>
      Stream<List<int>>.value(_kTinyPng).listen(onData,
          onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<File> _tempPhoto() async {
  final dir = await Directory.systemTemp.createTemp();
  final file = File('${dir.path}/photo.jpg');
  await file.writeAsBytes(_kTinyPng);
  return file;
}

void _mockConnectivity(List<String> results) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('dev.fluttercommunity.plus/connectivity'),
    (call) async {
      if (call.method == 'check') return results;
      return null;
    },
  );
}

/// Bounded pumps instead of pumpAndSettle: spinners in the
/// screen would never let pumpAndSettle return.
Future<void> _pumpShort(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpTaskScreen(
  WidgetTester tester, {
  required _FakeTaskService tasks,
  required _FakePhotoQueueService queue,
  required _FakePhotoService photos,
  required Stream<List<TaskItem>> allTasksStream,
  TaskItem? task,
  String? initialSiteId,
}) async {
  await initializeDateFormatting('en');
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  final updatesController = StreamController<List<TaskUpdate>>.broadcast();
  addTearDown(() async {
    await updatesController.close();
    await queue.entriesController.close();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(const AppStrings('en')),
        currentUserProvider.overrideWith((ref) => Stream.value(_me)),
        allTasksProvider.overrideWith((ref) => allTasksStream),
        taskUpdatesProvider
            .overrideWith((ref, taskId) => updatesController.stream),
        taskServiceProvider.overrideWithValue(tasks),
        photoQueueServiceProvider.overrideWithValue(queue),
        photoServiceProvider.overrideWithValue(photos),
        siteByIdProvider
            .overrideWithValue(<String, Site>{'site1': _site}),
        sitesProvider.overrideWith((ref) => Stream.value([_site])),
        allUsersProvider
            .overrideWith((ref) => Stream.value([_me, _worker])),
        unitsForSiteProvider.overrideWith((ref, siteId) => Stream.value([])),
        stagesForSiteProvider
            .overrideWith((ref, siteId) => Stream.value([])),
        stagesForUnitProvider
            .overrideWith((ref, unitId) => Stream.value([])),
        stageIndexProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: buildAppDarkTheme(),
        home: Scaffold(
            body: TaskScreen(task: task, initialSiteId: initialSiteId)),
      ),
    ),
  );
  updatesController.add(const []);
  await _pumpShort(tester);
}

Future<void> _enterEditMode(WidgetTester tester) async {
  await tester.ensureVisible(find.byIcon(Icons.edit_outlined));
  await tester.tap(find.byIcon(Icons.edit_outlined));
  await _pumpShort(tester);
  expect(find.text('Edit task'), findsOneWidget);
}

/// Picks [label] in the Status dropdown of the edit form.
Future<void> _pickStatus(WidgetTester tester, String label) async {
  final field = find.ancestor(
    of: find.text('Status'),
    matching: find.byType(DropdownButtonFormField<TaskStatus>),
  );
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pump();
  await tester.tap(find.text(label));
  await _pumpShort(tester);
}

/// Picks the task titled [title] in the "Starts after"
/// dropdown of the edit form.
Future<void> _pickStartsAfter(WidgetTester tester, String title) async {
  final field = find.ancestor(
    of: find.text('Starts after'),
    matching: find.byType(DropdownButtonFormField<String?>),
  );
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pump();
  await tester.tap(find.text(title));
  await _pumpShort(tester);
}

/// Opens the "Starts after" dropdown without picking.
Future<void> _openStartsAfter(WidgetTester tester) async {
  final field = find.ancestor(
    of: find.text('Starts after'),
    matching: find.byType(DropdownButtonFormField<String?>),
  );
  await tester.ensureVisible(field);
  await tester.tap(field);
  await tester.pump();
}

Future<void> _tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.text('Save'));
  await tester.tap(find.text('Save'));
  await _pumpShort(tester);
}

void main() {
  setUpAll(() async {
    final path =
        '${Platform.environment['HOME']}/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf';
    final bytes = await File(path).readAsBytes();
    final data = ByteData.view(
        bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes);
    for (final family in [
      'Manrope',
      'Manrope_regular',
      'Manrope_500',
      'Manrope_600',
      'Manrope_700',
    ]) {
      await (FontLoader(family)..addFont(Future.value(data))).load();
    }
    HttpOverrides.global = _FakeHttpOverrides();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.fluttercommunity.plus/connectivity'),
      null,
    );
  });

  group('dependency helpers', () {
    test('taskDescendantIds walks the chain transitively', () {
      final a = _task(id: 'a', title: 'Frame');
      final b = _task(id: 'b', title: 'Plumb', dependsOnTaskId: 'a');
      final c = _task(id: 'c', title: 'Paint', dependsOnTaskId: 'b');
      final d = _task(id: 'd', title: 'Other');
      final all = [a, b, c, d];
      expect(taskDescendantIds('a', all), {'b', 'c'});
      expect(taskDescendantIds('b', all), {'c'});
      expect(taskDescendantIds('c', all), isEmpty);
      expect(taskDescendantIds('d', all), isEmpty);
    });

    test('taskDescendantIds terminates on a cycle already in the data',
        () {
      final a = _task(id: 'a', title: 'A', dependsOnTaskId: 'b');
      final b = _task(id: 'b', title: 'B', dependsOnTaskId: 'a');
      expect(taskDescendantIds('a', [a, b]), {'b'});
    });

    test('createsDependencyCycle spots a closed loop', () {
      final a = _task(id: 'a', title: 'Frame');
      final b = _task(id: 'b', title: 'Plumb', dependsOnTaskId: 'a');
      final c = _task(id: 'c', title: 'Paint', dependsOnTaskId: 'b');
      final all = [a, b, c];
      expect(createsDependencyCycle('a', 'b', all), isTrue);
      expect(createsDependencyCycle('a', 'c', all), isTrue);
      expect(createsDependencyCycle('b', 'c', all), isTrue);
      expect(createsDependencyCycle('b', 'a', all), isFalse);
      expect(createsDependencyCycle('a', null, all), isFalse);
      expect(createsDependencyCycle('a', 'a', all), isTrue);
    });
  });

  group('photo queue: dead entries never wedge the rest', () {
    test('a missing parked file is dropped and the next photo uploads',
        () async {
      _mockConnectivity(['wifi']);
      SharedPreferences.setMockInitialValues({});
      final good = await _tempPhoto();
      final fake = FakeFirebaseFirestore();
      await fake
          .collection('tasks')
          .doc('t1')
          .set({'photoPending': true});
      await fake
          .collection('tasks')
          .doc('t2')
          .set({'photoPending': true});
      final dead = PhotoQueueEntry(
        id: 'dead',
        kind: 'taskDone',
        localPath: '/nope/deleted-by-someone-else.jpg',
        folder: 'taskPhotos',
        taskId: 't1',
        queuedAt: DateTime.now(),
      );
      final live = PhotoQueueEntry(
        id: 'live',
        kind: 'taskDone',
        localPath: good.path,
        folder: 'taskPhotos',
        taskId: 't2',
        queuedAt: DateTime.now(),
      );
      SharedPreferences.setMockInitialValues({
        'photo_upload_queue_v1':
            jsonEncode([dead.toJson(), live.toJson()]),
      });
      final service = PhotoQueueService(
          db: fake, photos: _ControllablePhotoService());

      await service.processQueue();

      expect(await service.watchEntries().first, isEmpty);
      final t1 = await fake.collection('tasks').doc('t1').get();
      expect(t1.data()?['photoPending'], isFalse);
      expect((t1.data()?['photoUrls'] as List?) ?? [], isEmpty);
      final t2 = await fake.collection('tasks').doc('t2').get();
      expect(t2.data()?['photoPending'], isFalse);
      expect(t2.data()?['photoUrls'], hasLength(1));
    });

    test('a failing upload is dropped after 3 attempts, then the rest flows',
        () async {
      _mockConnectivity(['wifi']);
      SharedPreferences.setMockInitialValues({});
      final badFile = await _tempPhoto();
      final goodFile = await _tempPhoto();
      final fake = FakeFirebaseFirestore();
      await fake
          .collection('tasks')
          .doc('t1')
          .set({'photoPending': true});
      await fake
          .collection('tasks')
          .doc('t2')
          .set({'photoPending': true});
      final bad = PhotoQueueEntry(
        id: 'bad',
        kind: 'taskDone',
        localPath: badFile.path,
        folder: 'taskPhotos',
        taskId: 't1',
        queuedAt: DateTime.now(),
      );
      final good = PhotoQueueEntry(
        id: 'good',
        kind: 'taskDone',
        localPath: goodFile.path,
        folder: 'taskPhotos',
        taskId: 't2',
        queuedAt: DateTime.now(),
      );
      SharedPreferences.setMockInitialValues({
        'photo_upload_queue_v1':
            jsonEncode([bad.toJson(), good.toJson()]),
      });
      final photos = _ControllablePhotoService()
        ..failPaths.add(badFile.path);
      final service = PhotoQueueService(db: fake, photos: photos);

      await service.processQueue();
      var remaining = await service.watchEntries().first;
      expect(remaining, hasLength(2));
      expect(remaining.first.attempts, 1);
      // The good photo behind the bad one was not tried yet:
      // the pass stopped at the (presumed offline) failure.
      expect(photos.uploadCalls, 1);

      await service.processQueue();
      remaining = await service.watchEntries().first;
      expect(remaining, hasLength(2));
      expect(remaining.first.attempts, 2);

      // Third failure drops the bad entry and the pass
      // continues to the good photo in the same run.
      await service.processQueue();
      expect(await service.watchEntries().first, isEmpty);
      final t1 = await fake.collection('tasks').doc('t1').get();
      expect(t1.data()?['photoPending'], isFalse);
      expect((t1.data()?['photoUrls'] as List?) ?? [], isEmpty);
      final t2 = await fake.collection('tasks').doc('t2').get();
      expect(t2.data()?['photoPending'], isFalse);
      expect(t2.data()?['photoUrls'], hasLength(1));
    });

    test('offline passes do not burn attempts', () async {
      _mockConnectivity(['none']);
      SharedPreferences.setMockInitialValues({});
      final file = await _tempPhoto();
      final entry = PhotoQueueEntry(
        id: 'only',
        kind: 'taskDone',
        localPath: file.path,
        folder: 'taskPhotos',
        taskId: 't1',
        queuedAt: DateTime.now(),
      );
      SharedPreferences.setMockInitialValues({
        'photo_upload_queue_v1': jsonEncode([entry.toJson()]),
      });
      final photos = _ControllablePhotoService()
        ..failPaths.add(file.path);
      final service = PhotoQueueService(
          db: FakeFirebaseFirestore(), photos: photos);

      await service.processQueue();
      await service.processQueue();
      await service.processQueue();

      final remaining = await service.watchEntries().first;
      expect(remaining, hasLength(1));
      expect(remaining.single.attempts, 0);
    });
  });

  group('task editor', () {
    testWidgets('save is refused while the task stream has not loaded',
        (tester) async {
      final never = StreamController<List<TaskItem>>.broadcast();
      addTearDown(never.close);
      final tasks = _FakeTaskService();
      final queue = _FakePhotoQueueService();
      final photos = _FakePhotoService();
      await _pumpTaskScreen(
        tester,
        tasks: tasks,
        queue: queue,
        photos: photos,
        // Never emits: the stream is still loading.
        allTasksStream: never.stream,
        initialSiteId: 'site1',
      );
      expect(find.text('New task'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, 'Test task');
      await _tapSave(tester);

      expect(
          find.text(
              'Still loading — wait a moment, then tap Save again.'),
          findsOneWidget);
      expect(tasks.created, isNull);
      // The editor stays open: nothing was lost.
      expect(find.text('New task'), findsOneWidget);
    });

    testWidgets('Done without a photo is refused when a photo is required',
        (tester) async {
      final task = _task(
          id: 'task1',
          title: 'Fix the hinge',
          status: TaskStatus.inProgress,
          photoRequired: true);
      final tasks = _FakeTaskService();
      final queue = _FakePhotoQueueService();
      final photos = _FakePhotoService();
      await _pumpTaskScreen(
        tester,
        tasks: tasks,
        queue: queue,
        photos: photos,
        allTasksStream: Stream.value([task]),
        task: task,
      );

      await _enterEditMode(tester);
      await _pickStatus(tester, 'Done');
      await _tapSave(tester);

      expect(
          find.text(
              'A photo is required before this task can be marked Done.'),
          findsOneWidget);
      expect(tasks.updated, isNull);
      expect(find.text('Edit task'), findsOneWidget);
    });

    testWidgets('Done stamps finishedAt and clears a stale blocked reason',
        (tester) async {
      final task = _task(
        id: 'task1',
        title: 'Fix the hinge',
        status: TaskStatus.blocked,
        blockedReason: BlockedReason.waitingMaterials,
        blockedNote: 'waiting on parts',
      );
      final tasks = _FakeTaskService();
      final queue = _FakePhotoQueueService();
      final photos = _FakePhotoService();
      await _pumpTaskScreen(
        tester,
        tasks: tasks,
        queue: queue,
        photos: photos,
        allTasksStream: Stream.value([task]),
        task: task,
      );

      // Blocked -> Done (no photo required): the stamp lands
      // and the blocked reason goes away with the status.
      await _enterEditMode(tester);
      await _pickStatus(tester, 'Done');
      await _tapSave(tester);

      final saved = tasks.updated;
      expect(saved, isNotNull);
      expect(saved!.status, TaskStatus.done);
      expect(saved.finishedAt, isNotNull);
      expect(saved.blockedReason, isNull);
      expect(saved.blockedNote, isEmpty);
      // Back in view mode on the same screen.
      expect(find.text('Edit task'), findsNothing);
    });

    testWidgets('"Starts after" never offers a descendant', (tester) async {
      final a = _task(id: 'a', title: 'Frame the shower');
      final b = _task(id: 'b', title: 'Plumbing', dependsOnTaskId: 'a');
      final c = _task(id: 'c', title: 'Paint', dependsOnTaskId: 'b');
      final tasks = _FakeTaskService();
      final queue = _FakePhotoQueueService();
      final photos = _FakePhotoService();
      await _pumpTaskScreen(
        tester,
        tasks: tasks,
        queue: queue,
        photos: photos,
        allTasksStream: Stream.value([a, b, c]),
        task: a,
      );

      await _enterEditMode(tester);
      await _openStartsAfter(tester);

      expect(find.text('Plumbing'), findsNothing);
      expect(find.text('Paint'), findsNothing);
      // 'None' shows twice: once as the field's current value
      // and once as the menu item.
      expect(find.text('None'), findsNWidgets(2));
    });

    testWidgets('a save that would close a cycle is refused', (tester) async {
      final a = _task(id: 'a', title: 'Frame the shower');
      final b = _task(
          id: 'b', title: 'Plumbing', dependsOnTaskId: 'a');
      final controller = StreamController<List<TaskItem>>.broadcast();
      addTearDown(controller.close);
      final tasks = _FakeTaskService();
      final queue = _FakePhotoQueueService();
      final photos = _FakePhotoService();
      await _pumpTaskScreen(
        tester,
        tasks: tasks,
        queue: queue,
        photos: photos,
        allTasksStream: controller.stream,
        task: a,
      );
      controller.add([a, b]);
      await _pumpShort(tester);

      // Break the link first, so Plumbing is offered; pick it.
      final unlinked =
          _task(id: 'b', title: 'Plumbing', dependsOnTaskId: null);
      controller.add([a, unlinked]);
      await _pumpShort(tester);
      await _enterEditMode(tester);
      await _pickStartsAfter(tester, 'Plumbing');

      // The link comes back before Save: Plumbing is a
      // descendant again, so saving the pick would deadlock.
      controller.add([a, b]);
      await _pumpShort(tester);
      await _tapSave(tester);

      expect(
          find.text(
              'That "Starts after" would create a dependency cycle.'),
          findsOneWidget);
      expect(tasks.updated, isNull);
    });

    testWidgets('a locked task cannot be started or finished in the editor',
        (tester) async {
      final a = _task(id: 'a', title: 'Frame the shower');
      final b = _task(
          id: 'b', title: 'Plumbing', dependsOnTaskId: 'a');
      final tasks = _FakeTaskService();
      final queue = _FakePhotoQueueService();
      final photos = _FakePhotoService();
      await _pumpTaskScreen(
        tester,
        tasks: tasks,
        queue: queue,
        photos: photos,
        allTasksStream: Stream.value([a, b]),
        task: b,
      );

      await _enterEditMode(tester);
      final field = find.ancestor(
        of: find.text('Status'),
        matching: find.byType(DropdownButtonFormField<TaskStatus>),
      );
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pump();

      // The button renders the selected item as a menu item
      // too, so scope the check to the open menu: the menu's
      // copy comes last in the tree.
      final menuItems = find
          .byType(DropdownMenuItem<TaskStatus>)
          .evaluate()
          .map((e) => e.widget as DropdownMenuItem<TaskStatus>)
          .toList();
      bool enabledOf(TaskStatus status) =>
          menuItems.lastWhere((w) => w.value == status).enabled;
      expect(enabledOf(TaskStatus.inProgress), isFalse);
      expect(enabledOf(TaskStatus.done), isFalse);
      expect(enabledOf(TaskStatus.todo), isTrue);
    });

    testWidgets('a lock that lands after the form opens blocks the save',
        (tester) async {
      final a = _task(
          id: 'a', title: 'Frame the shower', status: TaskStatus.done);
      final b = _task(id: 'b', title: 'Plumbing', dependsOnTaskId: 'a');
      final controller = StreamController<List<TaskItem>>.broadcast();
      addTearDown(controller.close);
      final tasks = _FakeTaskService();
      final queue = _FakePhotoQueueService();
      final photos = _FakePhotoService();
      await _pumpTaskScreen(
        tester,
        tasks: tasks,
        queue: queue,
        photos: photos,
        allTasksStream: controller.stream,
        task: b,
      );
      controller.add([a, b]);
      await _pumpShort(tester);

      // Unlocked while the form opens: In progress is offered.
      await _enterEditMode(tester);
      await _pickStatus(tester, 'In progress');

      // The dependency reopens before Save: the task is locked
      // again, so the forward step must be refused.
      final reopened =
          _task(id: 'a', title: 'Frame the shower', status: TaskStatus.todo);
      controller.add([reopened, b]);
      await _pumpShort(tester);
      await _tapSave(tester);

      expect(
          find.text('This task is locked — it can’t be started yet.'),
          findsOneWidget);
      expect(tasks.updated, isNull);
    });

    testWidgets('a deleted task reads as gone, not as a stale copy',
        (tester) async {
      final a = _task(id: 'a', title: 'Frame the shower');
      final b = _task(id: 'b', title: 'Plumbing');
      final controller = StreamController<List<TaskItem>>.broadcast();
      addTearDown(controller.close);
      final tasks = _FakeTaskService();
      final queue = _FakePhotoQueueService();
      final photos = _FakePhotoService();
      await _pumpTaskScreen(
        tester,
        tasks: tasks,
        queue: queue,
        photos: photos,
        allTasksStream: controller.stream,
        task: b,
      );
      controller.add([a, b]);
      await _pumpShort(tester);
      expect(find.text('Plumbing'), findsOneWidget);

      // Deleted on another device while this screen is open.
      controller.add([a]);
      await _pumpShort(tester);

      expect(find.text('Task deleted.'), findsOneWidget);
      expect(find.text('Plumbing'), findsNothing);
    });
  });

  group('Done button', () {
    testWidgets('a failed completion shows an error and stays usable',
        (tester) async {
      final task = _task(
          id: 'task1',
          title: 'Fix the hinge',
          status: TaskStatus.inProgress,
          photoRequired: false);
      final tasks = _FakeTaskService()..completeShouldThrow = true;
      final queue = _FakePhotoQueueService();
      final photos = _FakePhotoService();
      await _pumpTaskScreen(
        tester,
        tasks: tasks,
        queue: queue,
        photos: photos,
        allTasksStream: Stream.value([task]),
        task: task,
      );

      await tester.ensureVisible(find.text('Done'));
      await tester.tap(find.text('Done'));
      await _pumpShort(tester);

      expect(find.text('Could not save the task: Exception: boom'),
          findsOneWidget);
      // Still on the screen, Done still offered — not stuck busy.
      expect(find.text('Fix the hinge'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(tasks.completed, isNull);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Done aborts when the completion photo cannot be parked',
        (tester) async {
      final photo = (await tester.runAsync(_tempPhoto))!;
      final photoBytes = (await tester.runAsync(() => photo.readAsBytes()))!;
      final task = _task(
          id: 'task1',
          title: 'Fix the hinge',
          status: TaskStatus.inProgress,
          photoRequired: true);
      final tasks = _FakeTaskService();
      final queue = _FakePhotoQueueService()..enqueueResult = false;
      final photos = _FakePhotoService()
        ..photoPath = photo.path
        ..photoBytes = photoBytes
        ..uploadShouldThrow = true;
      await _pumpTaskScreen(
        tester,
        tasks: tasks,
        queue: queue,
        photos: photos,
        allTasksStream: Stream.value([task]),
        task: task,
      );

      // Add the photo offline: the upload fails and the park
      // fails too, so the path is held for a retry at Done.
      await tester.ensureVisible(find.text('Add photo'));
      await tester.tap(find.text('Add photo'));
      await _pumpShort(tester);
      expect(
          find.text(
              'Photo upload failed - check your connection and try again.'),
          findsOneWidget);

      // Done must not close on a photo that never parked.
      await tester.ensureVisible(find.textContaining('Done'));
      await tester.tap(find.textContaining('Done'));
      await _pumpShort(tester);

      expect(tasks.completed, isNull);
      expect(find.text('Fix the hinge'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
