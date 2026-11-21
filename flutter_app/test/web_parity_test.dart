import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/app_user.dart';
import 'package:dyadespace/models/breadcrumb.dart';
import 'package:dyadespace/models/chat.dart';
import 'package:dyadespace/models/day_report.dart';
import 'package:dyadespace/models/delivery_run.dart';
import 'package:dyadespace/models/notification_item.dart';
import 'package:dyadespace/models/run_stop.dart';
import 'package:dyadespace/models/material_request.dart';
import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/models/task_item.dart';
import 'package:dyadespace/models/team.dart';
import 'package:dyadespace/models/time_entry.dart';
import 'package:dyadespace/models/unit.dart';
import 'package:dyadespace/providers/auth_provider.dart';
import 'package:dyadespace/providers/chat_provider.dart';
import 'package:dyadespace/providers/locale_provider.dart';
import 'package:dyadespace/providers/material_requests_provider.dart';
import 'package:dyadespace/providers/notifications_provider.dart';
import 'package:dyadespace/providers/runs_provider.dart';
import 'package:dyadespace/providers/sites_provider.dart';
import 'package:dyadespace/providers/stages_provider.dart';
import 'package:dyadespace/providers/tasks_provider.dart';
import 'package:dyadespace/providers/teams_provider.dart';
import 'package:dyadespace/providers/time_entries_provider.dart';
import 'package:dyadespace/providers/units_provider.dart';
import 'package:dyadespace/screens/chat_list_screen.dart';
import 'package:dyadespace/screens/web/control_center_shell.dart';
import 'package:dyadespace/screens/web/web_board_screen.dart';
import 'package:dyadespace/screens/web/web_crew_screen.dart';
import 'package:dyadespace/screens/web/web_hours_screen.dart';
import 'package:dyadespace/screens/web/web_reports_screen.dart';
import 'package:dyadespace/screens/web/web_requests_screen.dart';
import 'package:dyadespace/screens/web/web_run_screen.dart';
import 'package:dyadespace/screens/web/web_sites_screen.dart';
import 'package:dyadespace/screens/worker_profile_screen.dart';
import 'package:dyadespace/services/chat_service.dart';
import 'package:dyadespace/services/progress_share.dart';
import 'package:dyadespace/services/report_service.dart';
import 'package:dyadespace/theme/app_theme.dart';
import 'package:dyadespace/widgets/task_chain.dart';

/// Web parity tests (Nov 15, 2026): everything an admin can do
/// on the phone, they can do on the web, except clocking in.
/// Pumped with the REAL app theme (the topbar bug was hidden by
/// the default Material theme) and mocked providers — no
/// Firebase, no network. Run on Chrome (`flutter test
/// --platform chrome`) for a real-browser layout proof, or on
/// the VM for a fast check.
const _me = AppUser(
  id: 'me',
  name: 'Alex Morgan',
  email: 'alex@example.com',
  role: UserRole.admin,
);

const _rolando = AppUser(
  id: 'rolando',
  name: 'Sam',
  email: 'sam@example.com',
  role: UserRole.admin,
);

const _site = Site(
  id: 'site1',
  name: 'Lakeside',
  address: '30 Boul. Montarville',
  lat: 45.6,
  lng: -73.4,
);

const _siteWide = Site(
  id: 'site2',
  name: 'Maple Court',
  address: '617 Saint-Rémi',
  lat: 45.5,
  lng: -73.6,
  radiusMeters: 250,
);

