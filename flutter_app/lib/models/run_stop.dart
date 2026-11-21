import 'package:cloud_firestore/cloud_firestore.dart';

/// One stop on a delivery run: either a pickup or a drop-off.
enum StopKind { pickup, dropoff }
enum StopStatus { pending, completed, failed }

/// Fixed "couldn't complete" reason keys. Labels live in
/// app_strings (stopFailReasonLabel) - only the keys are stored.
const List<String> stopFailReasonKeys = [
  'out_of_stock',
  'no_access',
  'wrong_item',
  'nobody_there',
  'other',
];

/// One line on a stop's item checklist (e.g. a counter to load).
class StopItem {
  final String label;
  final bool done;

  const StopItem({required this.label, this.done = false});

  StopItem copyWith({String? label, bool? done}) {
    return StopItem(
      label: label ?? this.label,
      done: done ?? this.done,
    );
  }

  factory StopItem.fromMap(Map<String, dynamic> map) {
    return StopItem(
      label: map['label'] as String? ?? '',
      done: map['done'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'label': label,
      'done': done,
    };
  }
}

class RunStop {
  final String id;
  final int orderIndex;
  final String title;
  final String address;
  final String notes;
  final StopKind kind;
  final StopStatus status;
  final String? photoUrl;

  /// True while the completion photo sits in the on-device
  /// queue (taken offline - see PhotoQueueService). Cleared
  /// when the queued photo lands and [photoUrl] is set.
  final bool photoPending;

  /// When the stop was closed (completed OR failed).
  final DateTime? completedAt;

  /// Optional "be there by" time, stored as 'HH:mm' (24h).
  final String? scheduledTime;

  /// Checklist for this stop. On a pickup the driver must tick
  /// every item before the stop can be marked picked up.
  final List<StopItem> items;

  /// Why the stop could not be completed (a key from
  /// [stopFailReasonKeys]); only set when status is failed.
  final String? failReason;

  /// Free-text detail for a failed stop.
  final String? failNote;

  /// Task this stop serves. Completing a DROP-OFF with a taskId
  /// marks that task's materials as on site.
  final String? taskId;

  /// Material request this stop serves (a pickup the manager
  /// attached from the requests queue or the run builder).
  /// Completing the pickup marks the request delivered (see
  /// notifyStopCompleted in functions/index.js).
  final String? materialRequestId;

  /// When the driver tapped "I'm here" on this stop (null until
  /// they arrive). The arrival push (notifyDriverArrived) fires
  /// on the null -> set transition.
  final DateTime? arrivedAt;

  /// Delay the driver reported, in minutes (15 / 30), with the
  /// time they reported it. The stop stays pending - a delay is
  /// not a failure. Null when never delayed.
  final int? delayedMinutes;
  final DateTime? delayedAt;

  /// Drop-off proof photos, on top of the single completion
  /// photo ([photoUrl]). Encouraged, never a gate: a stop can
  /// be completed without them.
  final List<String> photoUrls;

  /// True when this stop was appended by the auto-join (a driver
  /// task became available) rather than planned by a manager.
  /// Auto-added stops drop off again when their task stops
  /// qualifying (done, reassigned, stage skipped).
  final bool autoAdded;

  /// True when this stop rolled over from an earlier day's run.
  /// Carried stops keep the reason they failed yesterday, if any.
  final bool carriedOver;

  /// Id of the stop this one was carried over from (null for
  /// planned and auto-added stops). Used to de-duplicate
  /// carry-overs so the same stop never lands twice.
  final String? carriedFromStopId;

  const RunStop({
    required this.id,
    required this.orderIndex,
    required this.title,
    this.address = '',
    this.notes = '',
    this.kind = StopKind.dropoff,
    this.status = StopStatus.pending,
    this.photoUrl,
    this.photoPending = false,
    this.completedAt,
    this.scheduledTime,
    this.items = const [],
    this.failReason,
    this.failNote,
    this.taskId,
    this.materialRequestId,
    this.arrivedAt,
    this.delayedMinutes,
    this.delayedAt,
    this.photoUrls = const [],
    this.autoAdded = false,
    this.carriedOver = false,
    this.carriedFromStopId,
  });

