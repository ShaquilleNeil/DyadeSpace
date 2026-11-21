import 'dart:async';
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

/// Task-update posts (Nov 16, 2026): a photo + text post must
/// show on the task at once — as a pending row while its photo
/// uploads, then as a real update — never vanish silently.
/// Pumped with the REAL app theme and mocked providers + fake
/// queue/photo services — no Firebase, no network, no camera.
///
/// The bug this pins: _postUpdate cleared the composer the
/// moment enqueue returned, but enqueue only parks the file —
/// the Updates doc does not exist until the queue uploads the
/// photo and writes it. On weak signal that gap was seconds
/// to minutes of "nothing happened", and enqueue swallowed
/// every parking error, so a failed park lost the post with
/// no trace at all.

const _me = AppUser(
  id: 'me',
  name: 'Alex Morgan',
  email: 'alex@example.com',
  role: UserRole.admin,
);

const _site = Site(
  id: 'site1',
  name: 'Maple Court',
  address: '617 Saint-Rémi',
);

final _task = TaskItem(
  id: 'task1',
  title: 'Fix the hinge',
  siteId: 'site1',
  assigneeIds: ['me'],
  createdBy: 'me',
  status: TaskStatus.inProgress,
  photoRequired: false,
);

/// 1x1 transparent PNG, for the fake camera file and the fake
/// HTTP client that answers Image.network in the landed row.
const _kTinyPng = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// Records posted updates on a stream the test drives, instead
/// of touching Firestore.
class _FakeTaskService extends TaskService {
  final StreamController<List<TaskUpdate>> updatesController;
  final List<TaskUpdate> posted = [];

  _FakeTaskService(this.updatesController);

  @override
  Future<void> addUpdate(
    String taskId, {
    required String authorId,
    required String authorName,
    required String text,
    String? photoUrl,
  }) async {
    final update = TaskUpdate(
      id: 'u${posted.length}',
      taskId: taskId,
      authorId: authorId,
      authorName: authorName,
      text: text,
      photoUrl: photoUrl,
      createdAt: DateTime.now(),
    );
    posted.add(update);
    updatesController.add(List.unmodifiable(posted));
  }
}

/// The queue, under the test's control: enqueue records the
/// call and reports success or failure; the pending list is
/// driven by the test through [completeEntry]/[failEntry].
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
    // A failed park parks nothing: mirror the real service,
    // which returns false before the entry reaches the list —
    // otherwise a failed post would still render as pending.
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

  /// The queue landed this entry: it leaves the pending list
  /// (the real doc arrives on the updates stream separately).
  void completeEntry(PhotoQueueEntry entry) {
    current = current.where((e) => e.id != entry.id).toList();
    entriesController.add(current);
  }
}

/// The camera, under the test's control: returns a real temp
/// file so the composer thumbnail renders from disk.
/// XFile whose bytes live in memory: the real XFile.readAsBytes
/// does file IO, and real IO never completes inside a
/// testWidgets body (FakeAsync swallows its completion — the
/// same deadlock as a bare createTemp, fixed for the temp file
/// itself with tester.runAsync). The path stays the real temp
/// path so _updatePhotoPath / the queue see a real file.
class _MemoryXFile extends XFile {
  final Uint8List _bytes;
  _MemoryXFile(super.path, this._bytes);

  @override
  Future<Uint8List> readAsBytes() async => _bytes;
}

class _FakePhotoService extends PhotoService {
  String? photoPath;
  Uint8List? photoBytes;

  @override
  Future<XFile?> takePhoto() async {
    if (photoPath == null) return null;
    return _MemoryXFile(photoPath!, photoBytes ?? Uint8List(0));
  }
}

/// Image.network in the landed row must not hit the real
/// network in tests: answer every request with the tiny PNG.
class _FakeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _FakeHttpClient();
}

