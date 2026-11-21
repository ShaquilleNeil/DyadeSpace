import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/app_user.dart';
import 'package:dyadespace/models/delivery_run.dart';
import 'package:dyadespace/models/material_request.dart';
import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/providers/auth_provider.dart';
import 'package:dyadespace/providers/locale_provider.dart';
import 'package:dyadespace/providers/material_requests_provider.dart';
import 'package:dyadespace/providers/runs_provider.dart';
import 'package:dyadespace/providers/sites_provider.dart';
import 'package:dyadespace/screens/manager/material_requests_screen.dart';
import 'package:dyadespace/services/material_request_service.dart';
import 'package:dyadespace/theme/app_theme.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

/// Widget tests for the material-requests tabs + delete:
/// the Requests tab shows only requests awaiting a decision,
/// the History tab shows everything decided, approving moves
/// a request to History at once, and delete (with confirm)
/// removes it — offered only where the rules allow it.
void main() {
  const strings = AppStrings('en');

  const manager = AppUser(
      id: 'manager-1', name: 'Alex Morgan', email: 'm@d.c',
      role: UserRole.manager);
  const worker1 = AppUser(
      id: 'worker-1', name: 'Wendy Worker', email: 'w@d.c',
      role: UserRole.worker);

  setUpAll(() async {
    await initializeDateFormatting('en');
    // Same font setup as week_hours_visits_widgets_test.dart:
    // widget tests fall back to Ahem unless a real sans is
    // loaded, and the card header row overflows with it.
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

  MaterialRequest req({
    required String id,
    required String item,
    required MaterialRequestStatus status,
    String requesterId = 'worker-1',
    String requesterName = 'Wendy Worker',
  }) =>
      MaterialRequest(
        id: id,
        requesterId: requesterId,
        requesterName: requesterName,
        siteId: 'site-1',
        item: item,
        status: status,
        createdAt: DateTime(2026, 11, 17),
      );

  /// Fake service that drives the screen's stream, the way
  /// Firestore would: approve flips the status, delete drops
  /// the doc, and the list is re-emitted so the tabs update.
  late StreamController<List<MaterialRequest>> controller;
  late List<MaterialRequest> current;

  Future<void> pumpScreen(
    WidgetTester tester, {
    required AppUser me,
    required List<MaterialRequest> initial,
  }) async {
    current = List.of(initial);
    controller = StreamController<List<MaterialRequest>>.broadcast();
    addTearDown(controller.close);
    final service = _FakeRequestService(
      onApprove: (r) {
        current = current
            .map((x) => x.id == r.id
                ? x.copyWith(status: MaterialRequestStatus.approved)
                : x)
            .toList();
        controller.add(current);
      },
      onDelete: (id) {
        current = current.where((x) => x.id != id).toList();
        controller.add(current);
      },
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(strings),
          materialRequestsProvider.overrideWith((ref) => controller.stream),
          currentUserProvider.overrideWith((ref) => Stream.value(me)),
          allRunsProvider.overrideWith((ref) => Stream.value(<DeliveryRun>[])),
          allUsersProvider.overrideWith((ref) => Stream.value(<AppUser>[])),
          siteByIdProvider.overrideWithValue(<String, Site>{}),
          materialRequestServiceProvider.overrideWithValue(service),
        ],
        child: MaterialApp(
          theme: buildAppTheme(),
          home: const MaterialRequestsScreen(),
        ),
      ),
    );
    controller.add(current);
    await tester.pumpAndSettle();
  }

  Future<void> goToHistory(WidgetTester tester) async {
    await tester.tap(find.text(strings.materialRequestTabHistory));
    await tester.pumpAndSettle();
  }

  testWidgets('Requests tab shows only requested; History shows decided',
      (tester) async {
    await pumpScreen(tester, me: manager, initial: [
      req(id: 'r1', item: 'Cement', status: MaterialRequestStatus.requested),
      req(id: 'r2', item: 'Paint', status: MaterialRequestStatus.approved),
      req(id: 'r3', item: 'Lumber', status: MaterialRequestStatus.onRun),
      req(id: 'r4', item: 'Tiles', status: MaterialRequestStatus.delivered),
      req(id: 'r5', item: 'Glass', status: MaterialRequestStatus.denied),
    ]);
    expect(find.text('1 × Cement'), findsOneWidget);
    expect(find.text('1 × Paint'), findsNothing);
    expect(find.text('1 × Lumber'), findsNothing);
    expect(find.text('1 × Tiles'), findsNothing);
    expect(find.text('1 × Glass'), findsNothing);

    await goToHistory(tester);
    expect(find.text('1 × Cement'), findsNothing);
    expect(find.text('1 × Paint'), findsOneWidget);
    expect(find.text('1 × Lumber'), findsOneWidget);
    expect(find.text('1 × Tiles'), findsOneWidget);
    expect(find.text('1 × Glass'), findsOneWidget);
  });

  testWidgets('approving a request moves it to History at once',
      (tester) async {
    await pumpScreen(tester, me: manager, initial: [
      req(id: 'r1', item: 'Cement', status: MaterialRequestStatus.requested),
    ]);
    expect(find.text('1 × Cement'), findsOneWidget);
    await tester.tap(find.text(strings.materialRequestApprove));
    await tester.pumpAndSettle();
    expect(find.text(strings.confirmApproveRequest), findsOneWidget);
    await tester.tap(find.text(strings.confirm));
    await tester.pumpAndSettle();
    expect(find.text('1 × Cement'), findsNothing);
    expect(find.text(strings.materialRequestApproved), findsOneWidget);

    await goToHistory(tester);
    expect(find.text('1 × Cement'), findsOneWidget);
  });

  testWidgets('deleting with confirm removes it', (tester) async {
    await pumpScreen(tester, me: manager, initial: [
      req(id: 'r1', item: 'Cement', status: MaterialRequestStatus.requested),
    ]);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    expect(find.text(strings.materialRequestDeleteTitle), findsOneWidget);
    await tester.tap(find.text(strings.materialRequestDelete));
    await tester.pumpAndSettle();
    expect(find.text('1 × Cement'), findsNothing);
    expect(find.text(strings.materialRequestDeleted), findsOneWidget);
  });

  testWidgets('cancelling the delete keeps the request', (tester) async {
    await pumpScreen(tester, me: manager, initial: [
      req(id: 'r1', item: 'Cement', status: MaterialRequestStatus.requested),
    ]);
    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.cancel));
    await tester.pumpAndSettle();
    expect(find.text('1 × Cement'), findsOneWidget);
  });

  testWidgets('manager sees delete on any request', (tester) async {
    await pumpScreen(tester, me: manager, initial: [
      req(id: 'r1', item: 'Paint', status: MaterialRequestStatus.approved),
    ]);
    await goToHistory(tester);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('requester sees delete on their own requested request',
      (tester) async {
    await pumpScreen(tester, me: worker1, initial: [
      req(id: 'r1', item: 'Cement', status: MaterialRequestStatus.requested),
    ]);
    expect(find.byIcon(Icons.delete_outline), findsOneWidget);
  });

  testWidgets('requester sees no delete on their own decided request',
      (tester) async {
    await pumpScreen(tester, me: worker1, initial: [
      req(id: 'r1', item: 'Paint', status: MaterialRequestStatus.approved),
    ]);
    await goToHistory(tester);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });

  testWidgets('worker sees no delete on someone else’s request',
      (tester) async {
    await pumpScreen(tester, me: worker1, initial: [
      req(
          id: 'r1',
          item: 'Cement',
          status: MaterialRequestStatus.requested,
          requesterId: 'worker-2',
          requesterName: 'Walt Worker'),
    ]);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
  });
}

class _FakeRequestService extends MaterialRequestService {
  _FakeRequestService({
    required this.onApprove,
    required this.onDelete,
  }) : super(db: FakeFirebaseFirestore());

  final void Function(MaterialRequest) onApprove;
  final void Function(String) onDelete;

  @override
  Future<void> approve(MaterialRequest request) async => onApprove(request);

  @override
  Future<void> deny(MaterialRequest request, String reason) async {}

  @override
  Future<void> deleteRequest(String id) async => onDelete(id);

  @override
  Future<void> attachToRun({
    required MaterialRequest request,
    required DeliveryRun run,
    required String siteName,
  }) async {}
}
