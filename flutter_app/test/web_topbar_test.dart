import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/app_user.dart';
import 'package:dyadespace/models/delivery_run.dart';
import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/models/task_item.dart';
import 'package:dyadespace/models/time_entry.dart';
import 'package:dyadespace/providers/auth_provider.dart';
import 'package:dyadespace/providers/locale_provider.dart';
import 'package:dyadespace/providers/material_requests_provider.dart';
import 'package:dyadespace/providers/runs_provider.dart';
import 'package:dyadespace/providers/sites_provider.dart';
import 'package:dyadespace/providers/tasks_provider.dart';
import 'package:dyadespace/providers/time_entries_provider.dart';
import 'package:dyadespace/screens/web/control_center_shell.dart';
import 'package:dyadespace/theme/app_theme.dart';

/// Regression test for the live-site topbar (Nov 15, 2026):
/// on a wide desktop the section title was invisible, the date
/// rendered one letter per line in a ~10px strip at the content's
/// left edge, and the "+ New task" button was nowhere — so no new
/// task could be created from the site.
/// Root cause (measured in a real Chrome/CanvasKit render, not
/// from the code): the app theme gives every FilledButton
/// `minimumSize: Size.fromHeight(52)` = Size(infinity, 52)
/// (app_theme.dart). The topbar's "+ New task" FilledButton.icon
/// therefore took an INFINITE width, starving the Expanded title
/// column to 0px (title ellipsised to nothing, date wrapped to
/// one letter per line, ~204px tall) and clipping the button
/// itself off the Row (label at NaN). The topbar Container and
/// Row were full-width the whole time — the bug is the button's
/// infinite minimum, not the content Column. Fix: the topbar
/// button overrides minimumSize to Size(0, 52), same as the
/// bulk-invite sheet fix. NOTE: the test must pump with the REAL
/// app theme — the default Material theme has a finite button
/// minimum, so without it this test passes even with the bug.
const _me = AppUser(
  id: 'me',
  name: 'Alex Morgan',
  email: 'alex@example.com',
  role: UserRole.admin,
);

Future<void> _pumpShell(WidgetTester tester, Size size) async {
  // The topbar formats the date with intl; the test env needs
  // the locale data loaded first (the real app does this at
  // startup).
  await initializeDateFormatting('en');
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(const AppStrings('en')),
        currentUserProvider.overrideWith((ref) => Stream.value(_me)),
        allUsersProvider.overrideWith((ref) => Stream.value(<AppUser>[])),
        openMaterialRequestsCountProvider.overrideWithValue(0),
        allTasksProvider.overrideWith((ref) => Stream.value(<TaskItem>[])),
        allTimeEntriesProvider
            .overrideWith((ref) => Stream.value(<TimeEntry>[])),
        allRunsProvider
            .overrideWith((ref) => Stream.value(<DeliveryRun>[])),
        siteByIdProvider.overrideWithValue(<String, Site>{}),
      ],
      // The REAL app theme: its FilledButton minimumSize is what
      // broke the topbar (see the file comment). Pumping with the
      // default theme hides the bug.
      child: MaterialApp(
        theme: buildAppDarkTheme(),
        home: const ControlCenterShell(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

String _todayDate() =>
    DateFormat('EEEE, MMM d', 'en').format(DateTime.now());

void main() {
  testWidgets('desktop 1913px: title, date and New task button visible',
      (tester) async {
    await _pumpShell(tester, const Size(1913, 1065));

    expect(tester.takeException(), isNull);

    // The section title is the 18px bold text in the topbar; the
    // sidebar nav label 'Overview' is a second match, so take the
    // last one (the topbar title comes after the nav in the tree).
    final titles = tester.getRect(find.text('Overview').last);
    final dateRect = tester.getRect(find.text(_todayDate()));
    final buttonRect = tester.getRect(find.text('New task'));
    final searchBox =
        tester.getRect(find.byType(TextField).first);

    // Title: real width, sitting just inside the content area.
    expect(titles.width, greaterThan(50));
    expect(titles.left, greaterThanOrEqualTo(232));
    expect(titles.left, lessThan(400));
    // Date: a normal line, not a ~10px vertical strip.
    expect(dateRect.width, greaterThan(80));
    // Search field and button both on screen, button pinned to
    // the right edge (20px topbar padding).
    expect(searchBox.width, 240);
    expect(buttonRect.left, greaterThan(searchBox.right));
    expect(buttonRect.right, lessThanOrEqualTo(1913));
    expect(buttonRect.right, greaterThan(1850));
    expect(buttonRect.width, greaterThan(80));
  });

  testWidgets('desktop 1440px: title, date and New task button visible',
      (tester) async {
    await _pumpShell(tester, const Size(1440, 900));

    expect(tester.takeException(), isNull);

    final dateRect = tester.getRect(find.text(_todayDate()));
    final buttonRect = tester.getRect(find.text('New task'));
    expect(dateRect.width, greaterThan(80));
    expect(buttonRect.right, lessThanOrEqualTo(1440));
    expect(buttonRect.right, greaterThan(1380));
    expect(buttonRect.width, greaterThan(80));
  });

  testWidgets('rail 800px: title visible, search hidden, button visible',
      (tester) async {
    await _pumpShell(tester, const Size(800, 900));

    expect(tester.takeException(), isNull);

    final dateRect = tester.getRect(find.text(_todayDate()));
    final buttonRect = tester.getRect(find.text('New task'));
    expect(dateRect.width, greaterThan(80));
    // Topbar search hides below 900px; only the Board's own
    // search (different hint) is absent here on Overview.
    expect(find.byType(TextField), findsNothing);
    expect(buttonRect.right, lessThanOrEqualTo(800));
  });

  testWidgets('phone 390px: hamburger, title and add icon visible',
      (tester) async {
    await _pumpShell(tester, const Size(390, 844));

    expect(tester.takeException(), isNull);

    final titles = tester.getRect(find.text('Overview').last);
    expect(titles.width, greaterThan(50));
    // Icon-only add button below 560px.
    expect(find.byIcon(Icons.add), findsWidgets);
    expect(find.text('New task'), findsNothing);
  });
}
