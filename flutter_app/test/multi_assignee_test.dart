import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/models/app_user.dart';
import 'package:dyadespace/models/task_item.dart';
import 'package:dyadespace/providers/locale_provider.dart';
import 'package:dyadespace/widgets/assignee_picker.dart';
import 'package:dyadespace/widgets/task_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TaskItem assigneeIds compatibility', () {
    test('old doc with single assigneeId loads as a one-person list', () {
      final t = TaskItem.fromMap('t1', {
        'title': 'Paint',
        'siteId': 'site-1',
        'assigneeId': 'u1',
        'createdBy': 'admin',
        'status': 'todo',
      });
      expect(t.assigneeIds, ['u1']);
      expect(t.isAssigned, isTrue);
      expect(t.assignedTo('u1'), isTrue);
      expect(t.assignedTo('u2'), isFalse);
    });

    test('new doc round-trips the list', () {
      final t = TaskItem.fromMap('t1', {
        'title': 'Paint',
        'siteId': 'site-1',
        'assigneeIds': ['u1', 'u2'],
        'createdBy': 'admin',
        'status': 'todo',
      });
      expect(t.assigneeIds, ['u1', 'u2']);
      final back = TaskItem.fromMap('t1', t.toMap());
      expect(back.assigneeIds, ['u1', 'u2']);
    });

    test('toMap writes only the list, never the old string field', () {
      final t = TaskItem(
        id: 't1',
        title: 'Paint',
        siteId: 'site-1',
        assigneeIds: ['u1'],
        createdBy: 'admin',
      );
      final map = t.toMap();
      expect(map.containsKey('assigneeIds'), isTrue);
      expect(map.containsKey('assigneeId'), isFalse);
    });

    test('doc with neither field loads as unassigned', () {
      final t = TaskItem.fromMap('t1', {
        'title': 'Paint',
        'siteId': 'site-1',
        'createdBy': 'admin',
        'status': 'todo',
      });
      expect(t.assigneeIds, isEmpty);
      expect(t.isAssigned, isFalse);
    });

    test('empty assigneeId string loads as unassigned', () {
      final t = TaskItem.fromMap('t1', {
        'title': 'Paint',
        'siteId': 'site-1',
        'assigneeId': '',
        'createdBy': 'admin',
        'status': 'todo',
      });
      expect(t.assigneeIds, isEmpty);
    });

    test('new list wins when both fields are present', () {
      final t = TaskItem.fromMap('t1', {
        'title': 'Paint',
        'siteId': 'site-1',
        'assigneeId': 'old',
        'assigneeIds': ['u1', 'u2'],
        'createdBy': 'admin',
        'status': 'todo',
      });
      expect(t.assigneeIds, ['u1', 'u2']);
    });
  });

  group('taskAssignees helper', () {
    const strings = AppStrings('en');
    final users = {
      'u1': const AppUser(
          id: 'u1', name: 'Alex Morgan', email: 'a@b.c', role: UserRole.admin),
      'u2': const AppUser(
          id: 'u2', name: 'Sam Neil', email: 'd@e.f', role: UserRole.admin),
    };

    test('resolves names in assignment order', () {
      final t = TaskItem(
        id: 't1',
        title: 'Paint',
        siteId: 'site-1',
        assigneeIds: ['u2', 'u1'],
        createdBy: 'admin',
      );
      final list = taskAssignees(t, users, strings);
      expect(list.map((a) => a.name).toList(),
          ['Sam Neil', 'Alex Morgan']);
    });

    test('unknown id renders as former member', () {
      final t = TaskItem(
        id: 't1',
        title: 'Paint',
        siteId: 'site-1',
        assigneeIds: ['gone'],
        createdBy: 'admin',
      );
      final list = taskAssignees(t, users, strings);
      expect(list.single.name, strings.formerMember);
    });
  });

  group('AssigneePicker', () {
    const strings = AppStrings('en');
    final users = [
      const AppUser(
          id: 'u1', name: 'Alex Morgan', email: 'a@b.c', role: UserRole.admin),
      const AppUser(
          id: 'u2', name: 'Sam Neil', email: 'd@e.f', role: UserRole.admin),
      const AppUser(
          id: 'u3', name: 'Drew', email: 'g@h.i', role: UserRole.delivery),
    ];

    Future<void> pumpPicker(
      WidgetTester tester,
      Set<String> selected,
      ValueChanged<Set<String>> onChanged,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stringsProvider.overrideWithValue(strings),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: AssigneePicker(
                users: users,
                selectedIds: selected,
                onChanged: onChanged,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('empty query shows no employee list and no checkboxes',
        (tester) async {
      await pumpPicker(tester, {}, (_) {});
      expect(find.text('Alex Morgan · Admin'), findsNothing);
      expect(find.text('Sam Neil · Admin'), findsNothing);
      expect(find.text('Drew · Delivery'), findsNothing);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('adding two people via search reports both ids',
        (tester) async {
      var selected = <String>{};
      await pumpPicker(tester, selected, (next) => selected = next);
      await tester.enterText(find.byType(TextField), 'shaq');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('assignee-u1')));
      expect(selected, {'u1'});
      // Re-pump with the new selection, then search for the second.
      await pumpPicker(tester, selected, (next) => selected = next);
      await tester.enterText(find.byType(TextField), 'rol');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('assignee-u2')));
      expect(selected, {'u1', 'u2'});
    });

    testWidgets('search results exclude already-selected people',
        (tester) async {
      await pumpPicker(tester, {'u1'}, (_) {});
      await tester.enterText(find.byType(TextField), 'shaq');
      await tester.pump();
      expect(find.byKey(const ValueKey('assignee-u1')), findsNothing);
      expect(find.text('Alex Morgan · Admin'), findsNothing);
    });

    testWidgets('no checkboxes are rendered while searching',
        (tester) async {
      await pumpPicker(tester, {}, (_) {});
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump();
      expect(find.byType(ListTile), findsWidgets);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.byType(Checkbox), findsNothing);
    });

    testWidgets('no match hides the dropdown', (tester) async {
      await pumpPicker(tester, {}, (_) {});
      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump();
      expect(find.byType(ListTile), findsNothing);
      expect(find.text(strings.noPeopleMatch), findsNothing);
    });

    testWidgets('empty selection shows Unassigned', (tester) async {
      await pumpPicker(tester, {}, (_) {});
      expect(find.text(strings.unassigned), findsOneWidget);
    });

    testWidgets('typing in search narrows the list by name', (tester) async {
      await pumpPicker(tester, {}, (_) {});
      await tester.enterText(find.byType(TextField), 'rol');
      await tester.pump();
      expect(find.text('Sam Neil · Admin'), findsOneWidget);
      expect(find.text('Alex Morgan · Admin'), findsNothing);
      expect(find.text('Drew · Delivery'), findsNothing);
    });

    testWidgets('search is case-insensitive', (tester) async {
      await pumpPicker(tester, {}, (_) {});
      await tester.enterText(find.byType(TextField), 'SHAQ');
      await tester.pump();
      expect(find.text('Alex Morgan · Admin'), findsOneWidget);
      expect(find.text('Sam Neil · Admin'), findsNothing);
    });

    testWidgets('clearing the search hides the list entirely',
        (tester) async {
      await pumpPicker(tester, {}, (_) {});
      await tester.enterText(find.byType(TextField), 'rol');
      await tester.pump();
      expect(find.text('Sam Neil · Admin'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump();
      expect(find.text('Sam Neil · Admin'), findsNothing);
      expect(find.text('Alex Morgan · Admin'), findsNothing);
      expect(find.text('Drew · Delivery'), findsNothing);
    });

    testWidgets('tapping a search result adds their pill', (tester) async {
      var selected = <String>{};
      await pumpPicker(tester, selected, (next) => selected = next);
      await tester.enterText(find.byType(TextField), 'shaq');
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('assignee-u1')));
      expect(selected, {'u1'});
      await pumpPicker(tester, selected, (next) => selected = next);
      expect(
          find.byKey(const ValueKey('assignee-pill-u1')), findsOneWidget);
      expect(find.text('Alex Morgan'), findsWidgets);
    });

    testWidgets('tapping a search result closes the dropdown',
        (tester) async {
      var selected = <String>{};
      await pumpPicker(tester, selected, (next) => selected = next);
      await tester.enterText(find.byType(TextField), 'shaq');
      await tester.pump();
      expect(find.text('Alex Morgan · Admin'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('assignee-u1')));
      await tester.pump();
      expect(selected, {'u1'});
      expect(find.text('Alex Morgan · Admin'), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('losing focus closes the dropdown', (tester) async {
      await pumpPicker(tester, {}, (_) {});
      await tester.enterText(find.byType(TextField), 'rol');
      await tester.pump();
      expect(find.text('Sam Neil · Admin'), findsOneWidget);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(find.text('Sam Neil · Admin'), findsNothing);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('the dropdown floats: it does not push the pills down',
        (tester) async {
      await pumpPicker(tester, {}, (_) {});
      final before = tester.getTopLeft(find.text(strings.unassigned));
      await tester.enterText(find.byType(TextField), 'rol');
      await tester.pump();
      expect(find.text('Sam Neil · Admin'), findsOneWidget);
      final after = tester.getTopLeft(find.text(strings.unassigned));
      expect(after, before);
    });

    testWidgets("tapping a pill's X removes that person", (tester) async {
      var selected = {'u1', 'u2'};
      await pumpPicker(tester, selected, (next) => selected = next);
      expect(find.byKey(const ValueKey('assignee-pill-u1')), findsOneWidget);
      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('assignee-pill-u1')),
        matching: find.byIcon(Icons.close),
      ));
      expect(selected, {'u2'});
    });

    testWidgets('removing everyone leaves it unassigned', (tester) async {
      var selected = {'u1'};
      await pumpPicker(tester, selected, (next) => selected = next);
      expect(find.text(strings.unassigned), findsNothing);
      await tester.tap(find.descendant(
        of: find.byKey(const ValueKey('assignee-pill-u1')),
        matching: find.byIcon(Icons.close),
      ));
      expect(selected, isEmpty);
      await pumpPicker(tester, selected, (next) => selected = next);
      expect(find.text(strings.unassigned), findsOneWidget);
    });
  });

  group('TaskCard assignees', () {
    const strings = AppStrings('en');
    final users = {
      'u1': const AppUser(
          id: 'u1', name: 'Alex Morgan', email: 'a@b.c', role: UserRole.admin),
      'u2': const AppUser(
          id: 'u2', name: 'Sam Neil', email: 'd@e.f', role: UserRole.admin),
      'u3': const AppUser(
          id: 'u3', name: 'Drew', email: 'g@h.i', role: UserRole.delivery),
      'u4': const AppUser(
          id: 'u4', name: 'Eli', email: 'j@k.l', role: UserRole.worker),
    };

    Future<void> pumpCard(WidgetTester tester, TaskItem task) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stringsProvider.overrideWithValue(strings),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: TaskCard(
                task: task,
                assignees: taskAssignees(task, users, strings),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('two assignees show both names', (tester) async {
      await pumpCard(
        tester,
        TaskItem(
          id: 't1',
          title: 'Paint',
          siteId: 'site-1',
          assigneeIds: ['u1', 'u2'],
          createdBy: 'admin',
        ),
      );
      expect(find.text('Alex Morgan, Sam Neil'), findsOneWidget);
    });

    testWidgets('four assignees show first two names plus +2 more',
        (tester) async {
      await pumpCard(
        tester,
        TaskItem(
          id: 't1',
          title: 'Paint',
          siteId: 'site-1',
          assigneeIds: ['u1', 'u2', 'u3', 'u4'],
          createdBy: 'admin',
        ),
      );
      expect(find.text('Alex Morgan, Sam Neil +2 more'),
          findsOneWidget);
      expect(find.text('+1'), findsOneWidget); // avatar overflow circle
    });

    testWidgets('unassigned task shows no names line', (tester) async {
      await pumpCard(
        tester,
        TaskItem(
          id: 't1',
          title: 'Paint',
          siteId: 'site-1',
          assigneeIds: const [],
          createdBy: 'admin',
        ),
      );
      expect(find.textContaining('Alex'), findsNothing);
    });
  });
}
