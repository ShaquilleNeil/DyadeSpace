import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/delivery_run.dart';
import '../models/material_request.dart';
import '../models/run_stop.dart';

/// All Firestore access for material requests. Queries stay
/// simple on purpose (spec): filtering and sorting are done in
/// Dart, so no composite indexes are needed at this crew size.
///
/// Status moves are one-way and enforced by firestore.rules;
/// this service only writes the transitions the UI offers:
/// requested -> approved / denied (manager), approved -> onRun
/// (manager, when the request is attached to a run). The
/// onRun -> delivered transition is done by the Cloud Function
/// (notifyStopCompleted) when the driver completes the pickup
/// stop — never by the client — so the delivered push and the
/// status change can never drift apart.
class MaterialRequestService {
  final FirebaseFirestore _db;
  MaterialRequestService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _requests =>
      _db.collection('materialRequests');

  /// Every request, newest first. The queue screen filters in
  /// Dart by status.
  Stream<List<MaterialRequest>> watchAllRequests() {
    return _requests
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map(MaterialRequest.fromFirestore).toList());
  }

  /// Approved requests not on a run yet. Filtered in Dart on
  /// top of watchAllRequests on purpose — a where('status')
  /// + orderBy('createdAt') query would need a composite index.
  Stream<List<MaterialRequest>> watchApprovedRequests() {
    return watchAllRequests().map((list) => list
        .where((r) => r.status == MaterialRequestStatus.approved)
        .toList());
  }

  /// The request's `createdAt` always comes from the server
  /// clock: the client clock may be wrong, and the queue sorts
  /// on this field. The caller's value is ignored.
  Future<String> createRequest(MaterialRequest request) async {
    final data = request.toMap()..['createdAt'] = FieldValue.serverTimestamp();
    final ref = await _requests.add(data);
    return ref.id;
  }

  /// Creates the request under a pre-chosen id, so a photo can
  /// be uploaded into requestPhotos/<id> before the doc exists.
  /// `createdAt` is the server timestamp (see [createRequest]).
  Future<void> createRequestWithId(MaterialRequest request) {
    final data = request.toMap()..['createdAt'] = FieldValue.serverTimestamp();
    return _requests.doc(request.id).set(data);
  }

  Future<void> approve(MaterialRequest request) {
    return _requests
        .doc(request.id)
        .update({'status': MaterialRequestStatus.approved.name});
  }

  Future<void> deny(MaterialRequest request, String reason) {
    return _requests.doc(request.id).update({
      'status': MaterialRequestStatus.denied.name,
      'denyReason': reason,
    });
  }

  /// Deletes the request entirely. Rules enforce who may do
  /// this: admins/managers any request, the requester only
  /// their own still-requested one. Deleting never touches
  /// the run: if a request-linked stop later completes,
  /// notifyStopCompleted skips the delivered update when the
  /// doc is gone.
  Future<void> deleteRequest(String id) {
    return _requests.doc(id).delete();
  }

  /// Attach an approved request to a run as a pickup stop.
  /// The append runs in a transaction against the fresh run
  /// doc, and the request is re-read inside it: the attach
  /// only lands when the request is still `approved`. Two
  /// near-simultaneous attaches can no longer overwrite each
  /// other, and a denied (or already attached) request can no
  /// longer flip back to onRun. Throws [StateError] when the
  /// request is not approved (or is gone) or the run is gone.
  /// The stop's address stays empty — the pickup point is the
  /// supplier, which the manager fills in (run builder) or the
  /// driver knows; the destination site and requester travel in
  /// the notes and on the stop's request line.
  Future<void> attachToRun({
    required MaterialRequest request,
    required DeliveryRun run,
    required String siteName,
  }) async {
    final runRef = _db.collection('runs').doc(run.id);
    final requestRef = _requests.doc(request.id);
    await _db.runTransaction((tx) async {
      final runSnap = await tx.get(runRef);
      if (!runSnap.exists) {
        throw StateError('run-not-found');
      }
      final requestSnap = await tx.get(requestRef);
      final status = requestSnap.data()?['status'] as String?;
      if (status != MaterialRequestStatus.approved.name) {
        throw StateError('request-not-approved');
      }
      final freshRun = DeliveryRun.fromFirestore(runSnap);
      final stop = RunStop(
        id: _db.collection('runs').doc().id,
        orderIndex: freshRun.stops.length,
        title: request.item,
        address: '',
        notes: [
          if (siteName.isNotEmpty) siteName,
          request.requesterName,
          if (request.note.isNotEmpty) request.note,
        ].join(' · '),
        kind: StopKind.pickup,
        status: StopStatus.pending,
        items: [StopItem(label: '${request.quantity} × ${request.item}')],
        materialRequestId: request.id,
      );
      tx.update(runRef, {
        'stops': [...freshRun.stops, stop].map((s) => s.toMap()).toList(),
      });
      tx.update(requestRef, {
        'status': MaterialRequestStatus.onRun.name,
        'runId': run.id,
      });
    });
  }

  /// A request whose stop was saved in the run builder moves to
  /// onRun with the run id. Transactional: the move only lands
  /// when the request is still approved — a concurrent deny or
  /// attach cannot be overwritten. Throws [StateError] when
  /// the request is no longer approved.
  Future<void> markOnRun(MaterialRequest request, String runId) async {
    final ref = _requests.doc(request.id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if ((snap.data()?['status'] as String?) !=
          MaterialRequestStatus.approved.name) {
        throw StateError('request-not-approved');
      }
      tx.update(ref, {
        'status': MaterialRequestStatus.onRun.name,
        'runId': runId,
      });
    });
  }

  /// A request whose stop was removed from a run goes back to
  /// approved, waiting for a run again. Transactional: the
  /// revert only lands when the request is still onRun on that
  /// run — a concurrent re-attach cannot be undone.
  Future<void> revertToApproved(MaterialRequest request) async {
    final ref = _requests.doc(request.id);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final data = snap.data();
      if ((data?['status'] as String?) !=
              MaterialRequestStatus.onRun.name ||
          (data?['runId'] as String?) != request.runId) {
        throw StateError('request-not-on-run');
      }
      tx.update(ref, {
        'status': MaterialRequestStatus.approved.name,
        'runId': null,
      });
    });
  }
}
