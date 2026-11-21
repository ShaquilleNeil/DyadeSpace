import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/app_user.dart';
import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/models/time_entry.dart';
import 'package:dyadespace/providers/auth_provider.dart';
import 'package:dyadespace/providers/locale_provider.dart';
import 'package:dyadespace/providers/location_provider.dart';
import 'package:dyadespace/providers/sites_provider.dart';
import 'package:dyadespace/providers/time_entries_provider.dart';
import 'package:dyadespace/services/location_service.dart';
import 'package:dyadespace/services/time_entry_service.dart';
import 'package:dyadespace/theme/app_theme.dart';
import 'package:dyadespace/widgets/clock_in_button.dart';

/// One-tap site switch (Nov 16, 2026): when a worker is
/// clocked in at site A and is now inside a DIFFERENT site
/// B's fence, the button offers "Switch to B" instead of a
/// plain clock-out — one tap closes A (with the fix as its
/// clock-out location) and opens B, reusing the auto
/// clock-in's switch path. Pumped with the REAL app theme
/// and mocked providers + a fake GPS fix — no Firebase, no
/// network, no real location.
const _me = AppUser(
  id: 'me',
  name: 'Alex Morgan',
  email: 'alex@example.com',
  role: UserRole.admin,
);

const _siteA = Site(
  id: 'siteA',
  name: 'Maple Court',
  address: '617 Saint-Rémi',
  lat: 45.0400,
  lng: -73.0000,
);

const _siteB = Site(
  id: 'siteB',
  name: 'Lakeside',
  address: '30 Boul. Montarville',
  lat: 45.0500,
  lng: -73.0100,
);

String _today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

TimeEntry _openAtA() => TimeEntry(
      id: 'e1',
      userId: 'me',
      userName: 'Alex Morgan',
      siteId: 'siteA',
      siteName: 'Maple Court',
      date: _today(),
      clockInAt: DateTime.now().subtract(const Duration(hours: 2)),
    );

/// Records what the button asked the service to do, instead
/// of touching Firestore.
class _FakeTimeEntryService extends TimeEntryService {
  final List<({Site site, PositionFix? fix, PositionFix? closeFix})>
      clockIns = [];
  final List<TimeEntry> clockOuts = [];

  @override
  Future<String> clockIn({
    required AppUser user,
    required Site site,
    bool skipLocation = false,
    PositionFix? fix,
    bool auto = false,
    PositionFix? closeFix,
  }) async {
    clockIns.add((site: site, fix: fix, closeFix: closeFix));
    return 'new-entry';
  }

  @override
  Future<void> clockOut(TimeEntry entry, {PositionFix? fix}) async {
    clockOuts.add(entry);
  }
}

class _FakeLocationService extends LocationService {
  PositionFix? fix;

  @override
  Future<PositionFix?> currentFix() async => fix;
}

