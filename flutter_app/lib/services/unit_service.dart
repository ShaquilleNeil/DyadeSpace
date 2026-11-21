import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/unit.dart';
import 'stage_service.dart';

/// All Firestore access for site units (one apartment inside a
/// site). Mirrors [StageService]: the service owns the writes,
/// providers and screens read through it.
///
/// Queries are single-field (`where('siteId', ...)`) and the
/// ordering happens in Dart (order, then id) on purpose — it
/// keeps the queries simple and needs no composite index, the
/// same pattern as the notifications and chat queries.
class UnitService {
  final FirebaseFirestore _db;
  UnitService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _units =>
      _db.collection('units');

  /// Every unit, ordered by (order, id) in Dart.
  Stream<List<Unit>> watchAllUnits() {
    return _units.snapshots().map((snap) {
      final list = snap.docs.map(Unit.fromFirestore).toList();
      list.sort(_byOrder);
      return list;
    });
  }

  /// One site's units, ordered by (order, id) in Dart.
  Stream<List<Unit>> watchUnitsForSite(String siteId) {
    return _units
        .where('siteId', isEqualTo: siteId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(Unit.fromFirestore).toList();
      list.sort(_byOrder);
      return list;
    });
  }

  static int _byOrder(Unit a, Unit b) {
    final o = a.order.compareTo(b.order);
    if (o != 0) return o;
    return a.id.compareTo(b.id);
  }

  Future<String> createUnit({
    required String siteId,
    required String name,
    required int order,
  }) async {
    final ref = await _units.add(Unit(
      id: '',
      siteId: siteId,
      name: name,
      order: order,
    ).toMap());
    return ref.id;
  }

  Future<void> updateUnit(Unit unit) {
    return _units.doc(unit.id).update(unit.toMap());
  }

  /// Deletes a unit and clears its unitId from every task that
  /// belonged to it, so the tasks stay on the site as ordinary
  /// site-level tasks instead of pointing at a deleted unit.
  /// Its roadmap goes too: the unit's stages are deleted and
  /// their tasks keep their unit cleared and their stageId
  /// cleared, so nothing points at a deleted stage either.
  /// One batch for the unit itself — a unit's task count is
  /// small; the roadmap deletion chunks its own writes.
  Future<void> deleteUnit(String id) async {
    final unitSnap = await _units.doc(id).get();
    final siteId = unitSnap.data()?['siteId'] as String? ?? '';
    if (siteId.isNotEmpty) {
      await StageService(db: _db).deleteRoadmap(siteId, unitId: id);
    }
    final tasks = await _db
        .collection('tasks')
        .where('unitId', isEqualTo: id)
        .get();
    final batch = _db.batch();
    batch.delete(_units.doc(id));
    for (final doc in tasks.docs) {
      batch.update(doc.reference, {'unitId': null});
    }
    await batch.commit();
  }
}
