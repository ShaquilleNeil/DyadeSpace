import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/providers/locale_provider.dart';
import 'package:dyadespace/widgets/site_header.dart';

/// Regression test for the Board site rows not opening the site
/// page: on the Today filter (the Board default) the Board passed
/// `onOpenSite: null`, so tapping a site name did nothing. The
/// fix (board_screen.dart) passes the open-site callback on every
/// filter. These tests guard the widget contract the fix relies
/// on: the name tap fires onOpenSite, the chevron tap fires
/// onToggleCollapse, and a header without callbacks is inert.
const _site = Site(
  id: 'home',
  name: 'Home',
  address: '10490 avenue curotte',
);

Future<void> _pumpHeader(
  WidgetTester tester, {
  VoidCallback? onOpenSite,
  VoidCallback? onToggleCollapse,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(const AppStrings('en')),
      ],
      child: MaterialApp(
        home: Scaffold(
          body: SiteHeader(
            site: _site,
            count: 1,
            onOpenSite: onOpenSite,
            onToggleCollapse: onToggleCollapse,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('tapping the site name fires onOpenSite', (tester) async {
    var opened = false;
    await _pumpHeader(tester, onOpenSite: () => opened = true);
    await tester.tap(find.text('Home'));
    expect(opened, isTrue);
  });

  testWidgets('tapping the chevron fires onToggleCollapse',
      (tester) async {
    var toggled = false;
    await _pumpHeader(
      tester,
      onOpenSite: () {},
      onToggleCollapse: () => toggled = true,
    );
    await tester.tap(find.byIcon(Icons.chevron_right));
    expect(toggled, isTrue);
  });

  testWidgets('header without callbacks does nothing on tap',
      (tester) async {
    await _pumpHeader(tester);
    await tester.tap(find.text('Home'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
