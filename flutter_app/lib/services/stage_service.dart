import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/roadmap_template.dart';
import '../models/stage.dart';
import '../models/task_item.dart';

/// All Firestore access for roadmap stages (one step of a site's
/// roadmap). Mirrors [TeamService]: the service owns the writes,
/// providers and screens read through it.
class StageService {
  final FirebaseFirestore _db;
  StageService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _stages =>
      _db.collection('stages');

  CollectionReference<Map<String, dynamic>> get _templates =>
      _db.collection('roadmap_templates');

  CollectionReference<Map<String, dynamic>> get _tasks =>
      _db.collection('tasks');

  /// The 7 house stages, in order (the roadmap template).
  static const List<String> houseTemplate = [
    'Foundation',
    'Framing',
    'Roofing',
    'Plumbing',
    'Electrical',
    'Drywall',
    'Paint & Finishing',
  ];

  /// Every stage, ordered by `order` (the per-site order is
  /// applied in Dart by [StageIndex]).
  Stream<List<Stage>> watchAllStages() {
    return _stages.orderBy('order').snapshots().map(
        (snap) => snap.docs.map(Stage.fromFirestore).toList());
  }

  /// One site's roadmap stages, in roadmap order. The query
  /// returns every stage of the site (unit stages included);
  /// [StageIndex.stagesForSite] keeps only the site stages in
  /// Dart, so the site roadmap never shows a unit's stages.
  Stream<List<Stage>> watchStagesForSite(String siteId) {
    return _stages
        .where('siteId', isEqualTo: siteId)
        .orderBy('order')
        .snapshots()
        .map((snap) => snap.docs.map(Stage.fromFirestore).toList());
  }

