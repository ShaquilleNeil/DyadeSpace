import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for the profile/account sheet overflow.
///
/// The sheet's content is ~456px tall (avatar, name, email, role,
/// Settings row, two segmented controls, Sign out, padding). A
/// default showModalBottomSheet caps the sheet at 9/16 of the
/// screen height, so on his phone the content overflowed by 27px
/// and the Sign out button was cut off. The fix (home_shell.dart)
/// is `isScrollControlled: true` + a SingleChildScrollView, the
/// same pattern as the bulk-invite sheet.
Widget _sheetContent({bool withFix = false}) {
  final column = Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: const [
      SizedBox(height: 56), // avatar
      SizedBox(height: 12),
      SizedBox(height: 24), // name
      SizedBox(height: 4),
      SizedBox(height: 20), // email
      SizedBox(height: 4),
      SizedBox(height: 16), // role
      SizedBox(height: 20),
      SizedBox(height: 56), // Settings row
      SizedBox(height: 12),
      SizedBox(height: 40), // language segmented
      SizedBox(height: 12),
      SizedBox(height: 40), // theme segmented
      SizedBox(height: 12),
      SizedBox(height: 48, child: Text('Sign out')), // sign-out button
    ],
  );
  final padded = Padding(
    padding: const EdgeInsets.all(20),
    child: withFix ? SingleChildScrollView(child: column) : column,
  );
  return SafeArea(child: padded);
}

Future<void> _openSheet(WidgetTester tester, {required bool withFix}) async {
  // Short viewport (360x640 logical): the default sheet cap is
  // 9/16 of 640 = 360px, well under the ~456px content.
  tester.view.physicalSize = const Size(720, 1280);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: withFix,
                useSafeArea: withFix,
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
  testWidgets('unfixed sheet overflows at a short viewport',
      (tester) async {
    await _openSheet(tester, withFix: false);
    expect(tester.takeException(), isNotNull);
  });

  testWidgets('scroll-controlled sheet fits and shows Sign out',
      (tester) async {
    await _openSheet(tester, withFix: true);
    expect(tester.takeException(), isNull);
    expect(find.text('Sign out'), findsOneWidget);
  });
}
