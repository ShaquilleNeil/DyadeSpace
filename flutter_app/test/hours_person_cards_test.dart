import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/app_user.dart';
import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/models/task_item.dart';
import 'package:dyadespace/models/time_entry.dart';
import 'package:dyadespace/providers/auth_provider.dart';
import 'package:dyadespace/providers/locale_provider.dart';
import 'package:dyadespace/providers/sites_provider.dart';
import 'package:dyadespace/providers/tasks_provider.dart';
import 'package:dyadespace/providers/time_entries_provider.dart';
import 'package:dyadespace/screens/manager/hours_screen.dart';
import 'package:dyadespace/screens/web/web_hours_screen.dart';
import 'package:dyadespace/screens/worker_profile_screen.dart';
import 'package:dyadespace/services/hours_csv.dart';
import 'package:dyadespace/theme/app_theme.dart';
import 'package:dyadespace/utils/week_hours.dart';

/// Hours person cards (Nov 15, 2026): the phone Hours screen
/// is one card per person (Team-style) instead of an inline
/// entry list, tapping a card opens the profile on the
/// Clock-in tab, and hours fall back to the clock-in/out
/// times when the server value is missing. Pumped with the
/// REAL app theme and mocked providers — no Firebase, no
/// network.
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

const _worker = AppUser(
  id: 'wanda',
  name: 'Wanda',
  email: 'wanda@example.com',
  role: UserRole.worker,
);

const _site = Site(
  id: 'site1',
  name: 'Lakeside',
  address: '30 Boul. Montarville',
  lat: 45.6,
  lng: -73.4,
);

String _today() => DateFormat('yyyy-MM-dd').format(DateTime.now());

TimeEntry? _openFor(List<TimeEntry> entries, String uid) {
  for (final e in entries) {
    if (e.userId == uid && e.isOpen) return e;
  }
  return null;
}

