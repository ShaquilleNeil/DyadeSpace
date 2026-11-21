import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dyadespace/models/roadmap_template.dart';
import 'package:dyadespace/models/task_item.dart';
import 'package:dyadespace/services/stage_service.dart';
import 'package:dyadespace/services/task_service.dart';

/// Roadmap copy + custom templates (Nov 17, 2026): a site's
/// roadmap can be saved as a reusable template, a saved
/// template can be applied when creating a roadmap, and a
/// roadmap can be copied onto another site. Copied/applied
/// tasks always come over fresh — To do, unassigned, no dates,
/// no photos, no dependency links — while their titles, notes
/// and materials carry over. Copying/applying onto a site
/// that already has a roadmap is blocked, same as the house
/// template's no-op guard.

Future<void> _seedSiteRoadmap(
  StageService stages,
  TaskService tasks, {
  required String siteId,
}) async {
  final foundationId = await stages.createStage(
      siteId: siteId, name: 'Foundation', order: 1);
  final framingId = await stages.createStage(
      siteId: siteId, name: 'Framing', order: 2);
  // A unit stage on the same site: it belongs to the unit's
  // roadmap, never the site's — templates and copies must
  // ignore it.
  await stages.createStage(
      siteId: siteId, unitId: 'unit-1', name: 'Unit stage', order: 1);
  await tasks.createTask(TaskItem(
    id: '',
    title: 'Pour concrete',
    siteId: siteId,
    assigneeIds: const ['worker-1'],
    createdBy: 'admin-1',
    status: TaskStatus.done,
    notes: 'C25 mix',
    materials: const ['Cement', 'Rebar'],
    stageId: foundationId,
  ));
  await tasks.createTask(TaskItem(
    id: '',
    title: 'Cure slab',
    siteId: siteId,
    createdBy: 'admin-1',
    status: TaskStatus.todo,
    stageId: foundationId,
  ));
  await tasks.createTask(TaskItem(
    id: '',
    title: 'Raise walls',
    siteId: siteId,
    assigneeIds: const ['worker-2'],
    createdBy: 'admin-1',
    status: TaskStatus.inProgress,
    notes: 'Check level',
    stageId: framingId,
  ));
}

Future<List<Map<String, dynamic>>> _siteStages(
    FakeFirebaseFirestore db, String siteId) async {
  final snap = await db
      .collection('stages')
      .where('siteId', isEqualTo: siteId)
      .get();
  final docs = snap.docs
      .where((d) => (d.data()['unitId'] as String?) == null)
      .toList()
    ..sort((a, b) =>
        (a.data()['order'] as int).compareTo(b.data()['order'] as int));
  return docs.map((d) => d.data()).toList();
}

Future<List<Map<String, dynamic>>> _stageTasks(
    FakeFirebaseFirestore db, String stageId) async {
  final snap = await db
      .collection('tasks')
      .where('stageId', isEqualTo: stageId)
      .get();
  return snap.docs.map((d) => d.data()).toList();
}

Future<List<String>> _stageIds(
    FakeFirebaseFirestore db, String siteId) async {
  final snap = await db
      .collection('stages')
      .where('siteId', isEqualTo: siteId)
      .get();
  final docs = snap.docs
      .where((d) => (d.data()['unitId'] as String?) == null)
      .toList()
    ..sort((a, b) =>
        (a.data()['order'] as int).compareTo(b.data()['order'] as int));
  return docs.map((d) => d.id).toList();
}