  RunStop copyWith({
    int? orderIndex,
    StopStatus? status,
    String? photoUrl,
    bool? photoPending,
    DateTime? completedAt,
    String? scheduledTime,
    List<StopItem>? items,
    String? failReason,
    String? failNote,
    String? taskId,
    String? materialRequestId,
    DateTime? arrivedAt,
    int? delayedMinutes,
    DateTime? delayedAt,
    List<String>? photoUrls,
    bool? autoAdded,
    bool? carriedOver,
    String? carriedFromStopId,
  }) {
    return RunStop(
      id: id,
      orderIndex: orderIndex ?? this.orderIndex,
      title: title,
      address: address,
      notes: notes,
      kind: kind,
      status: status ?? this.status,
      photoUrl: photoUrl ?? this.photoUrl,
      photoPending: photoPending ?? this.photoPending,
      completedAt: completedAt ?? this.completedAt,
      scheduledTime: scheduledTime ?? this.scheduledTime,
      items: items ?? this.items,
      failReason: failReason ?? this.failReason,
      failNote: failNote ?? this.failNote,
      taskId: taskId ?? this.taskId,
      materialRequestId: materialRequestId ?? this.materialRequestId,
      arrivedAt: arrivedAt ?? this.arrivedAt,
      delayedMinutes: delayedMinutes ?? this.delayedMinutes,
      delayedAt: delayedAt ?? this.delayedAt,
      photoUrls: photoUrls ?? this.photoUrls,
      autoAdded: autoAdded ?? this.autoAdded,
      carriedOver: carriedOver ?? this.carriedOver,
      carriedFromStopId: carriedFromStopId ?? this.carriedFromStopId,
    );
  }

  factory RunStop.fromMap(Map<String, dynamic> map) {
    return RunStop(
      id: map['id'] as String? ?? '',
      orderIndex: (map['orderIndex'] as num?)?.toInt() ?? 0,
      title: map['title'] as String? ?? '',
      address: map['address'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      kind: StopKind.values.firstWhere(
        (k) => k.name == map['kind'],
        orElse: () => StopKind.dropoff,
      ),
      status: StopStatus.values.firstWhere(
        (s) => s.name == map['status'],
        orElse: () => StopStatus.pending,
      ),
      photoUrl: map['photoUrl'] as String?,
      photoPending: map['photoPending'] as bool? ?? false,
      completedAt:
          map['completedAt'] is Timestamp ? (map['completedAt'] as Timestamp).toDate() : null,
      scheduledTime: map['scheduledTime'] as String?,
      items: (map['items'] is List ? map['items'] as List : const [])
          .whereType<Map>()
          .map((e) => StopItem.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      failReason: map['failReason'] as String?,
      failNote: map['failNote'] as String?,
      taskId: map['taskId'] as String?,
      materialRequestId: map['materialRequestId'] as String?,
      arrivedAt:
          map['arrivedAt'] is Timestamp ? (map['arrivedAt'] as Timestamp).toDate() : null,
      delayedMinutes: (map['delayedMinutes'] as num?)?.toInt(),
      delayedAt:
          map['delayedAt'] is Timestamp ? (map['delayedAt'] as Timestamp).toDate() : null,
      photoUrls: (map['photoUrls'] is List ? map['photoUrls'] as List : const [])
          .whereType<String>()
          .toList(),
      autoAdded: map['autoAdded'] as bool? ?? false,
      carriedOver: map['carriedOver'] as bool? ?? false,
      carriedFromStopId: map['carriedFromStopId'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'orderIndex': orderIndex,
      'title': title,
      'address': address,
      'notes': notes,
      'kind': kind.name,
      'status': status.name,
      'photoUrl': photoUrl,
      'photoPending': photoPending,
      'completedAt': completedAt == null ? null : Timestamp.fromDate(completedAt!),
      'scheduledTime': scheduledTime,
      'items': items.map((i) => i.toMap()).toList(),
      'failReason': failReason,
      'failNote': failNote,
      'taskId': taskId,
      'materialRequestId': materialRequestId,
      'arrivedAt': arrivedAt == null ? null : Timestamp.fromDate(arrivedAt!),
      'delayedMinutes': delayedMinutes,
      'delayedAt': delayedAt == null ? null : Timestamp.fromDate(delayedAt!),
      'photoUrls': photoUrls,
      'autoAdded': autoAdded,
      'carriedOver': carriedOver,
      'carriedFromStopId': carriedFromStopId,
    };
  }
}
