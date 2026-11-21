import 'package:cloud_firestore/cloud_firestore.dart';

/// Task statuses, matching the Dyade Work Board column names.
enum TaskStatus { todo, inProgress, paused, blocked, toConfirm, done }

/// Why a task was marked Blocked (a reason is required).
enum BlockedReason { waitingMaterials, waitingPerson, noAccess, other }

TaskStatus taskStatusFromString(String? value) {
  return TaskStatus.values.firstWhere(
    (s) => s.name == value,
    orElse: () => TaskStatus.todo,
  );
}

/// Nullable parse for the optional [TaskItem.pausedFrom] field.
TaskStatus? taskStatusOrNull(String? value) {
  if (value == null) return null;
  for (final s in TaskStatus.values) {
    if (s.name == value) return s;
  }
  return null;
}

BlockedReason? blockedReasonFromString(String? value) {
  if (value == null) return null;
  for (final r in BlockedReason.values) {
    if (r.name == value) return r;
  }
  return null;
}

DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : null;

class TaskItem {
  final String id;
  final String title;
  final String siteId;
  final String unit;

  /// Everyone assigned to this task. Empty = unassigned.
  /// Old docs carry the single `assigneeId` string instead —
  /// [fromMap] reads that as a one-person list, so no migration
  /// and no rewrite of existing docs is needed. [toMap] writes
  /// only the list.
  final List<String> assigneeIds;
  final String createdBy;
  final TaskStatus status;

  /// The status the task had before it was paused (null when never
  /// paused). Resume restores it; defaults to todo when absent.
  final TaskStatus? pausedFrom;
  final DateTime? dueDate;

  /// Optional planned start. With a due date it makes the task
  /// multi-day: it shows in My Day / Today for the whole window
  /// from start through due.
  final DateTime? startDate;
  final String notes;

  /// Materials that should be on site before this task starts.
  final List<String> materials;

  /// Labels of [materials] the crew has ticked off on the task
  /// detail screen. Stored as labels (not indices) so the
  /// checks survive a materials-list edit; labels that are no
  /// longer on the list simply never match. Persisted to
  /// Firestore on every toggle (see TaskScreen._toggleMaterial).
  final List<String> materialsChecked;

  /// Set true when a delivery drop-off linked to this task is
  /// completed (see RunStop.taskId): the materials have arrived.
  final bool materialsOnSite;

  /// If set, this task stays locked until that task is Done -
  /// unless [dependsSoft] is true.
  final String? dependsOnTaskId;

  /// If set, this task belongs to a roadmap stage of its site.
  /// It stays locked until the stage is Active (started by an
  /// admin) — see [StageIndex]. Null = ordinary task, no stage.
  final String? stageId;

  /// If set, this task belongs to a unit (apartment) of its
  /// site — see [Unit]. A unit is a grouping only: it never
  /// locks the task and never hides it from My Day / Today /
  /// Board. Null = ordinary site-level task, no unit.

  final String? unitId;

  /// Soft link: the task still draws in the chain after its
  /// predecessor, but it may be started before the predecessor is
  /// Done (site prep that can begin while the previous step
  /// finishes). Never locks.
  final bool dependsSoft;

  /// When true (default), marking Done requires at least one photo.
  final bool photoRequired;
  final BlockedReason? blockedReason;
  final String blockedNote;
  final List<String> photoUrls;

  /// True while a completion photo sits in the on-device queue
  /// (taken offline - see PhotoQueueService). Cleared when the
  /// queued photo lands and its URL is appended to [photoUrls].
  final bool photoPending;
  final DateTime? createdAt;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  const TaskItem({
    required this.id,
    required this.title,
    required this.siteId,
    this.unit = '',
    this.assigneeIds = const [],
    required this.createdBy,
    this.status = TaskStatus.todo,
    this.pausedFrom,
    this.dueDate,
    this.startDate,
    this.notes = '',
    this.materials = const [],
    this.materialsChecked = const [],
    this.materialsOnSite = false,
    this.dependsOnTaskId,
    this.stageId,
    this.unitId,
    this.dependsSoft = false,
    this.photoRequired = true,
    this.blockedReason,
    this.blockedNote = '',
    this.photoUrls = const [],
    this.photoPending = false,
    this.createdAt,
    this.startedAt,
    this.finishedAt,
  });

