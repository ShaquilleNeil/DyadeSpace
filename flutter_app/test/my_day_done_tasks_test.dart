import 'dart:async';

import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/app_user.dart';
import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/models/task_item.dart';
import 'package:dyadespace/providers/auth_provider.dart';
import 'package:dyadespace/providers/locale_provider.dart';
import 'package:dyadespace/providers/sites_provider.dart';
import 'package:dyadespace/providers/stages_provider.dart';
import 'package:dyadespace/providers/tasks_provider.dart';
import 'package:dyadespace/screens/worker/my_day_screen.dart';
import 'package:dyadespace/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Widget tests for My Day hiding done tasks: a task that is
/// Done never renders in My Day — not on the day it was
/// finished, not as a chain context card — while to-do,
/// in-progress, overdue and blocked tasks still do, and
/// marking a task Done removes it live when the stream
/// re-emits (no restart, no pull-to-refresh).
void main() {
  const strings = AppStrings('en');
  const me = AppUser(
      id: 'me-1', name: 'Moi Worker', email: 'm@d.c', role: UserRole.worker);
  const other = AppUser(
      id: 'u2', name: 'Eli Other', email: 'b@d.c', role: UserRole.worker);
  const site = Site(id: 'site-1', name: 'Maple Court');

  DateTime today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day, 12);
  }

  TaskItem task({
    required String id,
    required String title,
    required TaskStatus status,
    List<String> assigneeIds = const ['me-1'],
    DateTime? dueDate,
    DateTime? finishedAt,
    String? dependsOnTaskId,
  }) =>
      TaskItem(
        id: id,
        title: title,
        siteId: 'site-1',
        assigneeIds: assigneeIds,
        createdBy: 'admin-1',
        status: status,
        dueDate: dueDate ?? today(),
        finishedAt: finishedAt,
        dependsOnTaskId: dependsOnTaskId,
      );

  /// Pumps My Day with the task list driven by a broadcast
  /// controller, so tests can re-emit a changed list and watch
  /// the screen update live.
  Future<StreamController<List<TaskItem>>> pumpMyDay(
    WidgetTester tester,
    List<TaskItem> initial,
  ) async {
    final controller = StreamController<List<TaskItem>>.broadcast();
    addTearDown(controller.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(strings),
          currentUserProvider
              .overrideWith((ref) => Stream.value(me)),
          allUsersProvider
              .overrideWith((ref) => Stream.value([me, other])),
          siteByIdProvider.overrideWithValue({'site-1': site}),
          stageIndexProvider.overrideWithValue(null),
          allTasksProvider.overrideWith((ref) => controller.stream),
          myTasksProvider.overrideWith((ref) => controller.stream.map(
              (all) => all.where((t) => t.assigneeIds.contains('me-1')).toList())),
        ],
        child: MaterialApp(
          theme: buildAppDarkTheme(),
          home: const Scaffold(body: MyDayScreen()),
        ),
      ),
    );
    controller.add(initial);
    await tester.pump();
    await tester.pump();
    // MyDayScreen watches allTasksProvider only once
    // myTasksProvider has data, so it subscribes after the
    // first emit and a plain broadcast stream would leave it
    // empty (production Firestore streams replay the latest
    // snapshot, so this is a test-harness artifact only).
    // Re-emit so the late subscriber gets the same list.
    controller.add(initial);
    await tester.pump();
    await tester.pump();
    return controller;
  }

  group('My Day hides done tasks', () {
    testWidgets('a task done today does not render', (tester) async {
      await pumpMyDay(tester, [
        task(id: 'open', title: 'Open task', status: TaskStatus.todo),
        task(
          id: 'done',
          title: 'Done task',
          status: TaskStatus.done,
          finishedAt: today(),
        ),
      ]);
      expect(find.text('Open task'), findsOneWidget);
      expect(find.text('Done task'), findsNothing);
    });

    testWidgets('to-do, in-progress, overdue and blocked still show',
        (tester) async {
      final yesterday = today().subtract(const Duration(days: 1));
      await pumpMyDay(tester, [
        task(id: 'a', title: 'Todo task', status: TaskStatus.todo),
        task(id: 'b', title: 'Started task', status: TaskStatus.inProgress),
        task(id: 'c', title: 'Blocked task', status: TaskStatus.blocked),
        task(
            id: 'd',
            title: 'Overdue task',
            status: TaskStatus.todo,
            dueDate: yesterday),
      ]);
      expect(find.text('Todo task'), findsOneWidget);
      expect(find.text('Started task'), findsOneWidget);
      expect(find.text('Blocked task'), findsOneWidget);
      expect(find.text('Overdue task'), findsOneWidget);
    });

    testWidgets('marking a task done removes it live', (tester) async {
      final open =
          task(id: 'a', title: 'Vanishing task', status: TaskStatus.todo);
      final controller = await pumpMyDay(tester, [open]);
      expect(find.text('Vanishing task'), findsOneWidget);
      controller.add([
        open.copyWith(status: TaskStatus.done, finishedAt: today()),
      ]);
      await tester.pump();
      await tester.pump();
      expect(find.text('Vanishing task'), findsNothing);
      // All done: the empty state shows instead of an empty list.
      expect(find.text(strings.noTasks), findsOneWidget);
    });

    testWidgets('a done chain predecessor shows no context card',
        (tester) async {
      await pumpMyDay(tester, [
        task(
          id: 'pred',
          title: 'Finished predecessor',
          status: TaskStatus.done,
          assigneeIds: const ['u2'],
          finishedAt: today(),
        ),
        task(
          id: 'mine',
          title: 'My unlocked step',
          status: TaskStatus.todo,
          dependsOnTaskId: 'pred',
        ),
      ]);
      expect(find.text('My unlocked step'), findsOneWidget);
      expect(find.text('Finished predecessor'), findsNothing);
    });

    testWidgets('an open chain predecessor still shows as context',
        (tester) async {
      await pumpMyDay(tester, [
        task(
          id: 'pred',
          title: 'Open predecessor',
          status: TaskStatus.todo,
          assigneeIds: const ['u2'],
        ),
        task(
          id: 'mine',
          title: 'My locked step',
          status: TaskStatus.todo,
          dependsOnTaskId: 'pred',
        ),
      ]);
      expect(find.text('Open predecessor'), findsOneWidget);
      expect(find.text('My locked step'), findsOneWidget);
    });
  });
}