Future<void> _pumpButton(
  WidgetTester tester, {
  required TimeEntry? open,
  required _FakeTimeEntryService service,
  required _FakeLocationService location,
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
        openTimeEntryProvider.overrideWith((ref) => Stream.value(open)),
        siteByIdProvider.overrideWithValue(
            <String, Site>{'siteA': _siteA, 'siteB': _siteB}),
        timeEntryServiceProvider.overrideWithValue(service),
        locationServiceProvider.overrideWithValue(location),
      ],
      child: MaterialApp(
        theme: buildAppDarkTheme(),
        home: const Scaffold(body: Center(child: ClockInButton())),
      ),
    ),
  );
  await tester.pumpAndSettle();
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
  });

  setUp(() {
    // Location consent already given, so the button may take
    // a fix for the switch candidate (setMockInitialValues
    // nullifies the cached instance, so this is per-test).
    SharedPreferences.setMockInitialValues(
        {'location_consent_given': true});
    // Route tracking's foreground-service channel: the button
    // restarts tracking after a switch, and the plugin's
    // isRunningService getter throws on a null reply — answer
    // it like a real (stopped, then started) service.
    var running = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      (call) async {
        switch (call.method) {
          case 'isRunningService':
            return running;
          case 'startService':
            running = true;
            return null;
          case 'stopService':
            running = false;
            return null;
          default:
            return null;
        }
      },
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('flutter_foreground_task/methods'),
      null,
    );
  });

  testWidgets('open at A + fix inside B renders Switch to B',
      (tester) async {
    final service = _FakeTimeEntryService();
    final location = _FakeLocationService()
      ..fix = const PositionFix(lat: 45.0500, lng: -73.0100);
    await _pumpButton(tester,
        open: _openAtA(), service: service, location: location);
    expect(tester.takeException(), isNull);
    final label = find.text('Switch to Lakeside');
    expect(label, findsOneWidget);
    // The label fits in full at 390px — no ellipsis.
    expect(tester.renderObject<RenderParagraph>(label).didExceedMaxLines,
        isFalse);
    expect(find.text('Clock out'), findsNothing);
  });

  testWidgets('tapping Switch to B closes A and opens B in one tap',
      (tester) async {
    final service = _FakeTimeEntryService();
    final location = _FakeLocationService()
      ..fix = const PositionFix(lat: 45.0500, lng: -73.0100);
    await _pumpButton(tester,
        open: _openAtA(), service: service, location: location);
    await tester.tap(find.text('Switch to Lakeside'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // One clock-in at B, with the fix as both the new
    // entry's coordinates and the closed entry's clock-out
    // location — the auto switch path. No plain clock-out.
    expect(service.clockIns, hasLength(1));
    expect(service.clockIns.single.site.id, 'siteB');
    expect(service.clockIns.single.fix?.lat, 45.0500);
    expect(service.clockIns.single.closeFix?.lat, 45.0500);
    expect(service.clockOuts, isEmpty);
    // The snackbar names both sites.
    expect(find.text('Clocked out of Maple Court, clocked in at Lakeside.'),
        findsOneWidget);
  });

  testWidgets('same-site fix still shows Clock out and clocks out',
      (tester) async {
    final service = _FakeTimeEntryService();
    final location = _FakeLocationService()
      ..fix = const PositionFix(lat: 45.0400, lng: -73.0000);
    await _pumpButton(tester,
        open: _openAtA(), service: service, location: location);
    expect(find.text('Clock out'), findsOneWidget);
    expect(find.textContaining('Switch to'), findsNothing);
    await tester.tap(find.text('Clock out'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(service.clockOuts, hasLength(1));
    expect(service.clockOuts.single.id, 'e1');
    expect(service.clockIns, isEmpty);
  });

  testWidgets('outside every fence still shows Clock out and clocks out',
      (tester) async {
    final service = _FakeTimeEntryService();
    final location = _FakeLocationService()
      ..fix = const PositionFix(lat: 46.5000, lng: -74.5000);
    await _pumpButton(tester,
        open: _openAtA(), service: service, location: location);
    expect(find.text('Clock out'), findsOneWidget);
    expect(find.textContaining('Switch to'), findsNothing);
    await tester.tap(find.text('Clock out'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(service.clockOuts, hasLength(1));
    expect(service.clockIns, isEmpty);
  });

  testWidgets('no location consent: no switch offered, plain clock-out',
      (tester) async {
    // Consent "Not now": the button never takes a fix, so no
    // candidate is ever computed — even inside B's fence.
    SharedPreferences.setMockInitialValues(
        {'location_consent_given': false});
    final service = _FakeTimeEntryService();
    final location = _FakeLocationService()
      ..fix = const PositionFix(lat: 45.0500, lng: -73.0100);
    await _pumpButton(tester,
        open: _openAtA(), service: service, location: location);
    expect(find.text('Clock out'), findsOneWidget);
    expect(find.textContaining('Switch to'), findsNothing);
    await tester.tap(find.text('Clock out'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(service.clockOuts, hasLength(1));
    expect(service.clockIns, isEmpty);
  });

  testWidgets('not clocked in still shows Clock in', (tester) async {
    final service = _FakeTimeEntryService();
    final location = _FakeLocationService()
      ..fix = const PositionFix(lat: 45.0500, lng: -73.0100);
    await _pumpButton(tester,
        open: null, service: service, location: location);
    expect(find.text('Clock in'), findsOneWidget);
    expect(find.textContaining('Switch to'), findsNothing);
  });
}
