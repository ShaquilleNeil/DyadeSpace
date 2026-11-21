import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for the bulk-invite blank sheet.
///
/// The app theme gives every FilledButton an infinite min width
/// (`Size.fromHeight(52)`). Inside this bottom sheet's Row the
/// button gets unbounded constraints, so layout throws
/// "BoxConstraints forces an infinite width" and the sheet
/// renders blank. The fix is a finite minimumSize on this one
/// button (see bulk_invite_sheet.dart).
Widget _sheetContent({bool withFix = false}) {
  return SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Bulk invite'),
            const SizedBox(height: 12),
            Row(
              children: [
                TextButton(onPressed: () {}, child: const Text('Cancel')),
                const Spacer(),
                FilledButton(
                  style: withFix
                      ? FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        )
                      : null,
                  onPressed: () {},
                  child: const Text('Create invites'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

ThemeData _theme() => ThemeData(
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
        ),
      ),
    );

Future<void> _openSheet(WidgetTester tester, {required bool withFix}) async {
  await tester.pumpWidget(MaterialApp(
    theme: _theme(),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                builder: (ctx) => _sheetContent(withFix: withFix),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('unfixed button throws the infinite-width error',
      (tester) async {
    await _openSheet(tester, withFix: false);
    // The raw output shows the exact "BoxConstraints forces an
    // infinite width" error; takeException() aggregates the
    // whole cascade into one summary object, so assert only
    // that the unfixed layout throws at all.
    expect(tester.takeException(), isNotNull);
  });

  testWidgets('style override fixes the sheet layout', (tester) async {
    await _openSheet(tester, withFix: true);
    expect(tester.takeException(), isNull);
    expect(find.text('Create invites'), findsOneWidget);
  });
}
