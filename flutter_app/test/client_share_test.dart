import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/client_share.dart';
import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/providers/locale_provider.dart';
import 'package:dyadespace/screens/client_share_route.dart';
import 'package:dyadespace/screens/client_share_screen.dart';
import 'package:dyadespace/services/client_share_service.dart';
import 'package:dyadespace/theme/app_theme.dart';

/// Client share link tests (Area G item 9): token shape, URL,
/// route parsing, model round-trip, and the public view
/// (renders progress; invalid token shows the invalid state).
/// No Firebase, no network — the service is faked.

final _progress = ClientSiteProgress(
  siteId: 'site1',
  siteName: 'Maple Court',
  siteAddress: '617 Saint-Rémi',
  stages: [
    ClientStageProgress(
      id: 'st1',
      name: 'Demolition',
      order: 1,
      status: 'completed',
      done: 3,
      total: 3,
    ),
    ClientStageProgress(
      id: 'st2',
      name: 'Plumbing',
      order: 2,
      status: 'inProgress',
      done: 1,
      total: 4,
    ),
  ],
  tasks: [
    ClientTaskProgress(
      id: 't1',
      title: 'Remove old vanity',
      status: 'done',
      stageId: 'st1',
      finishedAt: DateTime(2026, 11, 20),
      photoUrls: ['https://example.com/photo.jpg'],
    ),
    ClientTaskProgress(
      id: 't2',
      title: 'Install new vanity',
      status: 'inProgress',
      stageId: 'st2',
    ),
  ],
);

class _FakeClientShareService implements ClientShareService {
  final ClientSiteProgress? progress;
  final bool throwOnFetch;
  _FakeClientShareService({this.progress, this.throwOnFetch = false});

  @override
  Stream<List<ClientShare>> watchSharesForSite(String siteId) =>
      Stream.value(const []);

  @override
  Future<ClientShare> createShare(
          {required Site site, required String createdBy}) async =>
      ClientShare(
          token: 'tok123',
          siteId: site.id,
          siteName: site.name,
          createdBy: createdBy);

  @override
  Future<void> revokeShare(String token) async {}

  @override
  Future<ClientShare> regenerateShare(
          {required Site site, required String createdBy}) async =>
      createShare(site: site, createdBy: createdBy);

  @override
  Future<ClientSiteProgress> fetchPublicProgress(String token) async {
    if (throwOnFetch) throw StateError('invalid token');
    return progress!;
  }
}

Future<void> _pumpShare(
  WidgetTester tester,
  ClientShareService service, {
  String token = 'tok123',
}) async {
  await initializeDateFormatting('en');
  tester.view.physicalSize = const Size(1200, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(const AppStrings('en')),
        clientShareServiceProvider.overrideWithValue(service),
      ],
      child: MaterialApp(
        theme: buildAppDarkTheme(),
        home: Scaffold(body: ClientShareScreen(token: token)),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  test('token: 32 url-safe chars, unique per call', () {
    final a = newClientShareToken();
    final b = newClientShareToken();
    expect(a.length, clientShareTokenLength);
    expect(RegExp(r'^[A-Za-z0-9]{32}$').hasMatch(a), isTrue);
    expect(a, isNot(b));
  });

  test('clientShareUrl ends with /client/<token>', () {
    expect(clientShareUrl('abc123'), endsWith('/client/abc123'));
  });

  test('ClientShare round-trips through toMap/fromMap', () {
    const share = ClientShare(
      token: 'tok123',
      siteId: 'site1',
      siteName: 'Maple Court',
      createdBy: 'me',
    );
    final restored = ClientShare.fromMap('tok123', share.toMap());
    expect(restored.token, 'tok123');
    expect(restored.siteId, 'site1');
    expect(restored.siteName, 'Maple Court');
    expect(restored.revoked, isFalse);
    expect(share.copyWith(revoked: true).revoked, isTrue);
  });

  test('ClientSiteProgress.recentlyCompleted is newest-first', () {
    final progress = ClientSiteProgress(
      siteId: 's',
      siteName: 'S',
      siteAddress: '',
      stages: const [],
      tasks: [
        ClientTaskProgress(
            id: 'old',
            title: 'Old',
            status: 'done',
            finishedAt: DateTime(2026, 11, 18)),
        ClientTaskProgress(
            id: 'new',
            title: 'New',
            status: 'done',
            finishedAt: DateTime(2026, 11, 20)),
        ClientTaskProgress(id: 'open', title: 'Open', status: 'todo'),
      ],
    );
    final recent = progress.recentlyCompleted;
    expect(recent.map((t) => t.id).toList(), ['new', 'old']);
  });

  test('clientShareRoute parses /client/<token>, rejects the rest', () {
    expect(clientShareRoute(const RouteSettings(name: '/client/tok123')),
        isNotNull);
    expect(
        clientShareRoute(const RouteSettings(name: '/client/tok123/')),
        isNotNull);
    expect(clientShareRoute(const RouteSettings(name: '/client/')), isNull);
    expect(clientShareRoute(const RouteSettings(name: '/client/a/b')), isNull);
    expect(clientShareRoute(const RouteSettings(name: '/privacy')), isNull);
    expect(clientShareRoute(const RouteSettings(name: '/')), isNull);
    expect(clientShareRoute(const RouteSettings(name: '')), isNull);
  });

  testWidgets('public view renders site, stages, tasks, photos',
      (tester) async {
    await _pumpShare(
        tester, _FakeClientShareService(progress: _progress));
    expect(tester.takeException(), isNull);
    expect(find.text('Maple Court'), findsOneWidget);
    expect(find.text('Demolition'), findsOneWidget);
    expect(find.text('Plumbing'), findsOneWidget);
    expect(find.text('Remove old vanity'), findsWidgets);
    expect(find.text('Install new vanity'), findsOneWidget);
    expect(find.text('Recently completed'), findsOneWidget);
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('public view shows the invalid state for a bad token',
      (tester) async {
    await _pumpShare(
        tester, _FakeClientShareService(throwOnFetch: true));
    expect(tester.takeException(), isNull);
    expect(
      find.text('This link is not valid, or it was revoked.'),
      findsOneWidget,
    );
  });

  testWidgets('route /client/<token> opens the public view', (tester) async {
    await initializeDateFormatting('en');
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(const AppStrings('en')),
          clientShareServiceProvider
              .overrideWithValue(_FakeClientShareService(progress: _progress)),
        ],
        child: MaterialApp(
          theme: buildAppDarkTheme(),
          onGenerateRoute: clientShareRoute,
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    final ctx = tester.element(find.text('home'));
    Navigator.of(ctx).pushNamed('/client/tok123');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Maple Court'), findsOneWidget);
  });
}