Future<void> _pump(
  WidgetTester tester,
  Size size,
  Widget child, {
  List<Override> extraOverrides = const [],
}) async {
  await initializeDateFormatting('en');
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(const AppStrings('en')),
        currentUserProvider.overrideWith((ref) => Stream.value(_me)),
        allUsersProvider
            .overrideWith((ref) => Stream.value(<AppUser>[_me, _rolando])),
        openMaterialRequestsCountProvider.overrideWithValue(0),
        allTasksProvider.overrideWith((ref) => Stream.value(<TaskItem>[])),
        allTimeEntriesProvider
            .overrideWith((ref) => Stream.value(<TimeEntry>[])),
        allRunsProvider
            .overrideWith((ref) => Stream.value(<DeliveryRun>[])),
        siteByIdProvider.overrideWithValue(<String, Site>{}),
        sitesProvider.overrideWith((ref) => Stream.value(<Site>[])),
        stageIndexProvider.overrideWithValue(null),
        ...extraOverrides,
      ],
      child: MaterialApp(
        theme: buildAppDarkTheme(),
        // Sections are normally hosted inside a Scaffold (the
        // shell or the phone shell); the Scaffold here is the
        // Material ancestor TextField/DropdownButton need.
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

/// ChatService without Firestore: the real constructor reads
/// FirebaseFirestore.instance, which throws in tests. The list
/// screen only reads the provider (to pass it to the
/// team-channel ensure, which never runs with no teams) — the
/// fake never gets a real call here.
class _FakeChatService implements ChatService {
  @override
  Stream<List<Conversation>> watchConversations(String myId) =>
      Stream.value(const []);

  @override
  Stream<Conversation?> watchConversation(String conversationId) =>
      Stream.value(null);

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) =>
      Stream.value(const []);

  @override
  Future<String> findOrCreateDm(String meId, String otherId) async =>
      'dm_${meId}_$otherId';

  @override
  Future<String> ensureTeamChannel({
    required Team team,
    required List<String> adminManagerIds,
    required String createdBy,
  }) async =>
      'team_${team.id}';

  @override
  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String senderName,
    required String text,
    String? mediaUrl,
    String? mediaType,
    int? mediaDurationSeconds,
    String? previewLabel,
  }) async {}

  @override
  Future<BroadcastResult> sendBroadcast({
    required String senderId,
    required String senderName,
    required List<String> recipientIds,
    required String text,
    String? mediaUrl,
    String? mediaType,
    int? mediaDurationSeconds,
    String? previewLabel,
  }) async =>
      const BroadcastResult();

  @override
  Future<void> markRead({
    required String conversationId,
    required String myId,
    required List<ChatMessage> messages,
  }) async {}
}

/// ReportService without Firestore: the real constructor calls
/// FirebaseFirestore.instance, which throws in tests.
class _FakeReportService implements ReportService {
  final List<DayReport> reports;
  _FakeReportService({this.reports = const []});

  @override
  Stream<List<DayReport>> watchReports() => Stream.value(reports);

  @override
  Stream<String> watchEodChannel() => Stream.value('both');

  @override
  Stream<String> watchEodTime() => Stream.value('18:00');

  @override
  Future<void> saveEodChannel(String channel) async {}

  @override
  Future<void> saveEodTime(String time) async {}

  @override
  Future<void> requestSendNow(String requestedBy) async {}

  @override
  Future<DayReport> buildAndSaveReport(DateTime day) =>
      throw UnimplementedError();
}

