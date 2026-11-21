import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dyadespace/models/time_entry.dart';
import 'package:dyadespace/theme/app_theme.dart';
import 'package:dyadespace/utils/date_format.dart';
import 'package:dyadespace/widgets/app_date_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Area H audit fixes: malformed docs must fail visibly (never
/// render invented data), the System theme option must
/// round-trip through storage, and display dates must follow
/// the current language.
void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
    await initializeDateFormatting('fr');
    await initializeDateFormatting('es');
  });

  group('TimeEntry malformed docs', () {
    test('fromMap throws when clockInAt is missing', () {
      expect(() => TimeEntry.fromMap('e1', {}), throwsFormatException);
      expect(
          () => TimeEntry.fromMap('e1', {'clockInAt': 'not-a-timestamp'}),
          throwsFormatException);
    });

    test('tryFromMap returns null for a malformed doc', () {
      expect(TimeEntry.tryFromMap('e1', {}), isNull);
    });

    test('fromMap/tryFromMap keep a well-formed doc', () {
      final at = DateTime(2026, 11, 20, 8, 0);
      final entry = TimeEntry.fromMap('e2', {
        'userId': 'u1',
        'userName': 'Chris',
        'clockInAt': Timestamp.fromDate(at),
      });
      expect(entry.clockInAt, at);
      expect(TimeEntry.tryFromMap('e2', {
        'clockInAt': Timestamp.fromDate(at),
      }),
          isNotNull);
    });
  });

  group('System theme option', () {
    test('system round-trips through the stored value', () {
      expect(themeModeStorageValue(ThemeMode.system), 'system');
      expect(themeModeFromStorage('system'), ThemeMode.system);
      expect(themeModeStorageValue(ThemeMode.light), 'light');
      expect(themeModeFromStorage('light'), ThemeMode.light);
      expect(themeModeStorageValue(ThemeMode.dark), 'dark');
      expect(themeModeFromStorage('dark'), ThemeMode.dark);
    });

    test('unknown or missing stored value falls back to dark', () {
      expect(themeModeFromStorage(null), ThemeMode.dark);
      expect(themeModeFromStorage('sepia'), ThemeMode.dark);
    });
  });

  group('Localized display dates', () {
    test('French weekday/month names render in French, not English', () {
      final day = DateTime(2026, 11, 17); // a Tuesday in November
      final fr = formatDisplayDate(day, 'fr');
      expect(fr.toLowerCase(), contains('nov'));
      expect(fr.toLowerCase(), isNot(contains('november')));
      expect(formatDisplayDate(day, 'en'), contains('Nov'));
      expect(formatWeekdayShort(day, 'fr'), isNot('Tue'));
    });

    test('unknown locale falls back to English instead of throwing', () {
      expect(formatDisplayDate(DateTime(2026, 11, 17), 'xx'),
          contains('Nov'));
    });
  });

  group('AppDateField controller', () {
    Future<void> pumpField(WidgetTester tester, DateTime? value) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AppDateField(
              label: 'Due', value: value, onPick: (_) {}),
        ),
      ));
    }

    testWidgets('shows the value and updates when it changes',
        (tester) async {
      await pumpField(tester, DateTime(2026, 11, 17));
      expect(find.textContaining('Nov 17, 2026'), findsOneWidget);
      // Same widget, new value: the once-created controller must
      // pick it up (didUpdateWidget), not keep the stale text.
      await pumpField(tester, DateTime(2026, 11, 18));
      expect(find.textContaining('Nov 18, 2026'), findsOneWidget);
      expect(find.textContaining('Nov 17, 2026'), findsNothing);
      // Unmounting must dispose the controller without error.
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    });
  });
}