class _FakeHttpClient implements HttpClient {
  // NetworkImage sets this on the client it builds; without
  // a real field it falls into noSuchMethod and throws.
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

/// connectivity_plus checkConnectivity in tests: answer with
/// [results] ('wifi' online, 'none' offline).
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

/// Bounded pumps instead of pumpAndSettle: the pending row
/// spins a CircularProgressIndicator forever, so pumpAndSettle
/// would never return once a post is pending.
Future<void> _pumpShort(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required _FakeTaskService tasks,
  required _FakePhotoQueueService queue,
  required _FakePhotoService photos,
  required StreamController<List<TaskUpdate>> updatesController,
}) async {
  await initializeDateFormatting('en');
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(const AppStrings('en')),
        currentUserProvider.overrideWith((ref) => Stream.value(_me)),
        allTasksProvider.overrideWith((ref) => Stream.value([_task])),
        taskUpdatesProvider
            .overrideWith((ref, taskId) => updatesController.stream),
        taskServiceProvider.overrideWithValue(tasks),
        photoQueueServiceProvider.overrideWithValue(queue),
        photoServiceProvider.overrideWithValue(photos),
        siteByIdProvider
            .overrideWithValue(<String, Site>{'site1': _site}),
        unitsForSiteProvider.overrideWith((ref, siteId) => Stream.value([])),
        stageIndexProvider.overrideWithValue(null),
      ],
      child: MaterialApp(
        theme: buildAppDarkTheme(),
        home: Scaffold(body: TaskScreen(task: _task)),
      ),
    ),
  );
  // The updates stream is a broadcast controller: seed the
  // empty list after the screen subscribes (an add before
  // pumpWidget would be lost), then let the loading state
  // resolve with bounded pumps.
  updatesController.add(const []);
  await _pumpShort(tester);
}