  /// Overdue = not Done and the due date has passed (checked in Dart,
  /// per the spec, instead of a composite Firestore query).
  bool get isOverdue {
    if (status == TaskStatus.done || dueDate == null) return false;
    final now = DateTime.now();
    final endOfDueDay =
        DateTime(dueDate!.year, dueDate!.month, dueDate!.day, 23, 59, 59);
    return now.isAfter(endOfDueDay);
  }

  /// A task is locked while its dependency exists and is not
  /// Done. A soft link never locks.
  bool isLocked(TaskItem? dependency) {
    if (dependsOnTaskId == null || dependsSoft) return false;
    if (dependency == null) return true; // dependency missing: stay locked
    return dependency.status != TaskStatus.done;
  }

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Total days in the planned window (start..due) when the task
  /// spans more than one day; otherwise null.
  int? get spanTotalDays {
    if (startDate == null || dueDate == null) return null;
    final total =
        _dayOnly(dueDate!).difference(_dayOnly(startDate!)).inDays + 1;
    return total > 1 ? total : null;
  }

  /// Which day of the window today is (1-based), or null when
  /// today is outside a multi-day window.
  int? get spanDayIndex {
    final total = spanTotalDays;
    if (total == null) return null;
    final idx = _dayOnly(DateTime.now())
            .difference(_dayOnly(startDate!))
            .inDays +
        1;
    if (idx < 1 || idx > total) return null;
    return idx;
  }

  /// Rolled in from an earlier day and still open: overdue, or
  /// started on a previous day and not finished.
  bool get carriedOver {
    if (status == TaskStatus.done) return false;
    if (isOverdue) return true;
    return startedAt != null &&
        _dayOnly(startedAt!).isBefore(_dayOnly(DateTime.now()));
  }

  /// True when at least one person is assigned.
  bool get isAssigned => assigneeIds.isNotEmpty;

  /// True when [uid] is one of this task's assignees.
  bool assignedTo(String uid) => assigneeIds.contains(uid);