void main() {
  testWidgets('shell 1913px: Chats nav item and bell render',
      (tester) async {
    await _pump(
      tester,
      const Size(1913, 1065),
      const ControlCenterShell(),
      extraOverrides: [
        notificationsProvider.overrideWith((ref) => Stream.value(
              <AppNotification>[
                AppNotification(
                  id: 'n1',
                  userId: 'me',
                  title: 'Task assigned',
                  body: 'Check the board',
                  type: 'taskAssigned',
                  createdAt: DateTime(2026, 11, 15, 8, 0),
                  read: false,
                ),
              ],
            )),
      ],
    );
    expect(tester.takeException(), isNull);
    // Chats is the last nav item, after Settings.
    expect(find.text('Chats'), findsWidgets);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
    // One unread notification -> badge "1".
    expect(find.text('1'), findsWidgets);
  });

  testWidgets('shell 390px: hamburger and bell render', (tester) async {
    await _pump(
      tester,
      const Size(390, 844),
      const ControlCenterShell(),
      extraOverrides: [
        notificationsProvider
            .overrideWith((ref) => Stream.value(<AppNotification>[])),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.menu), findsOneWidget);
    expect(find.byIcon(Icons.notifications_outlined), findsOneWidget);
  });

  testWidgets('sites: New site button, radius lines, edit/delete',
      (tester) async {
    await _pump(
      tester,
      const Size(1913, 1065),
      WebSitesScreen(onNavigate: (_, {siteId, query}) {}),
      extraOverrides: [
        sitesProvider.overrideWith(
            (ref) => Stream.value(<Site>[_site, _siteWide])),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Add site'), findsOneWidget);
    // No stored radius -> the 100 m default; stored 250 -> 250 m.
    expect(find.text('Radius 100 m'), findsOneWidget);
    expect(find.text('Radius 250 m'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
    expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
  });

  testWidgets('board: chain strip renders, Plan a run present',
      (tester) async {
    final today = DateTime.now();
    final first = TaskItem(
      id: 't1',
      title: 'Frame the shower',
      siteId: 'site1',
      assigneeIds: ['me'],
      createdBy: 'me',
      dueDate: today,
    );
    final second = TaskItem(
      id: 't2',
      title: 'Plumbing',
      siteId: 'site1',
      assigneeIds: ['me'],
      createdBy: 'me',
      dueDate: today,
      dependsOnTaskId: 't1',
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      const WebBoardScreen(),
      extraOverrides: [
        allTasksProvider
            .overrideWith((ref) => Stream.value(<TaskItem>[first, second])),
        sitesProvider.overrideWith((ref) => Stream.value(<Site>[_site])),
        siteByIdProvider.overrideWithValue(<String, Site>{'site1': _site}),
        allUnitsProvider.overrideWith((ref) => Stream.value([])),
      ],
    );
    expect(tester.takeException(), isNull);
    // "Plan a delivery run" is a button in the chips row on the
    // web Board (same entry point as the phone Board's Actions
    // sheet — the web Board has no Actions sheet of its own).
    expect(find.text('Plan a delivery run'), findsOneWidget);
    // One ChainStrip footer per task in the chain.
    expect(find.byType(ChainStrip), findsNWidgets(2));
  });

  testWidgets('hours: Auto tag and edit button on an auto entry',
      (tester) async {
    final now = DateTime.now();
    final entry = TimeEntry(
      id: 'e1',
      userId: 'rolando',
      userName: 'Sam',
      siteId: 'site1',
      siteName: 'Lakeside',
      date: DateFormat('yyyy-MM-dd').format(now),
      clockInAt: now.subtract(const Duration(hours: 2)),
      clockOutAt: now,
      hours: 2.0,
      auto: true,
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      const WebHoursScreen(),
      extraOverrides: [
        allTimeEntriesProvider
            .overrideWith((ref) => Stream.value(<TimeEntry>[entry])),
        sitesProvider.overrideWith((ref) => Stream.value(<Site>[_site])),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Auto'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
  });

  testWidgets('reports: Share progress and photo proof strip',
      (tester) async {
    final today = DateTime.now();
    final photoTask = TaskItem(
      id: 't1',
      title: 'Install the vanity',
      siteId: 'site1',
      assigneeIds: ['me'],
      createdBy: 'me',
      status: TaskStatus.done,
      finishedAt: today,
      photoUrls: const ['https://example.com/photo.jpg'],
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      const WebReportsScreen(),
      extraOverrides: [
        allTasksProvider
            .overrideWith((ref) => Stream.value(<TaskItem>[photoTask])),
        sitesProvider.overrideWith((ref) => Stream.value(<Site>[_site])),
        siteByIdProvider.overrideWithValue(<String, Site>{'site1': _site}),
        reportServiceProvider.overrideWithValue(_FakeReportService()),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Share progress'), findsOneWidget);
    expect(find.text('Photo proof — today'), findsOneWidget);
    // The photo thumb itself (network image — renders as a
    // broken-image box in tests, but the strip is there).
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('run screen: Edit run button present', (tester) async {
    final run = DeliveryRun(
      id: 'r1',
      date: DateTime.now(),
      driverId: 'sean',
      stops: const [
        RunStop(
          id: 's1',
          orderIndex: 0,
          title: 'Pick up materials',
          address: '30 Boul. Montarville',
        ),
      ],
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      WebRunScreen(run: run, driverName: 'Drew'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Edit run'), findsOneWidget);
  });

  testWidgets('chats: DM row renders, new-message button present',
      (tester) async {
    const dm = Conversation(
      id: 'dm_me_rolando',
      type: 'dm',
      participantIds: ['me', 'rolando'],
      lastMessage: 'On my way',
      lastSenderId: 'rolando',
      updatedAt: null,
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      const ChatListScreen(),
      extraOverrides: [
        conversationsProvider
            .overrideWith((ref) => Stream.value(<Conversation>[dm])),
        teamsProvider.overrideWith((ref) => Stream.value([])),
        chatServiceProvider.overrideWithValue(_FakeChatService()),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('On my way'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsOneWidget);
  });

  testWidgets('profile on web: Tasks and Clock-in tabs render',
      (tester) async {
    await _pump(
      tester,
      const Size(1913, 1065),
      const WorkerProfileScreen(user: _rolando),
      extraOverrides: [
        siteByIdProvider.overrideWithValue(<String, Site>{'site1': _site}),
        entriesForUserProvider.overrideWith(
            (ref, uid) => Stream.value(<TimeEntry>[])),
        openEntryForUserProvider.overrideWith(
            (ref, uid) => Stream.value(null)),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Tasks'), findsOneWidget);
    expect(find.text('Clock in'), findsOneWidget);
    // Admin viewing someone else's profile: the role changer.
    expect(find.text('Admin'), findsWidgets);
  });

  test('buildProgressText: done / in-progress / blocked sections', () {
    const s = AppStrings('en');
    final tasks = [
      TaskItem(
        id: 't1',
        title: 'Done task',
        siteId: 'site1',
        assigneeIds: ['me'],
        createdBy: 'me',
        status: TaskStatus.done,
      ),
      TaskItem(
        id: 't2',
        title: 'Working task',
        siteId: 'site1',
        assigneeIds: ['me'],
        createdBy: 'me',
        status: TaskStatus.inProgress,
      ),
      TaskItem(
        id: 't3',
        title: 'Other site',
        siteId: 'site2',
        assigneeIds: ['me'],
        createdBy: 'me',
        status: TaskStatus.done,
      ),
    ];
    final text = buildProgressText(s, _site, tasks);
    expect(text, contains('Lakeside'));
    expect(text, contains('Done task'));
    expect(text, contains('Working task'));
    expect(text.contains('Other site'), isFalse);
  });

  // Interaction proofs: the parity features do not just render —
  // their buttons actually open the editor / builder / map.
  testWidgets('sites: Add site opens the editor dialog',
      (tester) async {
    await _pump(
      tester,
      const Size(1913, 1065),
      WebSitesScreen(onNavigate: (_, {siteId, query}) {}),
      extraOverrides: [
        sitesProvider.overrideWith(
            (ref) => Stream.value(<Site>[_site, _siteWide])),
      ],
    );
    await tester.tap(find.text('Add site'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The editor dialog: name field + Save.
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('hours: edit button opens the entry editor',
      (tester) async {
    final now = DateTime.now();
    final entry = TimeEntry(
      id: 'e1',
      userId: 'rolando',
      userName: 'Sam',
      siteId: 'site1',
      siteName: 'Lakeside',
      date: DateFormat('yyyy-MM-dd').format(now),
      clockInAt: now.subtract(const Duration(hours: 2)),
      clockOutAt: now,
      hours: 2.0,
      auto: true,
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      // The real shell always watches the signed-in user, so the
      // provider is warm before anyone taps Edit. Mirror that
      // here: the dialog reads it with ref.read, which sees null
      // until the stream has emitted at least once.
      Consumer(builder: (context, ref, _) {
        ref.watch(currentUserProvider);
        return const WebHoursScreen();
      }),
      extraOverrides: [
        allTimeEntriesProvider
            .overrideWith((ref) => Stream.value(<TimeEntry>[entry])),
        sitesProvider.overrideWith((ref) => Stream.value(<Site>[_site])),
        siteByIdProvider.overrideWithValue(<String, Site>{'site1': _site}),
      ],
    );
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Save'), findsOneWidget);
  });

  testWidgets('board: Plan a delivery run opens the run builder',
      (tester) async {
    final today = DateTime.now();
    final first = TaskItem(
      id: 't1',
      title: 'Frame the shower',
      siteId: 'site1',
      assigneeIds: ['me'],
      createdBy: 'me',
      dueDate: today,
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      const WebBoardScreen(),
      extraOverrides: [
        allTasksProvider
            .overrideWith((ref) => Stream.value(<TaskItem>[first])),
        sitesProvider.overrideWith((ref) => Stream.value(<Site>[_site])),
        siteByIdProvider.overrideWithValue(<String, Site>{'site1': _site}),
        allUnitsProvider.overrideWith((ref) => Stream.value([])),
        allUsersProvider
            .overrideWith((ref) => Stream.value(<AppUser>[_me, _rolando])),
        approvedMaterialRequestsProvider
            .overrideWith((ref) => Stream.value([])),
      ],
    );
    await tester.tap(find.text('Plan a delivery run'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Add stop'), findsOneWidget);
  });

  testWidgets('hours: tapping an entry opens the map', (tester) async {
    final now = DateTime.now();
    final entry = TimeEntry(
      id: 'e1',
      userId: 'rolando',
      userName: 'Sam',
      siteId: 'site1',
      siteName: 'Lakeside',
      date: DateFormat('yyyy-MM-dd').format(now),
      clockInAt: now.subtract(const Duration(hours: 2)),
      clockOutAt: now,
      hours: 2.0,
      clockInLat: 45.6,
      clockInLng: -73.4,
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      const WebHoursScreen(),
      extraOverrides: [
        allTimeEntriesProvider
            .overrideWith((ref) => Stream.value(<TimeEntry>[entry])),
        sitesProvider.overrideWith((ref) => Stream.value(<Site>[_site])),
        breadcrumbsProvider
            .overrideWith((ref, id) => Stream.value(<Breadcrumb>[])),
      ],
    );
    await tester.tap(find.text('Sam').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The map screen: pin at the fix + Open in Maps.
    expect(find.text('Open in Maps'), findsOneWidget);
  });

  testWidgets('shell: bell opens the notifications list',
      (tester) async {
    await _pump(
      tester,
      const Size(1913, 1065),
      const ControlCenterShell(),
      extraOverrides: [
        notificationsProvider.overrideWith((ref) => Stream.value([
              AppNotification(
                id: 'n1',
                userId: 'me',
                title: 'Task assigned',
                body: 'Check the board',
                type: 'taskAssigned',
                createdAt: DateTime(2026, 11, 15, 8, 0),
                read: false,
              ),
            ])),
      ],
    );
    await tester.tap(find.byIcon(Icons.notifications_outlined));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Task assigned'), findsOneWidget);
  });

  testWidgets('shell: Chats nav opens the chats section',
      (tester) async {
    const dm = Conversation(
      id: 'dm_me_rolando',
      type: 'dm',
      participantIds: ['me', 'rolando'],
      lastMessage: 'On my way',
      lastSenderId: 'rolando',
      updatedAt: null,
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      const ControlCenterShell(),
      extraOverrides: [
        conversationsProvider
            .overrideWith((ref) => Stream.value(<Conversation>[dm])),
        teamsProvider.overrideWith((ref) => Stream.value([])),
        chatServiceProvider.overrideWithValue(_FakeChatService()),
      ],
    );
    await tester.tap(find.text('Chats').first);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Sam'), findsOneWidget);
    expect(find.text('On my way'), findsOneWidget);
  });

  // --- Area G (Nov 21 audit): web parity fixes ---

  testWidgets('crew: invite, bulk invite, week nav, pending invites',
      (tester) async {
    await _pump(
      tester,
      const Size(1913, 1065),
      const WebCrewScreen(),
      extraOverrides: [
        pendingInvitesProvider.overrideWith((ref) => Stream.value([
              <String, dynamic>{
                'id': 'inv1',
                'email': 'new@example.com',
                'role': 'worker',
              },
            ])),
        teamsProvider.overrideWith((ref) => Stream.value(<Team>[])),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Invite'), findsOneWidget);
    expect(find.text('Bulk invite'), findsOneWidget);
    expect(find.byTooltip('Previous week'), findsOneWidget);
    expect(find.byTooltip('Next week'), findsOneWidget);
    expect(find.text('Pending invites (1)'), findsOneWidget);
    expect(find.text('new@example.com'), findsOneWidget);
    // Invite opens the single-invite dialog (email + role).
    await tester.tap(find.text('Invite'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Email'), findsWidgets);
  });

  testWidgets('crew: stale open entry is labelled Still clocked in',
      (tester) async {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final stale = TimeEntry(
      id: 'e-stale',
      userId: 'rolando',
      userName: 'Sam',
      siteId: 'site1',
      siteName: 'Lakeside',
      date: DateFormat('yyyy-MM-dd').format(yesterday),
      clockInAt: DateTime(yesterday.year, yesterday.month, yesterday.day, 8),
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      const WebCrewScreen(),
      extraOverrides: [
        allTimeEntriesProvider
            .overrideWith((ref) => Stream.value(<TimeEntry>[stale])),
        pendingInvitesProvider
            .overrideWith((ref) => Stream.value(const [])),
        teamsProvider.overrideWith((ref) => Stream.value(<Team>[])),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Still clocked in'), findsOneWidget);
    expect(find.textContaining('Lakeside'), findsOneWidget);
  });

  testWidgets('crew: two open entries — today’s wins over the stale one',
      (tester) async {
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    final stale = TimeEntry(
      id: 'e-stale',
      userId: 'rolando',
      userName: 'Sam',
      siteId: 'site2',
      siteName: 'Maple Court',
      date: DateFormat('yyyy-MM-dd').format(yesterday),
      clockInAt: DateTime(yesterday.year, yesterday.month, yesterday.day, 8),
    );
    final todayEntry = TimeEntry(
      id: 'e-today',
      userId: 'rolando',
      userName: 'Sam',
      siteId: 'site1',
      siteName: 'Lakeside',
      date: DateFormat('yyyy-MM-dd').format(now),
      clockInAt: now.subtract(const Duration(hours: 1)),
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      const WebCrewScreen(),
      extraOverrides: [
        allTimeEntriesProvider.overrideWith(
            (ref) => Stream.value(<TimeEntry>[stale, todayEntry])),
        pendingInvitesProvider
            .overrideWith((ref) => Stream.value(const [])),
        teamsProvider.overrideWith((ref) => Stream.value(<Team>[])),
      ],
    );
    expect(tester.takeException(), isNull);
    // Both open entries are kept, but the row shows today's —
    // no "Still clocked in" label for this person.
    expect(find.text('Still clocked in'), findsNothing);
    expect(find.textContaining('Lakeside'), findsOneWidget);
  });

  testWidgets('sites: units section with add, counts, share button',
      (tester) async {
    final today = DateTime.now();
    final unitTask = TaskItem(
      id: 't1',
      title: 'Frame the shower',
      siteId: 'site1',
      unitId: 'u1',
      assigneeIds: ['me'],
      createdBy: 'me',
      status: TaskStatus.done,
      dueDate: today,
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      WebSitesScreen(onNavigate: (_, {siteId, query}) {}),
      extraOverrides: [
        sitesProvider.overrideWith(
            (ref) => Stream.value(<Site>[_site])),
        allUnitsProvider.overrideWith((ref) => Stream.value(<Unit>[
              const Unit(id: 'u1', siteId: 'site1', name: '502', order: 1),
            ])),
        allTasksProvider
            .overrideWith((ref) => Stream.value(<TaskItem>[unitTask])),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Units'), findsOneWidget);
    expect(find.text('Add unit'), findsOneWidget);
    expect(find.text('502'), findsOneWidget);
    expect(find.byIcon(Icons.share_outlined), findsOneWidget);
  });

  testWidgets('run screen: drive controls present', (tester) async {
    final run = DeliveryRun(
      id: 'r1',
      date: DateTime.now(),
      driverId: 'sean',
      stops: const [
        RunStop(
          id: 's1',
          orderIndex: 0,
          title: 'Drop off vanity',
          address: '30 Boul. Montarville',
          kind: StopKind.dropoff,
        ),
      ],
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      WebRunScreen(run: run, driverName: 'Drew'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Edit run'), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.text("I'm here"), findsOneWidget);
    expect(find.text('Delayed 15 min'), findsOneWidget);
    expect(find.text('Delayed 30 min'), findsOneWidget);
    expect(find.text("Couldn't complete"), findsOneWidget);
    expect(find.text('Mileage'), findsOneWidget);
    expect(find.text('Add photo'), findsOneWidget);
  });

  testWidgets('requests: new-request button opens the site picker',
      (tester) async {
    await _pump(
      tester,
      const Size(1913, 1065),
      const WebRequestsScreen(),
      extraOverrides: [
        materialRequestsProvider
            .overrideWith((ref) => Stream.value(<MaterialRequest>[])),
        sitesProvider.overrideWith(
            (ref) => Stream.value(<Site>[_site])),
        siteByIdProvider.overrideWithValue(<String, Site>{'site1': _site}),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Request materials'), findsOneWidget);
    await tester.tap(find.text('Request materials'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Pick a site'), findsOneWidget);
  });

  testWidgets('reports: archive past 7, week view, who did what',
      (tester) async {
    final today = DateTime.now();
    final reports = List.generate(
      10,
      (i) => DayReport(
        id: 'r$i',
        date: today.subtract(Duration(days: i)),
        doneCount: i,
      ),
    );
    final doneTask = TaskItem(
      id: 't1',
      title: 'Install the vanity',
      siteId: 'site1',
      assigneeIds: ['me'],
      createdBy: 'me',
      status: TaskStatus.done,
      finishedAt: today,
    );
    await _pump(
      tester,
      // Tall viewport: the archive sits below the week view in
      // a lazy ListView, so short screens never build its rows.
      const Size(1913, 3000),
      const WebReportsScreen(),
      extraOverrides: [
        allTasksProvider
            .overrideWith((ref) => Stream.value(<TaskItem>[doneTask])),
        sitesProvider.overrideWith((ref) => Stream.value(<Site>[_site])),
        siteByIdProvider.overrideWithValue(<String, Site>{'site1': _site}),
        reportServiceProvider
            .overrideWithValue(_FakeReportService(reports: reports)),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('This week'), findsOneWidget);
    expect(find.text('Who did what'), findsOneWidget);
    expect(find.text('Alex Morgan'), findsOneWidget);
    expect(find.text('Install the vanity'), findsWidgets);
    // The archive shows all 10 — with the old take(7) the
    // oldest report's date would be missing.
    final oldest = DateFormat('EEEE, MMM d')
        .format(today.subtract(const Duration(days: 9)));
    expect(find.text(oldest), findsOneWidget);
  });

  testWidgets('reports: manager sees no send controls', (tester) async {
    const manager = AppUser(
      id: 'mgr',
      name: 'Maggie',
      email: 'm@example.com',
      role: UserRole.manager,
    );
    await _pump(
      tester,
      const Size(1913, 1065),
      const WebReportsScreen(),
      extraOverrides: [
        currentUserProvider.overrideWith((ref) => Stream.value(manager)),
        reportServiceProvider.overrideWithValue(_FakeReportService()),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Send now'), findsNothing);
    expect(find.text('Send end-of-day report'), findsNothing);
  });

  testWidgets('reports: admin sees send, email hidden until transport ready',
      (tester) async {
    await _pump(
      tester,
      const Size(1913, 1065),
      const WebReportsScreen(),
      extraOverrides: [
        reportServiceProvider.overrideWithValue(_FakeReportService()),
      ],
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Send now'), findsOneWidget);
    // No email/both segments until emailTransportReady.
    expect(find.text('Email'), findsNothing);
    expect(
      find.text(
          'Email reports need the Trigger Email extension installed. Ask an admin to set it up.'),
      findsOneWidget,
    );
  });
}