Future<void> _pumpHours(
  WidgetTester tester,
  List<TimeEntry> entries,
) async {
  await initializeDateFormatting('en');
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(const AppStrings('en')),
        currentUserProvider.overrideWith((ref) => Stream.value(_me)),
        allUsersProvider.overrideWith(
            (ref) => Stream.value(<AppUser>[_me, _rolando])),
        allTimeEntriesProvider
            .overrideWith((ref) => Stream.value(entries)),
        siteByIdProvider.overrideWithValue(<String, Site>{'site1': _site}),
        sitesProvider.overrideWith((ref) => Stream.value(<Site>[_site])),
        // The profile opened by tapping a card watches these.
        entriesForUserProvider.overrideWith((ref, uid) => Stream.value(
            entries.where((e) => e.userId == uid).toList())),
        openEntryForUserProvider
            .overrideWith((ref, uid) => Stream.value(_openFor(entries, uid))),
        allTasksProvider.overrideWith((ref) => Stream.value(<TaskItem>[
              TaskItem(
                id: 't1',
                title: 'Paint the fence',
                siteId: 'site1',
                assigneeIds: ['rolando'],
                createdBy: 'me',
                dueDate: DateTime.now(),
              ),
            ])),
      ],
      child: MaterialApp(
        theme: buildAppDarkTheme(),
        home: const HoursScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

Future<void> _pumpProfile(
  WidgetTester tester, {
  required AppUser user,
  required AppUser me,
  required List<TimeEntry> entries,
}) async {
  await initializeDateFormatting('en');
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(const AppStrings('en')),
        currentUserProvider.overrideWith((ref) => Stream.value(me)),
        allUsersProvider.overrideWith((ref) => Stream.value(<AppUser>[me])),
        entriesForUserProvider.overrideWith(
            (ref, uid) => Stream.value(entries)),
        openEntryForUserProvider.overrideWith(
            (ref, uid) => Stream.value(_openFor(entries, uid))),
        allTasksProvider.overrideWith((ref) => Stream.value(<TaskItem>[])),
        siteByIdProvider.overrideWithValue(<String, Site>{'site1': _site}),
      ],
      child: MaterialApp(
        theme: buildAppDarkTheme(),
        home: WorkerProfileScreen(user: user),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  // The app theme sets Manrope via GoogleFonts, which cannot
  // fetch in widget tests — text falls back to Ahem, whose
  // glyphs are 1em wide, so every line looks truncated. Load a
  // real sans (Roboto from the Flutter SDK cache) under the
  // family names google_fonts resolves to: each weight gets
  // its own family (Manrope_regular, Manrope_600, ...), with
  // plain 'Manrope' only as a fallback. The metrics are close
  // enough to Manrope for fit checks.
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

  testWidgets(
      'person card: null-hours closed entry counts toward the total',
      (tester) async {
    // Anchored to Toronto midday (10:00–12:00 Toronto today):
    // wholly inside one Toronto day, so the total is exactly
    // 2 h whatever time of day the test runs (a window
    // relative to device-local now could straddle Toronto
    // midnight and split).
    final todayToronto = torontoNow();
    final dayStartUtc = torontoMidnightUtc(DateTime(
        todayToronto.year, todayToronto.month, todayToronto.day));
    final entries = <TimeEntry>[
      // Sam: closed 2 h, no server hours yet.
      TimeEntry(
        id: 'e1',
        userId: 'rolando',
        userName: 'Sam',
        siteId: 'site1',
        siteName: 'Lakeside',
        date: torontoDateStr(dayStartUtc.add(const Duration(hours: 10))),
        clockInAt: dayStartUtc.add(const Duration(hours: 10)),
        clockOutAt: dayStartUtc.add(const Duration(hours: 12)),
      ),
      // Alex: closed 1.5 h, server hours present.
      TimeEntry(
        id: 'e2',
        userId: 'me',
        userName: 'Alex Morgan',
        siteId: 'site1',
        siteName: 'Lakeside',
        date: torontoDateStr(dayStartUtc.add(const Duration(hours: 9))),
        clockInAt: dayStartUtc.add(const Duration(hours: 9)),
        clockOutAt: dayStartUtc.add(const Duration(hours: 10, minutes: 30)),
        hours: 1.5,
      ),
    ];
    await _pumpHours(tester, entries);
    expect(tester.takeException(), isNull);
    expect(find.text('Sam'), findsOneWidget);
    // The fallback: 2 h from the times, not "—" and not 0.
    expect(find.text('2 h'), findsOneWidget);
    expect(find.text('1 h 30 min'), findsOneWidget);
    expect(find.text('Total hours'), findsNWidgets(2));
    expect(find.text('1 entry'), findsNWidgets(2));
    // No entry tiles on the Hours screen any more.
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  testWidgets('person card: open entry counts its live time in the total',
      (tester) async {
    final now = DateTime.now();
    // The closed entry is anchored to Toronto midday so its
    // 2 h can never split across Toronto midnight; the open
    // entry stays relative to now (its live time is real).
    final todayToronto = torontoNow();
    final dayStartUtc = torontoMidnightUtc(DateTime(
        todayToronto.year, todayToronto.month, todayToronto.day));
    final entries = <TimeEntry>[
      TimeEntry(
        id: 'e1',
        userId: 'rolando',
        userName: 'Sam',
        siteId: 'site1',
        siteName: 'Lakeside',
        date: torontoDateStr(dayStartUtc.add(const Duration(hours: 10))),
        clockInAt: dayStartUtc.add(const Duration(hours: 10)),
        clockOutAt: dayStartUtc.add(const Duration(hours: 12)),
      ),
      TimeEntry(
        id: 'e2',
        userId: 'rolando',
        userName: 'Sam',
        siteId: 'site1',
        siteName: 'Lakeside',
        date: _today(),
        clockInAt: now.subtract(const Duration(minutes: 65)),
      ),
    ];
    await _pumpHours(tester, entries);
    expect(tester.takeException(), isNull);
    // Total counts the closed entry PLUS the open one's live
    // time (2 h + ~1 h 5 min), the same rule as the web Hours
    // screen and week_hours.dart — so the screens agree. The
    // exact total depends on when the open entry's live time
    // crosses Toronto midnight, so assert it is no longer
    // just the closed 2 h (and the live status line shows).
    expect(find.text('2 h'), findsNothing);
    // The card's second line is the short live status —
    // "Clocked in · 1 h 5 min" — the site and the clock-in
    // time live on the profile status card instead.
    expect(find.textContaining('Clocked in ·'), findsOneWidget);
  });

  testWidgets('person card: live status line fits in full at 390px',
      (tester) async {
    final now = DateTime.now();
    final entries = <TimeEntry>[
      TimeEntry(
        id: 'e1',
        userId: 'rolando',
        userName: 'Sam',
        siteId: 'site1',
        siteName: 'Lakeside',
        date: _today(),
        clockInAt: now.subtract(const Duration(hours: 2)),
        clockOutAt: now,
      ),
      // Open 65 minutes ago at Lakeside — the old line
      // ("Clocked in at Lakeside · 07:12 · 1 h 5 min")
      // was cut off mid-time at this width.
      TimeEntry(
        id: 'e2',
        userId: 'rolando',
        userName: 'Sam',
        siteId: 'site1',
        siteName: 'Lakeside',
        date: _today(),
        clockInAt: now.subtract(const Duration(minutes: 65)),
      ),
    ];
    await _pumpHours(tester, entries);
    expect(tester.takeException(), isNull);
    // The short line renders in full — the paragraph does not
    // exceed its one line (find.text alone can't tell: the
    // widget's data is the full string even when truncated).
    final status = find.textContaining('Clocked in ·');
    expect(status, findsOneWidget);
    expect(tester.renderObject<RenderParagraph>(status).didExceedMaxLines,
        isFalse);
  });

  testWidgets('profile history: long site names show in full at 390px',
      (tester) async {
    final verified = TimeEntry(
      id: 'e1',
      userId: 'rolando',
      userName: 'Sam',
      siteId: 'site1',
      siteName: 'Harborview 1200',
      date: '2026-11-14',
      clockInAt: DateTime(2026, 11, 14, 18, 20),
      clockOutAt: DateTime(2026, 11, 14, 20, 45),
    );
    final flagged = TimeEntry(
      id: 'e2',
      userId: 'rolando',
      userName: 'Sam',
      siteId: 'site1',
      siteName: 'Lakeside',
      date: '2026-11-13',
      clockInAt: DateTime(2026, 11, 13, 9, 0),
      clockOutAt: DateTime(2026, 11, 13, 9, 45),
      flagged: true,
      flagReason: 'outside-radius',
    );
    await _pumpProfile(tester,
        user: _rolando, me: _me, entries: [verified, flagged]);
    await tester.tap(find.text('Clock in'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Both titles render in full — no "Boucher…" / "Fri N…".
    for (final title in [
      'Sat Nov 14 · Harborview 1200',
      'Fri Nov 13 · Lakeside',
    ]) {
      expect(find.text(title), findsOneWidget);
      expect(
          tester.renderObject<RenderParagraph>(find.text(title))
              .didExceedMaxLines,
          isFalse);
    }
    // The flagged pill is just "Flagged" now — the reason
    // shows on the map screen instead.
    expect(find.text('Flagged'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget);
  });

  testWidgets('tap a person card opens the profile on the Clock-in tab',
      (tester) async {
    final now = DateTime.now();
    final entries = <TimeEntry>[
      TimeEntry(
        id: 'e1',
        userId: 'rolando',
        userName: 'Sam',
        siteId: 'site1',
        siteName: 'Lakeside',
        date: _today(),
        clockInAt: now.subtract(const Duration(hours: 2)),
        clockOutAt: now,
      ),
      TimeEntry(
        id: 'e2',
        userId: 'rolando',
        userName: 'Sam',
        siteId: 'site1',
        siteName: 'Lakeside',
        date: _today(),
        clockInAt: now.subtract(const Duration(minutes: 65)),
      ),
    ];
    await _pumpHours(tester, entries);
    await tester.tap(find.text('Sam'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Clock-in tab content: the history entries (status card +
    // two history tiles all name the site).
    expect(find.textContaining('Lakeside'), findsWidgets);
    // The Tasks tab is not the one showing: Sam's open
    // task is not visible.
    expect(find.text('Paint the fence'), findsNothing);
    // Admin viewer: an edit button on each history row.
    expect(find.byIcon(Icons.edit_outlined), findsNWidgets(2));
  });

  testWidgets('profile history: worker viewing own profile sees no edit button',
      (tester) async {
    final closed = TimeEntry(
      id: 'e1',
      userId: 'wanda',
      userName: 'Wanda',
      siteId: 'site1',
      siteName: 'Lakeside',
      date: '2026-11-15',
      clockInAt: DateTime(2026, 11, 15, 8, 0),
      clockOutAt: DateTime(2026, 11, 15, 10, 0),
    );
    await _pumpProfile(tester,
        user: _worker, me: _worker, entries: [closed]);
    await tester.tap(find.text('Clock in'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // The history row shows the computed time, not "—".
    expect(find.textContaining('08:00 – 10:00 · 2 h'), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing);
  });

  test('buildHoursCsv: null-hours closed entry uses its computed time', () {
    final closed = TimeEntry(
      id: 'e1',
      userId: 'rolando',
      userName: 'Sam',
      siteId: 'site1',
      siteName: 'Lakeside',
      date: '2026-11-15',
      clockInAt: DateTime(2026, 11, 15, 8, 0),
      clockOutAt: DateTime(2026, 11, 15, 10, 0),
    );
    final open = TimeEntry(
      id: 'e2',
      userId: 'rolando',
      userName: 'Sam',
      siteId: 'site1',
      siteName: 'Lakeside',
      date: '2026-11-15',
      clockInAt: DateTime(2026, 11, 15, 11, 0),
    );
    // Totals are keyed by userId (two workers sharing a name
    // never merge); the CSV prints the display name.
    final csv = buildHoursCsv([closed, open], {'rolando': 2.0});
    expect(
        csv,
        contains(
            'Sam,2026-11-15,Lakeside,08:00,10:00,2.00,Verified'));
    // An open entry stays blank — its hours are not final yet.
    expect(csv, contains('Sam,2026-11-15,Lakeside,11:00,,,Verified'));
    expect(csv, contains('Sam,2.00'));
  });

  test('buildHoursCsv: two workers sharing a name get separate totals', () {
    TimeEntry worker(String id, double hours) => TimeEntry(
          id: 'e-$id',
          userId: id,
          userName: 'Alex',
          siteId: 'site1',
          siteName: 'Lakeside',
          date: '2026-11-15',
          clockInAt: DateTime(2026, 11, 15, 8, 0),
          clockOutAt: DateTime(2026, 11, 15, 10, 0),
          hours: hours,
        );
    final csv = buildHoursCsv(
        [worker('u1', 2), worker('u2', 3)], {'u1': 2.0, 'u2': 3.0});
    expect(csv, contains('Alex,2.00'));
    expect(csv, contains('Alex,3.00'));
  });

  testWidgets('web hours: null-hours closed entry counts in the week table',
      (tester) async {
    // 10:00–12:00 Toronto today: wholly inside one Toronto
    // day, so the day cell, the week total and the entry row
    // all read the computed 2 h (a window relative to
    // device-local now could straddle Toronto midnight and
    // split across days).
    final todayToronto = torontoNow();
    final dayStartUtc = torontoMidnightUtc(DateTime(
        todayToronto.year, todayToronto.month, todayToronto.day));
    final clockInAt = dayStartUtc.add(const Duration(hours: 10));
    final entry = TimeEntry(
      id: 'e1',
      userId: 'rolando',
      userName: 'Sam',
      siteId: 'site1',
      siteName: 'Lakeside',
      date: torontoDateStr(clockInAt),
      clockInAt: clockInAt,
      clockOutAt: dayStartUtc.add(const Duration(hours: 12)),
    );
    await initializeDateFormatting('en');
    tester.view.physicalSize = const Size(1913, 1065);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(const AppStrings('en')),
          currentUserProvider.overrideWith((ref) => Stream.value(_me)),
          allTimeEntriesProvider
              .overrideWith((ref) => Stream.value(<TimeEntry>[entry])),
          sitesProvider.overrideWith((ref) => Stream.value(<Site>[_site])),
        ],
        child: MaterialApp(
          theme: buildAppDarkTheme(),
          home: const Scaffold(body: WebHoursScreen()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(tester.takeException(), isNull);
    // Day cell + week total + entry row all show the computed 2 h.
    expect(find.text('2 h'), findsNWidgets(3));
  });
}