  /// One unit's roadmap stages, in roadmap order. Single-field
  /// query, sorted by (order, id) in Dart — no composite index,
  /// same pattern as the units queries.
  Stream<List<Stage>> watchStagesForUnit(String unitId) {
    return _stages
        .where('unitId', isEqualTo: unitId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(Stage.fromFirestore).toList();
      list.sort(_byOrder);
      return list;
    });
  }

  static int _byOrder(Stage a, Stage b) {
    final o = a.order.compareTo(b.order);
    if (o != 0) return o;
    return a.id.compareTo(b.id);
  }

  Future<String> createStage({
    required String siteId,
    String? unitId,
    required String name,
    required int order,
  }) async {
    final ref = await _stages.add(Stage(
      id: '',
      siteId: siteId,
      unitId: unitId,
      name: name,
      order: order,
    ).toMap());
    return ref.id;
  }

  /// Creates the 7 house stages for a site, in order (orders
  /// 1..7). Returns false — and writes nothing — when the site
  /// already has a roadmap. Only site stages (unitId null)
  /// count: a site whose units already have roadmaps can still
  /// get its own.
  Future<bool> createRoadmapFromTemplate(String siteId) async {
    final written = await _writeRoadmap(
      siteId: siteId,
      stages: [
        for (var i = 0; i < houseTemplate.length; i++)
          TemplateStage(name: houseTemplate[i], order: i + 1),
      ],
      createdBy: '',
    );
    return written;
  }

  /// True when the site already has a site roadmap (at least
  /// one stage with no unitId). Unit roadmaps never count.
  Future<bool> hasSiteRoadmap(String siteId) async {
    final existing = await _stages.where('siteId', isEqualTo: siteId).get();
    return existing.docs
        .any((d) => (d.data()['unitId'] as String?) == null);
  }

  /// All saved roadmap templates, by name.
  Stream<List<RoadmapTemplate>> watchTemplates() {
    return _templates.orderBy('name').snapshots().map((snap) =>
        snap.docs.map(RoadmapTemplate.fromFirestore).toList());
  }

  /// Saves a site's roadmap as a reusable template: its stages
  /// in order, each with its tasks' titles, notes and
  /// materials. Progress, assignees and dates are NOT saved —
  /// a template is a definition, not a snapshot. Returns the
  /// new template's id, or '' when the site has no roadmap.
  Future<String> saveRoadmapAsTemplate({
    required String siteId,
    required String name,
    required String createdBy,
  }) async {
    final stages = await _readSiteRoadmap(siteId);
    if (stages.isEmpty) return '';
    final ref = await _templates.add(RoadmapTemplate(
      id: '',
      name: name,
      createdBy: createdBy,
      stages: stages,
    ).toMap());
    return ref.id;
  }

  /// Deletes a saved template. Rules gate it: admin/manager
  /// or the template's creator.
  Future<void> deleteTemplate(String templateId) {
    return _templates.doc(templateId).delete();
  }

  /// Creates a site's roadmap from a saved template (its
  /// stages and their tasks, fresh). Returns false — and writes
  /// nothing — when the site already has a roadmap. The guard
  /// and the write are atomic (see [_writeRoadmap]): a
  /// concurrent copy/apply cannot slip a duplicate roadmap in
  /// between the check and the write.
  Future<bool> createRoadmapFromRoadmapTemplate({
    required String siteId,
    required RoadmapTemplate template,
    required String createdBy,
  }) async {
    return _writeRoadmap(
      siteId: siteId,
      stages: template.stages,
      createdBy: createdBy,
    );
  }

  /// Copies a site's roadmap onto another site: its stages in
  /// order, each with its tasks. Copied tasks come over fresh —
  /// To do, unassigned, no dates, no photos, no dependency
  /// links — and belong to the target site. Returns false —
  /// and writes nothing — when the target site already has a
  /// roadmap; the source roadmap is never touched. The guard
  /// and the write are atomic (see [_writeRoadmap]).
  Future<bool> copyRoadmap({
    required String fromSiteId,
    required String toSiteId,
    required String createdBy,
  }) async {
    final stages = await _readSiteRoadmap(fromSiteId);
    if (stages.isEmpty) return false;
    return _writeRoadmap(
      siteId: toSiteId,
      stages: stages,
      createdBy: createdBy,
    );
  }

  /// Reads one site's roadmap as template stages: its site
  /// stages (unitId null) in order, each with its tasks'
  /// definitions (title, notes, materials). Task order inside
  /// a stage follows creation order, then title.
  Future<List<TemplateStage>> _readSiteRoadmap(String siteId) async {
    final snap = await _stages
        .where('siteId', isEqualTo: siteId)
        .orderBy('order')
        .get();
    final stages = snap.docs
        .map(Stage.fromFirestore)
        .where((s) => s.unitId == null)
        .toList();
    final out = <TemplateStage>[];
    for (final stage in stages) {
      final taskSnap = await _tasks
          .where('stageId', isEqualTo: stage.id)
          .get();
      final tasks = taskSnap.docs.map(TaskItem.fromFirestore).toList()
        ..sort((a, b) {
          final ca = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final cb = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final c = ca.compareTo(cb);
          return c != 0 ? c : a.title.compareTo(b.title);
        });
      out.add(TemplateStage(
        name: stage.name,
        order: stage.order,
        tasks: [
          for (final t in tasks)
            TemplateTask(
              title: t.title,
              notes: t.notes,
              materials: t.materials,
            ),
        ],
      ));
    }
    return out;
  }

  /// Writes a roadmap onto a site: new stage docs (fresh ids,
  /// order kept, never started or skipped) plus fresh tasks
  /// inside them — To do, unassigned, no dates, no photos, no
  /// dependency links, the caller's uid as creator. Returns
  /// false — and writes nothing — when the site already has a
  /// roadmap.
  ///
  /// The guard and the write are atomic. A plain check-then-
  /// write lets two concurrent copies/applies both pass the
  /// check and write two roadmaps; instead the site doc itself
  /// carries the claim: the transaction reads
  /// `sites/{siteId}.roadmapCreatedAt` and only writes when it
  /// is absent, so the loser's transaction retries, sees the
  /// claim, and writes nothing. (Transactions cannot read a
  /// query, so the stages collection cannot be the guard; the
  /// pre-check below still reads it, which also blocks sites
  /// whose roadmap predates the claim field.) Roadmaps that
  /// fit in one transaction (<= 450 writes) land wholly in it;
  /// a bigger one claims the site first and chunks the rest,
  /// rolling the claim and the stages back if a chunk fails.
  /// [deleteRoadmap] clears the claim when a site roadmap goes.
  Future<bool> _writeRoadmap({
    required String siteId,
    required List<TemplateStage> stages,
    required String createdBy,
  }) async {
    if (await hasSiteRoadmap(siteId)) return false;
    final writes = <({DocumentReference<Map<String, dynamic>> ref, Map<String, dynamic> data})>[];
    for (final templateStage in stages) {
      final stageRef = _stages.doc();
      writes.add((
        ref: stageRef,
        data: Stage(
          id: '',
          siteId: siteId,
          name: templateStage.name,
          order: templateStage.order,
        ).toMap(),
      ));
      for (final templateTask in templateStage.tasks) {
        if (templateTask.title.isEmpty) continue;
        writes.add((
          ref: _tasks.doc(),
          data: TaskItem(
            id: '',
            title: templateTask.title,
            siteId: siteId,
            createdBy: createdBy,
            status: TaskStatus.todo,
            notes: templateTask.notes,
            materials: templateTask.materials,
            stageId: stageRef.id,
          ).toMap(),
        ));
      }
    }
    final siteRef = _db.collection('sites').doc(siteId);
    // The claim write: update when the site doc exists, merge-
    // set when it does not (a plain set would wipe the doc).
    void claim(Transaction tx, DocumentSnapshot snap) {
      if (snap.exists) {
        tx.update(siteRef, {
          'roadmapCreatedAt': FieldValue.serverTimestamp(),
        });
      } else {
        tx.set(siteRef, {
          'roadmapCreatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }

    if (writes.length <= 450) {
      var claimed = false;
      await _db.runTransaction((tx) async {
        final siteSnap = await tx.get(siteRef);
        if ((siteSnap.data()?['roadmapCreatedAt']) != null) return;
        claim(tx, siteSnap);
        for (final write in writes) {
          tx.set(write.ref, write.data);
        }
        claimed = true;
      });
      return claimed;
    }

    // Huge roadmap: claim the site, then chunk the writes.
    var claimed = false;
    await _db.runTransaction((tx) async {
      final siteSnap = await tx.get(siteRef);
      if ((siteSnap.data()?['roadmapCreatedAt']) != null) return;
      claim(tx, siteSnap);
      claimed = true;
    });
    if (!claimed) return false;
    try {
      var batch = _db.batch();
      var count = 0;
      Future<void> flush() async {
        if (count == 0) return;
        await batch.commit();
        batch = _db.batch();
        count = 0;
      }

      for (final write in writes) {
        batch.set(write.ref, write.data);
        count++;
        if (count >= 400) await flush();
      }
      await flush();
    } catch (e) {
      // Roll the claim and any stages back, best-effort, so
      // the site is not stuck with a claim and half a roadmap.
      try {
        final batch = _db.batch();
        for (final write in writes) {
          batch.delete(write.ref);
        }
        batch.update(siteRef, {'roadmapCreatedAt': null});
        await batch.commit();
      } catch (_) {}
      rethrow;
    }
    return true;
  }

  Future<void> updateStage(Stage stage) {
    return _stages.doc(stage.id).update(stage.toMap());
  }

  /// Deletes a stage and clears its stageId from every task that
  /// belonged to it, so the tasks stay on the site as ordinary
  /// tasks instead of pointing at a deleted stage. Writes are
  /// chunked into batches of 400 so a stage with many tasks
  /// never hits the 500-write batch limit (like
  /// [deleteRoadmap]).
  Future<void> deleteStage(String id) async {
    final tasks = await _db
        .collection('tasks')
        .where('stageId', isEqualTo: id)
        .get();
    var batch = _db.batch();
    var writes = 0;
    Future<void> flush() async {
      if (writes == 0) return;
      await batch.commit();
      batch = _db.batch();
      writes = 0;
    }

    batch.delete(_stages.doc(id));
    writes++;
    for (final doc in tasks.docs) {
      batch.update(doc.reference, {'stageId': null});
      writes++;
      if (writes >= 400) await flush();
    }
    await flush();
  }

  /// Deletes a whole roadmap: every stage of the site, and
  /// clears stageId on all of their tasks, so the tasks stay on
  /// the site as ordinary tasks. Pass [unitId] to delete only
  /// that unit's roadmap instead — its tasks keep their unit
  /// and stay on the site without a stage. Writes are chunked
  /// into batches of 400 so a big roadmap never hits the
  /// 500-write batch limit; the task lookup runs in whereIn
  /// chunks of 30 stage ids (the per-query limit).
  Future<void> deleteRoadmap(String siteId, {String? unitId}) async {
    final all = await _stages
        .where('siteId', isEqualTo: siteId)
        .get();
    // Scope filter in Dart: a missing/null unitId is a site
    // stage, a set one is a unit stage — never mix scopes.
    final stages = all.docs
        .where((d) => (d.data()['unitId'] as String?) == unitId)
        .toList();
    if (stages.isEmpty) return;
    final stageIds = stages.map((d) => d.id).toList();
    final taskRefs = <DocumentReference<Map<String, dynamic>>>[];
    for (var i = 0; i < stageIds.length; i += 30) {
      final chunk =
          stageIds.sublist(i, min(i + 30, stageIds.length));
      final snap = await _db
          .collection('tasks')
          .where('stageId', whereIn: chunk)
          .get();
      taskRefs.addAll(snap.docs.map((d) => d.reference));
    }
    var batch = _db.batch();
    var writes = 0;
    Future<void> flush() async {
      if (writes == 0) return;
      await batch.commit();
      batch = _db.batch();
      writes = 0;
    }

    for (final doc in stages) {
      batch.delete(doc.reference);
      writes++;
      if (writes >= 400) await flush();
    }
    for (final ref in taskRefs) {
      batch.update(ref, {'stageId': null});
      writes++;
      if (writes >= 400) await flush();
    }
    await flush();
    // A deleted site roadmap releases the site's roadmap claim
    // (see [_writeRoadmap]) so a fresh roadmap can be created
    // or copied onto it later. Unit roadmaps never hold the
    // claim, so only the site scope clears it. Best-effort: a
    // missing site doc must never fail the delete.
    if (unitId == null) {
      try {
        await _db.collection('sites').doc(siteId).update({
          'roadmapCreatedAt': null,
        });
      } catch (_) {}
    }
  }

  /// Starts a stage: its tasks go live for their assignees (the
  /// Cloud Function notifies them). No-op when already started —
  /// the UI hides the button then.
  Future<void> startStage(String stageId) {
    return _stages.doc(stageId).update({
      'startedAt': FieldValue.serverTimestamp(),
      'skipped': false,
    });
  }

  /// Skips a stage: it never blocks the next one, and its tasks
  /// stay dormant. The start is reset too, so un-skipping
  /// returns it to Ready (or Locked) rather than In progress.
  Future<void> skipStage(String stageId) {
    return _stages.doc(stageId).update({
      'skipped': true,
      'startedAt': null,
    });
  }

  Future<void> unskipStage(String stageId) {
    return _stages.doc(stageId).update({'skipped': false});
  }

  /// Moves a stage one step up or down, swapping its order with
  /// the neighbour in [ordered]. No-op at the ends of the list.
  Future<void> moveStage(List<Stage> ordered, Stage stage,
      {required bool up}) async {
    final i = ordered.indexWhere((s) => s.id == stage.id);
    if (i < 0) return;
    final j = up ? i - 1 : i + 1;
    if (j < 0 || j >= ordered.length) return;
    final other = ordered[j];
    final batch = _db.batch();
    batch.update(_stages.doc(stage.id), {'order': other.order});
    batch.update(_stages.doc(other.id), {'order': stage.order});
    await batch.commit();
  }
}