Future<void> _postPhotoUpdate(
  WidgetTester tester, {
  required String photoPath,
  required String text,
}) async {
  await tester.enterText(find.byType(TextField).first, text);
  // The composer sits near the bottom of a long ListView:
  // scroll it into view or the tap lands outside the
  // viewport and silently hits nothing.
  await tester.ensureVisible(find.byIcon(Icons.photo_camera_outlined).first);
  await tester.tap(find.byIcon(Icons.photo_camera_outlined).first);
  // _addUpdatePhoto reads the picked file (real IO) before it
  // clears _updateBusy and the Post label comes back. The busy
  // setState only renders on the next frame, so pump once
  // first — otherwise Post still shows and the wait loop below
  // exits at once while the photo has not landed yet — then
  // pump until the button returns.
  await tester.pump();
  for (var i = 0; i < 30 && find.text('Post').evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.ensureVisible(find.text('Post'));
  await tester.tap(find.text('Post'));
  await _pumpShort(tester);
}

void main() {
  // Same font setup as hours_person_cards_test.dart: widget
  // tests fall back to Ahem (every glyph 1em wide) unless a
  // real sans is loaded under the family names google_fonts
  // resolves to — without it every line looks truncated.
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

  testWidgets('photo + text post shows at once, then lands as a real update',
      (tester) async {
    _mockConnectivity(['wifi']);
    final photo = (await tester.runAsync(_tempPhoto))!;
    final photoBytes =
        (await tester.runAsync(() => photo.readAsBytes()))!;
    final updatesController = StreamController<List<TaskUpdate>>.broadcast();
    final tasks = _FakeTaskService(updatesController);
    final queue = _FakePhotoQueueService();
    final photos = _FakePhotoService()
      ..photoPath = photo.path
      ..photoBytes = photoBytes;
    addTearDown(() async {
      await updatesController.close();
      await queue.entriesController.close();
    });
    await _pumpScreen(tester,
        tasks: tasks,
        queue: queue,
        photos: photos,
        updatesController: updatesController);
    expect(tester.takeException(), isNull);
    expect(find.text('No updates yet.'), findsOneWidget);

    await _postPhotoUpdate(tester,
        photoPath: photo.path, text: 'Fixed the hinge');

    // The post is visible at once as a pending row — the
    // composer is cleared, the photo + text show, and the
    // thread no longer claims to be empty.
    expect(find.text('Fixed the hinge'), findsOneWidget);
    expect(find.text('Sending…'), findsOneWidget);
    expect(find.text('No updates yet.'), findsNothing);
    expect(queue.enqueued, hasLength(1));
    expect(queue.enqueued.single.kind, 'taskUpdate');
    expect(queue.enqueued.single.text, 'Fixed the hinge');

    // The queue lands it: the real doc arrives on the updates
    // stream and the pending row goes away — no duplicate.
    await tasks.addUpdate('task1',
        authorId: 'me',
        authorName: 'Alex Morgan',
        text: 'Fixed the hinge',
        photoUrl: 'https://example.com/x.jpg');
    queue.completeEntry(queue.enqueued.single);
    await _pumpShort(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Fixed the hinge'), findsOneWidget);
    expect(find.text('Sending…'), findsNothing);
    expect(find.text('Alex Morgan'), findsWidgets);
  });

  testWidgets('a failed post keeps its content and shows an error',
      (tester) async {
    _mockConnectivity(['wifi']);
    final photo = (await tester.runAsync(_tempPhoto))!;
    final photoBytes =
        (await tester.runAsync(() => photo.readAsBytes()))!;
    final updatesController = StreamController<List<TaskUpdate>>.broadcast();
    final tasks = _FakeTaskService(updatesController);
    final queue = _FakePhotoQueueService()..enqueueResult = false;
    final photos = _FakePhotoService()
      ..photoPath = photo.path
      ..photoBytes = photoBytes;
    addTearDown(() async {
      await updatesController.close();
      await queue.entriesController.close();
    });
    await _pumpScreen(tester,
        tasks: tasks,
        queue: queue,
        photos: photos,
        updatesController: updatesController);

    await _postPhotoUpdate(tester,
        photoPath: photo.path, text: 'Fixed the hinge');

    // Nothing was parked, nothing posted — but the post is
    // NOT lost: the text and the thumbnail stay in the
    // composer and the failure is visible.
    expect(
        find.text(
            'Photo upload failed - check your connection and try again.'),
        findsOneWidget);
    expect(find.text('Fixed the hinge'), findsOneWidget);
    expect(find.text('Sending…'), findsNothing);
    expect(find.text('No updates yet.'), findsOneWidget);
    expect(tasks.posted, isEmpty);
  });

  testWidgets('an offline post queues visibly and lands after reconnect',
      (tester) async {
    _mockConnectivity(['none']);
    final photo = (await tester.runAsync(_tempPhoto))!;
    final photoBytes =
        (await tester.runAsync(() => photo.readAsBytes()))!;
    final updatesController = StreamController<List<TaskUpdate>>.broadcast();
    final tasks = _FakeTaskService(updatesController);
    final queue = _FakePhotoQueueService();
    final photos = _FakePhotoService()
      ..photoPath = photo.path
      ..photoBytes = photoBytes;
    addTearDown(() async {
      await updatesController.close();
      await queue.entriesController.close();
    });
    await _pumpScreen(tester,
        tasks: tasks,
        queue: queue,
        photos: photos,
        updatesController: updatesController);

    await _postPhotoUpdate(tester,
        photoPath: photo.path, text: 'Fixed the hinge');

    // Offline: the post is parked and shown as waiting for a
    // connection — not lost, not pretending to be sent.
    expect(find.text('Fixed the hinge'), findsOneWidget);
    expect(find.text('Will send when you\'re back online'), findsOneWidget);

    // Reconnect: the label flips to sending, then the queue
    // lands it as a real update.
    _mockConnectivity(['wifi']);
    queue.entriesController.add(queue.current);
    await _pumpShort(tester);
    expect(find.text('Sending…'), findsOneWidget);
    await tasks.addUpdate('task1',
        authorId: 'me',
        authorName: 'Alex Morgan',
        text: 'Fixed the hinge',
        photoUrl: 'https://example.com/x.jpg');
    queue.completeEntry(queue.enqueued.single);
    await _pumpShort(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Fixed the hinge'), findsOneWidget);
    expect(find.text('Sending…'), findsNothing);
    expect(find.text('Will send when you\'re back online'), findsNothing);
  });

  test('enqueue reports a failed park instead of swallowing it', () async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async {
        if (call.method == 'getApplicationDocumentsDirectory') {
          return (await Directory.systemTemp.createTemp()).path;
        }
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        null,
      );
    });
    final service = PhotoQueueService();

    // A missing camera file cannot be parked: false, and
    // nothing is recorded.
    expect(
        await service.enqueue(
          kind: 'taskUpdate',
          sourcePath: '/nope/missing.jpg',
          folder: 'taskPhotos',
          taskId: 'task1',
          authorId: 'me',
          authorName: 'Alex Morgan',
          text: 'hi',
        ),
        isFalse);
    expect(await service.watchEntries().first, isEmpty);

    // A real file parks fine and shows up in the live list.
    final file = await _tempPhoto();
    expect(
        await service.enqueue(
          kind: 'taskUpdate',
          sourcePath: file.path,
          folder: 'taskPhotos',
          taskId: 'task1',
          authorId: 'me',
          authorName: 'Alex Morgan',
          text: 'hi',
        ),
        isTrue);
    final entries = await service.watchEntries().first;
    expect(entries, hasLength(1));
    expect(entries.single.text, 'hi');
    expect(entries.single.kind, 'taskUpdate');
  });
}
