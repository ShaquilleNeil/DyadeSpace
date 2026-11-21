import 'package:cloud_firestore/cloud_firestore.dart';

/// A worker's request for materials: what they need, how much,
/// where, and by when. Flow, in order:
///   requested -> approved -> onRun -> delivered
///   requested -> denied (terminal)
/// A request never becomes a task and never joins a run by
/// itself: a manager attaches it to a delivery run as a pickup
/// stop, and completing that stop marks it delivered (see
/// notifyStopCompleted in functions/index.js).
enum MaterialRequestStatus { requested, approved, onRun, delivered, denied }

class MaterialRequest {
  final String id;

  /// Who asked, and their name at request time (names change;
  /// the stored name is what the queue shows).
  final String requesterId;
  final String requesterName;

  /// Where the materials are needed. taskId is null for a
  /// site-level request (made from the site screen).
  final String siteId;
  final String? taskId;

  final String item;
  final int quantity;

  /// "Needed by" date, day only; null means no date given.
  final DateTime? neededBy;

  final String note;
  final String? photoUrl;
  final MaterialRequestStatus status;

  /// Why a manager refused it; only set when denied.
  final String? denyReason;

  /// The run the request is riding on (null until attached).
  /// No stopId is stored: stops are renumbered and carried
  /// over, so a stored stop id would go stale; the link back
  /// lives on the stop (RunStop.materialRequestId).
  final String? runId;

  final DateTime? createdAt;

  const MaterialRequest({
    required this.id,
    required this.requesterId,
    required this.requesterName,
    required this.siteId,
    this.taskId,
    required this.item,
    this.quantity = 1,
    this.neededBy,
    this.note = '',
    this.photoUrl,
    this.status = MaterialRequestStatus.requested,
    this.denyReason,
    this.runId,
    this.createdAt,
  });

  /// Open work for the managers: waiting on a decision, or
  /// approved and waiting for a run.
  bool get isOpen =>
      status == MaterialRequestStatus.requested ||
      status == MaterialRequestStatus.approved;

  MaterialRequest copyWith({
    MaterialRequestStatus? status,
    String? denyReason,
    String? runId,
  }) {
    return MaterialRequest(
      id: id,
      requesterId: requesterId,
      requesterName: requesterName,
      siteId: siteId,
      taskId: taskId,
      item: item,
      quantity: quantity,
      neededBy: neededBy,
      note: note,
      photoUrl: photoUrl,
      status: status ?? this.status,
      denyReason: denyReason ?? this.denyReason,
      runId: runId ?? this.runId,
      createdAt: createdAt,
    );
  }

  factory MaterialRequest.fromFirestore(DocumentSnapshot doc) {
    return MaterialRequest.fromMap(
        doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory MaterialRequest.fromMap(String id, Map<String, dynamic> map) {
    return MaterialRequest(
      id: id,
      requesterId: map['requesterId'] as String? ?? '',
      requesterName: map['requesterName'] as String? ?? '',
      siteId: map['siteId'] as String? ?? '',
      taskId: map['taskId'] as String?,
      item: map['item'] as String? ?? '',
      quantity: (map['quantity'] as num?)?.toInt() ?? 1,
      neededBy: map['neededBy'] is Timestamp
          ? (map['neededBy'] as Timestamp).toDate()
          : null,
      note: map['note'] as String? ?? '',
      photoUrl: map['photoUrl'] as String?,
      status: MaterialRequestStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => MaterialRequestStatus.requested,
      ),
      denyReason: map['denyReason'] as String?,
      runId: map['runId'] as String?,
      createdAt: map['createdAt'] is Timestamp
          ? (map['createdAt'] as Timestamp).toDate()
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'requesterId': requesterId,
      'requesterName': requesterName,
      'siteId': siteId,
      'taskId': taskId,
      'item': item,
      'quantity': quantity,
      'neededBy': neededBy == null ? null : Timestamp.fromDate(neededBy!),
      'note': note,
      'photoUrl': photoUrl,
      'status': status.name,
      'denyReason': denyReason,
      'runId': runId,
      'createdAt':
          createdAt == null ? null : Timestamp.fromDate(createdAt!),
    };
  }
}
