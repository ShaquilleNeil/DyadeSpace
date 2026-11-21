import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/app_user.dart';
import 'package:dyadespace/models/time_entry.dart';
import 'package:dyadespace/providers/locale_provider.dart';
import 'package:dyadespace/providers/time_entries_provider.dart';
import 'package:dyadespace/theme/app_tokens.dart';
import 'package:dyadespace/widgets/member_tile.dart';

/// Regression tests for the Team clock-in line:
/// - `todayOpenEntries` keeps only open entries clocked in
///   today (a stale open entry from an earlier day does not
///   count as clocked in), newest open entry wins per user.
/// - `MemberTile` renders the status line green when active,
///   muted otherwise, and hides it when null.
TimeEntry _entry({
  required String id,
  required String userId,
  required String date,
  required DateTime clockInAt,
  DateTime? clockOutAt,
  String siteName = 'Maple Court',
}) {
  return TimeEntry(
    id: id,
    userId: userId,
    userName: userId,
    siteId: 'site-$siteName',
    siteName: siteName,
    date: date,
    clockInAt: clockInAt,
    clockOutAt: clockOutAt,
  );
}

void main() {
  final now = DateTime(2026, 11, 15, 10, 0);

  test('open entry today counts as clocked in', () {
    final out = todayOpenEntries([
      _entry(
        id: 'e1',
        userId: 'u1',
        date: '2026-11-15',
        clockInAt: DateTime(2026, 11, 15, 8, 4),
      ),
    ], now);
    expect(out['u1']?.id, 'e1');
  });

  test('open entry from yesterday is stale, not clocked in', () {
    final out = todayOpenEntries([
      _entry(
        id: 'e2',
        userId: 'u2',
        date: '2026-11-14',
        clockInAt: DateTime(2026, 11, 14, 8, 0),
      ),
    ], now);
    expect(out, isEmpty);
  });

  test('closed entry today does not count', () {
    final out = todayOpenEntries([
      _entry(
        id: 'e3',
        userId: 'u3',
        date: '2026-11-15',
        clockInAt: DateTime(2026, 11, 15, 7, 30),
        clockOutAt: DateTime(2026, 11, 15, 9, 0),
      ),
    ], now);
    expect(out, isEmpty);
  });

  test('newest open entry wins per user', () {
    final out = todayOpenEntries([
      _entry(
        id: 'e4-new',
        userId: 'u4',
        date: '2026-11-15',
        clockInAt: DateTime(2026, 11, 15, 9, 0),
        siteName: 'Maple Court',
      ),
      _entry(
        id: 'e4-old',
        userId: 'u4',
        date: '2026-11-15',
        clockInAt: DateTime(2026, 11, 15, 7, 0),
        siteName: 'Harborview 1200',
      ),
    ], now);
    expect(out['u4']?.id, 'e4-new');
  });

  test('empty list gives an empty map', () {
    expect(todayOpenEntries([], now), isEmpty);
  });

  Future<void> pumpTile(
    WidgetTester tester, {
    String? statusText,
    bool statusActive = false,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(const AppStrings('en')),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: MemberTile(
              title: 'Alex Morgan',
              subtitle: 'alex@example.com',
              role: UserRole.worker,
              statusText: statusText,
              statusActive: statusActive,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('active status line renders green', (tester) async {
    const text = 'Clocked in at Maple Court · 08:04';
    await pumpTile(tester, statusText: text, statusActive: true);
    final found = find.text(text);
    expect(found, findsOneWidget);
    final style = tester.widget<Text>(found).style;
    final tokens = AppTokens.of(tester.element(found));
    expect(style?.color, tokens.statusDone);
  });

  testWidgets('inactive status line renders muted', (tester) async {
    const text = 'Not clocked in yet.';
    await pumpTile(tester, statusText: text, statusActive: false);
    final found = find.text(text);
    expect(found, findsOneWidget);
    final style = tester.widget<Text>(found).style;
    final tokens = AppTokens.of(tester.element(found));
    expect(style?.color, tokens.textTertiary);
  });

  testWidgets('no status line when statusText is null', (tester) async {
    await pumpTile(tester);
    expect(find.text('Clocked in at Maple Court · 08:04'), findsNothing);
    expect(find.text('Not clocked in yet.'), findsNothing);
  });
}