  TaskItem copyWith({
    TaskStatus? status,
    TaskStatus? pausedFrom,
    String? title,
    String? siteId,
    String? unit,
    List<String>? assigneeIds,
    DateTime? dueDate,
    DateTime? startDate,
    String? notes,
    List<String>? materials,
    List<String>? materialsChecked,
    bool? materialsOnSite,
    String? dependsOnTaskId,
    String? stageId,
    String? unitId,
    bool? dependsSoft,
    bool? photoRequired,
    BlockedReason? blockedReason,
    String? blockedNote,
    List<String>? photoUrls,
    bool? photoPending,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) {
    return TaskItem(
      id: id,
      title: title ?? this.title,
      siteId: siteId ?? this.siteId,
      unit: unit ?? this.unit,
      assigneeIds: assigneeIds ?? this.assigneeIds,
      createdBy: createdBy,
      status: status ?? this.status,
      pausedFrom: pausedFrom ?? this.pausedFrom,
      dueDate: dueDate ?? this.dueDate,
      startDate: startDate ?? this.startDate,
      notes: notes ?? this.notes,
      materials: materials ?? this.materials,
      materialsChecked: materialsChecked ?? this.materialsChecked,
      materialsOnSite: materialsOnSite ?? this.materialsOnSite,
      dependsOnTaskId: dependsOnTaskId ?? this.dependsOnTaskId,
      stageId: stageId ?? this.stageId,
      unitId: unitId ?? this.unitId,
      dependsSoft: dependsSoft ?? this.dependsSoft,
      photoRequired: photoRequired ?? this.photoRequired,
      blockedReason: blockedReason ?? this.blockedReason,
      blockedNote: blockedNote ?? this.blockedNote,
      photoUrls: photoUrls ?? this.photoUrls,
      photoPending: photoPending ?? this.photoPending,
      createdAt: createdAt,
      startedAt: startedAt ?? this.startedAt,
      finishedAt: finishedAt ?? this.finishedAt,
    );
  }

  factory TaskItem.fromFirestore(DocumentSnapshot doc) {
    return TaskItem.fromMap(doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  /// Reads the new `assigneeIds` list when present; an old doc
  /// with only the single `assigneeId` string loads as a
  /// one-person list; a doc with neither loads as unassigned.
  static List<String> _assigneeIdsFromMap(Map<String, dynamic> map) {
    final list = map['assigneeIds'];
    if (list is List) {
      return list
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toList();
    }
    final single = map['assigneeId'];
    if (single is String && single.isNotEmpty) return [single];
    return [];
  }

  /// Tolerant string-list parse: a single malformed element (a
  /// number, a map, null) must never fail the whole doc — the
  /// bad element is dropped and the rest load. A non-list value
  /// loads as empty. (Audit 2026-11-21: `List<String>.from`
  /// threw on one bad element and broke the entire board stream.)
  static List<String> _stringList(dynamic value) {
    if (value is! List) return const [];
    return value.whereType<String>().toList();
  }

  factory TaskItem.fromMap(String id, Map<String, dynamic> map) {
    return TaskItem(
      id: id,
      title: map['title'] as String? ?? '',
      siteId: map['siteId'] as String? ?? '',
      unit: map['unit'] as String? ?? '',
      assigneeIds: _assigneeIdsFromMap(map),
      createdBy: map['createdBy'] as String? ?? '',
      status: taskStatusFromString(map['status'] as String?),
      pausedFrom: taskStatusOrNull(map['pausedFrom'] as String?),
      dueDate: _date(map['dueDate']),
      startDate: _date(map['startDate']),
      notes: map['notes'] as String? ?? '',
      materials: _stringList(map['materials']),
      materialsChecked: _stringList(map['materialsChecked']),
      materialsOnSite: map['materialsOnSite'] as bool? ?? false,
      dependsOnTaskId: map['dependsOnTaskId'] as String?,
      stageId: map['stageId'] as String?,
      unitId: map['unitId'] as String?,
      dependsSoft: map['dependsSoft'] as bool? ?? false,
      photoRequired: map['photoRequired'] as bool? ?? true,
      blockedReason: blockedReasonFromString(map['blockedReason'] as String?),
      blockedNote: map['blockedNote'] as String? ?? '',
      photoUrls: _stringList(map['photoUrls']),
      photoPending: map['photoPending'] as bool? ?? false,
      createdAt: _date(map['createdAt']),
      startedAt: _date(map['startedAt']),
      finishedAt: _date(map['finishedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'siteId': siteId,
      'unit': unit,
      'assigneeIds': assigneeIds,
      'createdBy': createdBy,
      'status': status.name,
      'pausedFrom': pausedFrom?.name,
      'dueDate': dueDate == null ? null : Timestamp.fromDate(dueDate!),
      'startDate': startDate == null ? null : Timestamp.fromDate(startDate!),
      'notes': notes,
      'materials': materials,
      'materialsChecked': materialsChecked,
      'materialsOnSite': materialsOnSite,
      'dependsOnTaskId': dependsOnTaskId,
      'stageId': stageId,
      'unitId': unitId,
      'dependsSoft': dependsSoft,
      'photoRequired': photoRequired,
      'blockedReason': blockedReason?.name,
      'blockedNote': blockedNote,
      'photoUrls': photoUrls,
      'photoPending': photoPending,
      'createdAt':
          createdAt == null ? FieldValue.serverTimestamp() : Timestamp.fromDate(createdAt!),
      'startedAt': startedAt == null ? null : Timestamp.fromDate(startedAt!),
      'finishedAt': finishedAt == null ? null : Timestamp.fromDate(finishedAt!),
    };
  }
}
