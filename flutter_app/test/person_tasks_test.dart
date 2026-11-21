import 'package:dyadespace/models/task_item.dart';
import 'package:dyadespace/services/task_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TaskItem task(String id, List<String> assigneeIds, TaskStatus status) =>
      TaskItem(
        id: id,
        title: id,
        siteId: 'site-1',
        assigneeIds: assigneeIds,
        createdBy: 'admin-1',
        status: status,
      );

  group('TaskService.tasksForPerson', () {
    test('returns only the person\'s open tasks', () {
      final all = [
        task('a', ['u1'], TaskStatus.todo),
        task('b', ['u1'], TaskStatus.inProgress),
        task('c', ['u2'], TaskStatus.todo),
        task('d', ['u1'], TaskStatus.done),
      ];
      expect(
        TaskService.tasksForPerson(all, 'u1').map((t) => t.id).toList(),
        ['a', 'b'],
      );
    });

    test('excludes done tasks even when assigned to the person', () {
      final all = [task('a', ['u1'], TaskStatus.done)];
      expect(TaskService.tasksForPerson(all, 'u1'), isEmpty);
    });

    test('returns empty when the person has no tasks', () {
      final all = [task('a', ['u2'], TaskStatus.todo)];
      expect(TaskService.tasksForPerson(all, 'u1'), isEmpty);
    });

    test('keeps provider order', () {
      final all = [
        task('b', ['u1'], TaskStatus.blocked),
        task('a', ['u1'], TaskStatus.todo),
      ];
      expect(
        TaskService.tasksForPerson(all, 'u1').map((t) => t.id).toList(),
        ['b', 'a'],
      );
    });

    test('a task with several assignees shows for each of them', () {
      final all = [task('a', ['u1', 'u2'], TaskStatus.todo)];
      expect(
        TaskService.tasksForPerson(all, 'u1').map((t) => t.id).toList(),
        ['a'],
      );
      expect(
        TaskService.tasksForPerson(all, 'u2').map((t) => t.id).toList(),
        ['a'],
      );
    });

    test('an unassigned task shows for nobody', () {
      final all = [task('a', [], TaskStatus.todo)];
      expect(TaskService.tasksForPerson(all, 'u1'), isEmpty);
      expect(TaskService.tasksForPerson(all, 'u2'), isEmpty);
    });
  });

  group('TaskService.tasksForAssignee', () {
    test('includes done tasks, filters by membership', () {
      final all = [
        task('a', ['u1'], TaskStatus.done),
        task('b', ['u2'], TaskStatus.todo),
        task('c', ['u1', 'u2'], TaskStatus.todo),
        task('d', [], TaskStatus.todo),
      ];
      expect(
        TaskService.tasksForAssignee(all, 'u1').map((t) => t.id).toList(),
        ['a', 'c'],
      );
      expect(
        TaskService.tasksForAssignee(all, 'u2').map((t) => t.id).toList(),
        ['b', 'c'],
      );
    });
  });
}
