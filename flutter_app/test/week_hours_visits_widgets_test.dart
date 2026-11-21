import 'dart:io' show File, Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/site_visit.dart';
import 'package:dyadespace/models/time_entry.dart';
import 'package:dyadespace/theme/app_theme.dart';
import 'package:dyadespace/widgets/site_visits_list.dart';
import 'package:dyadespace/widgets/week_hours_header.dart';

/// Widget tests for the week-hours header and the visits list:
/// the header totals the current week (closed hours + live
/// time so far, ticking every minute while clocked in), and
/// the list renders each visit with its times and duration.
/// Pumped with the real app theme — no Firebase, no network.
void main() {
  const strings = AppStrings('en');

  setUpAll(() async {
    await initializeDateFormatting('en');
    // Same font setup as clock_in_site_switch_test.dart: widget
    // tests fall back to Ahem unless a real sans is loaded.
    final path =
        '${Platform.environment['HOME']}/flutter/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf';
    final bytes = await File(path).readAsBytes();
    final data = ByteData.view(bytes.buffer, bytes.offsetInBytes);
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

  String dateStr(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  TimeEntry entry({
    required String id,
    required DateTime clockInAt,
    DateTime? clockOutAt,
    double? hours,
  }) =>
      TimeEntry(
        id: id,
        userId: 'u1',
        userName: 'Worker',
        siteId: 'site-1',
        siteName: 'Maple Court',
        date: dateStr(clockInAt),
        clockInAt: clockInAt,
        clockOutAt: clockOutAt,
        hours: hours,
      );

  Future<void> pumpHeader(
    WidgetTester tester,
    List<TimeEntry> entries,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppDarkTheme(),
        home: Scaffold(
          body: WeekHoursHeader(entries: entries, strings: strings),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('header totals closed entries in the current week',
      (tester) async {
    final now = DateTime.now();
    await pumpHeader(tester, [
      entry(
        id: 'a',
        clockInAt: DateTime(now.year, now.month, now.day, 7),
        clockOutAt: DateTime(now.year, now.month, now.day, 9),
        hours: 2,
      ),
      entry(
        id: 'last-week',
        clockInAt: now.subtract(const Duration(days: 10, hours: 1)),
        clockOutAt: now.subtract(const Duration(days: 10)),
        hours: 8,
      ),
    ]);
    expect(find.textContaining('This week: 2 h'), findsOneWidget);
  });

  testWidgets('header shows live time for an open entry and rebuilds',
      (tester) async {
    final now = DateTime.now();
    await pumpHeader(tester, [
      entry(
        id: 'open',
        clockInAt: now.subtract(const Duration(minutes: 61)),
      ),
    ]);
    expect(find.textContaining('This week: 1 h 1 min'), findsOneWidget);
    // The 60-second timer rebuilds the header while an entry
    // is open. DateTime.now() is real time in widget tests
    // (tester.pump does not move it), so the value cannot
    // grow inside this test — the growth itself is covered by
    // week_hours_test.dart. This asserts the rebuild runs
    // without error and the live total stays on screen.
    await tester.pump(const Duration(minutes: 2));
    expect(find.textContaining('This week: 1 h 1 min'), findsOneWidget);
  });

  testWidgets('header shows 0 min with no entries', (tester) async {
    await pumpHeader(tester, []);
    expect(find.textContaining('This week: 0 min'), findsOneWidget);
  });

  Future<void> pumpVisits(
    WidgetTester tester,
    List<SiteVisit> visits,
    DateTime? entryClockOutAt,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppDarkTheme(),
        home: Scaffold(
          body: SiteVisitsList(
            visits: visits,
            entryClockOutAt: entryClockOutAt,
            strings: strings,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('closed visit shows times and duration', (tester) async {
    await pumpVisits(
        tester,
        [
          SiteVisit(
            id: 'v1',
            siteId: 'a',
            siteName: 'St Antoine',
            arrivedAt: DateTime(2026, 11, 16, 9, 12),
            leftAt: DateTime(2026, 11, 16, 11, 40),
            durationMinutes: 148,
          ),
        ],
        DateTime(2026, 11, 16, 17, 0));
    expect(find.text('St Antoine'), findsOneWidget);
    expect(find.textContaining('09:12 – 11:40'), findsOneWidget);
    expect(find.textContaining('2 h 28 min'), findsOneWidget);
  });

  testWidgets('open visit shows "Here now"', (tester) async {
    await pumpVisits(
        tester,
        [
          SiteVisit(
            id: 'v1',
            siteId: 'a',
            siteName: 'Harborview 1200',
            arrivedAt: DateTime(2026, 11, 16, 13, 5),
          ),
        ],
        null);
    expect(find.text('Harborview 1200'), findsOneWidget);
    expect(find.textContaining('Here now'), findsOneWidget);
    expect(find.textContaining('Since 13:05'), findsOneWidget);
  });

  testWidgets('open visit on a closed entry ends at clock-out', (tester) async {
    await pumpVisits(
        tester,
        [
          SiteVisit(
            id: 'v1',
            siteId: 'a',
            siteName: 'St Antoine',
            arrivedAt: DateTime(2026, 11, 16, 9, 12),
          ),
        ],
        DateTime(2026, 11, 16, 23, 59));
    expect(find.textContaining('09:12 – 23:59'), findsOneWidget);
    expect(find.textContaining('Here now'), findsNothing);
  });
}