void main() {
  late FakeFirebaseFirestore db;
  late StageService stages;
  late TaskService tasks;

  setUp(() {
    db = FakeFirebaseFirestore();
    stages = StageService(db: db);
    tasks = TaskService(db: db);
  });

  test('save a roadmap as a template keeps stages and task definitions',
      () async {
    await _seedSiteRoadmap(stages, tasks, siteId: 'site-1');
    final id = await stages.saveRoadmapAsTemplate(
        siteId: 'site-1', name: 'House build', createdBy: 'admin-1');
    expect(id, isNotEmpty);

    final doc = await db.collection('roadmap_templates').doc(id).get();
    final template = RoadmapTemplate.fromFirestore(doc);
    expect(template.name, 'House build');
    expect(template.createdBy, 'admin-1');
    // The unit stage is not part of the site roadmap.
    expect(template.stages.map((s) => s.name), ['Foundation', 'Framing']);
    expect(template.stages[0].order, 1);
    expect(template.stages[1].order, 2);
    // Task definitions carry over; progress and assignees do not.
    expect(
        template.stages[0].tasks.map((t) => t.title),
        containsAll(['Pour concrete', 'Cure slab']));
    final pour = template.stages[0].tasks
        .firstWhere((t) => t.title == 'Pour concrete');
    expect(pour.notes, 'C25 mix');
    expect(pour.materials, ['Cement', 'Rebar']);
    expect(template.stages[1].tasks.map((t) => t.title), ['Raise walls']);
  });

  test('save returns empty and writes nothing when the site has no roadmap',
      () async {
    final id = await stages.saveRoadmapAsTemplate(
        siteId: 'site-empty', name: 'Nothing', createdBy: 'admin-1');
    expect(id, isEmpty);
    final snap = await db.collection('roadmap_templates').get();
    expect(snap.docs, isEmpty);
  });

  test('apply a saved template creates fresh stages and tasks', () async {
    await _seedSiteRoadmap(stages, tasks, siteId: 'site-1');
    final id = await stages.saveRoadmapAsTemplate(
        siteId: 'site-1', name: 'House build', createdBy: 'admin-1');
    final template = RoadmapTemplate.fromFirestore(
        await db.collection('roadmap_templates').doc(id).get());

    final ok = await stages.createRoadmapFromRoadmapTemplate(
        siteId: 'site-2', template: template, createdBy: 'admin-1');
    expect(ok, isTrue);

    final siteStages = await _siteStages(db, 'site-2');
    expect(siteStages.map((s) => s['name']), ['Foundation', 'Framing']);
    expect(siteStages.map((s) => s['order']), [1, 2]);
    final ids = await _stageIds(db, 'site-2');
    final foundationTasks = await _stageTasks(db, ids[0]);
    expect(foundationTasks.map((t) => t['title']),
        containsAll(['Pour concrete', 'Cure slab']));
    for (final task in foundationTasks) {
      // Fresh: To do, unassigned, no progress carried over.
      expect(task['status'], 'todo');
      expect(task['assigneeIds'], isEmpty);
      expect(task['siteId'], 'site-2');
      expect(task['dueDate'], isNull);
      expect(task['startedAt'], isNull);
      expect(task['photoUrls'], isEmpty);
      expect(task['dependsOnTaskId'], isNull);
    }
    final pour = foundationTasks
        .firstWhere((t) => t['title'] == 'Pour concrete');
    expect(pour['notes'], 'C25 mix');
    expect(pour['materials'], ['Cement', 'Rebar']);
    final framingTasks = await _stageTasks(db, ids[1]);
    expect(framingTasks.map((t) => t['title']), ['Raise walls']);
    expect(framingTasks.first['notes'], 'Check level');
  });

  test('apply is blocked when the target already has a roadmap', () async {
    await _seedSiteRoadmap(stages, tasks, siteId: 'site-1');
    final id = await stages.saveRoadmapAsTemplate(
        siteId: 'site-1', name: 'House build', createdBy: 'admin-1');
    final template = RoadmapTemplate.fromFirestore(
        await db.collection('roadmap_templates').doc(id).get());

    // site-1 already has its own roadmap.
    final ok = await stages.createRoadmapFromRoadmapTemplate(
        siteId: 'site-1', template: template, createdBy: 'admin-1');
    expect(ok, isFalse);
    // Nothing was added: still the original 2 site stages.
    expect((await _siteStages(db, 'site-1')).length, 2);
  });

  test('copy a roadmap to another site, source untouched', () async {
    await _seedSiteRoadmap(stages, tasks, siteId: 'site-1');
    final beforeStages = await _siteStages(db, 'site-1');
    final beforeTasks = await db.collection('tasks').get();

    final ok = await stages.copyRoadmap(
        fromSiteId: 'site-1', toSiteId: 'site-2', createdBy: 'admin-1');
    expect(ok, isTrue);

    final siteStages = await _siteStages(db, 'site-2');
    expect(siteStages.map((s) => s['name']), ['Foundation', 'Framing']);
    // Fresh stages: never started or skipped.
    for (final stage in siteStages) {
      expect(stage['startedAt'], isNull);
      expect(stage['skipped'], isFalse);
    }
    final ids = await _stageIds(db, 'site-2');
    final copiedTasks = await _stageTasks(db, ids[0]);
    expect(copiedTasks.map((t) => t['title']),
        containsAll(['Pour concrete', 'Cure slab']));
    for (final task in copiedTasks) {
      expect(task['status'], 'todo');
      expect(task['assigneeIds'], isEmpty);
      expect(task['siteId'], 'site-2');
    }
    // The source roadmap is untouched: same stages, same tasks.
    expect(await _siteStages(db, 'site-1'), beforeStages);
    expect((await db.collection('tasks').get()).docs.length,
        beforeTasks.docs.length + 3);
  });

  test('copy is blocked when the target already has a roadmap', () async {
    await _seedSiteRoadmap(stages, tasks, siteId: 'site-1');
    await _seedSiteRoadmap(stages, tasks, siteId: 'site-2');

    final ok = await stages.copyRoadmap(
        fromSiteId: 'site-1', toSiteId: 'site-2', createdBy: 'admin-1');
    expect(ok, isFalse);
    expect((await _siteStages(db, 'site-2')).length, 2);
    expect((await db.collection('tasks').get()).docs.length, 6);
  });

  test('copy from a site with no roadmap writes nothing', () async {
    final ok = await stages.copyRoadmap(
        fromSiteId: 'site-empty', toSiteId: 'site-2', createdBy: 'admin-1');
    expect(ok, isFalse);
    expect((await _siteStages(db, 'site-2')), isEmpty);
  });

  test('house template still creates the 7 stages', () async {
    await stages.createRoadmapFromTemplate('site-1');
    final siteStages = await _siteStages(db, 'site-1');
    expect(
        siteStages.map((s) => s['name']),
        [
          'Foundation',
          'Framing',
          'Roofing',
          'Plumbing',
          'Electrical',
          'Drywall',
          'Paint & Finishing',
        ]);
    expect(siteStages.map((s) => s['order']), [1, 2, 3, 4, 5, 6, 7]);
    // Second call is still a no-op.
    await stages.createRoadmapFromTemplate('site-1');
    expect((await _siteStages(db, 'site-1')).length, 7);
  });

  test('delete a saved template removes it', () async {
    await _seedSiteRoadmap(stages, tasks, siteId: 'site-1');
    final id = await stages.saveRoadmapAsTemplate(
        siteId: 'site-1', name: 'House build', createdBy: 'admin-1');
    await stages.deleteTemplate(id);
    expect((await db.collection('roadmap_templates').get()).docs, isEmpty);
  });
}
