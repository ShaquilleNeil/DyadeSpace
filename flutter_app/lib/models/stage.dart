import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import 'task_item.dart';

/// Roadmap stage statuses. The status is derived, never stored
/// (see [StageIndex.statusOf]).
enum StageStatus { completed, inProgress, ready, locked, skipped }

/// Colour for a stage status, matching the roadmap concept:
/// green when done, blue while in progress, blue when ready to
/// start, grey while locked or skipped. Resolved in the current
/// theme via [colors] so the dot reads on light and dark.
Color stageStatusColor(StageStatus status, AppColors colors) {
  switch (status) {
    case StageStatus.completed:
      return colors.statusDone;
    case StageStatus.inProgress:
      return colors.statusInProgress;
    case StageStatus.ready:
      return colors.accent;
    case StageStatus.locked:
      return colors.statusTodo;
    case StageStatus.skipped:
      return colors.textTertiary;
  }
}

DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : null;

/// One step of a roadmap: a named stage in a fixed order.
/// Stored in the top-level `stages` collection. A site has a
/// roadmap iff it has at least one stage with no `unitId`; a
/// unit has a roadmap iff it has at least one stage with its
/// `unitId`. Site stages and unit stages live in the same
/// collection but never mix: a stage belongs to one roadmap
/// or the other, and every lookup below is scoped that way.
///
/// No status is stored on the doc: it is derived from the
/// stage's tasks and its neighbours (see [StageIndex.statusOf]).
/// An admin starts a stage ([startedAt]) and may skip it
/// ([skipped]). Starting a stage is what brings its tasks up
/// for the people assigned to them.
class Stage {
  final String id;
  final String siteId;

  /// Null = site roadmap; set = this unit's roadmap.
  final String? unitId;
  final String name;

  /// 1-based position in its roadmap (Stage 1, Stage 2…).
  final int order;
  final DateTime? startedAt;
  final bool skipped;

  const Stage({
    required this.id,
    required this.siteId,
    this.unitId,
    required this.name,
    this.order = 0,
    this.startedAt,
    this.skipped = false,
  });

  factory Stage.fromFirestore(DocumentSnapshot doc) {
    return Stage.fromMap(doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory Stage.fromMap(String id, Map<String, dynamic> map) {
    return Stage(
      id: id,
      siteId: map['siteId'] as String? ?? '',
      unitId: map['unitId'] as String?,
      name: map['name'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      startedAt: _date(map['startedAt']),
      skipped: map['skipped'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'siteId': siteId,
      'unitId': unitId,
      'name': name,
      'order': order,
      'startedAt': startedAt == null ? null : Timestamp.fromDate(startedAt!),
      'skipped': skipped,
    };
  }

  Stage copyWith({
    String? name,
    int? order,
    DateTime? startedAt,
    bool? skipped,
  }) {
    return Stage(
      id: id,
      siteId: siteId,
      unitId: unitId,
      name: name ?? this.name,
      order: order ?? this.order,
      startedAt: startedAt ?? this.startedAt,
      skipped: skipped ?? this.skipped,
    );
  }
}

/// Roadmap state, computed in Dart from the stage docs and the
/// task list — mirroring [ChainIndex]. All stage rules live here
/// so every screen (Board, Today, My Day, site view, detail)
/// agrees on locks and visibility.
class StageIndex {
  /// All stages, sorted by (siteId, unitId, order, id).
  final List<Stage> stages;
  final Map<String, Stage> byId;

  /// Site roadmaps only: stages with no `unitId`, per site.
  final Map<String, List<Stage>> stagesBySite;

  /// Unit roadmaps: stages with a `unitId`, per unit.
  final Map<String, List<Stage>> stagesByUnit;
  final Map<String, List<TaskItem>> tasksByStage;

  /// True when the stage/task streams have not both loaded
  /// yet: the index knows nothing about any stage, so every
  /// staged task reads as locked (unknown = locked) while its
  /// visibility is left alone — a task must never vanish from
  /// Today or drop off a run just because the stages stream
  /// is still loading. See [stageIndexProvider].
  final bool isLoading;

  const StageIndex._(this.stages, this.byId, this.stagesBySite,
      this.stagesByUnit, this.tasksByStage,
      [this.isLoading = false]);

  /// The loading sentinel: no stages known, no tasks indexed.
  /// [isLockedByStage] locks any staged task, [isVisibleToday]
  /// stays true, everything else reads empty.
  factory StageIndex.loading() => const StageIndex._(
      [], {}, {}, {}, {}, true);

  factory StageIndex.from(List<Stage> stages, List<TaskItem> tasks) {
    final sorted = [...stages]
      ..sort((a, b) {
        final c = a.siteId.compareTo(b.siteId);
        if (c != 0) return c;
        final u = (a.unitId ?? '').compareTo(b.unitId ?? '');
        if (u != 0) return u;
        final o = a.order.compareTo(b.order);
        if (o != 0) return o;
        return a.id.compareTo(b.id);
      });
    final byId = {for (final s in sorted) s.id: s};
    final stagesBySite = <String, List<Stage>>{};
    final stagesByUnit = <String, List<Stage>>{};
    for (final s in sorted) {
      if (s.unitId == null) {
        stagesBySite.putIfAbsent(s.siteId, () => []).add(s);
      } else {
        stagesByUnit.putIfAbsent(s.unitId!, () => []).add(s);
      }
    }
    final tasksByStage = <String, List<TaskItem>>{};
    for (final t in tasks) {
      final sid = t.stageId;
      if (sid == null) continue;
      tasksByStage.putIfAbsent(sid, () => []).add(t);
    }
    return StageIndex._(sorted, byId, stagesBySite, stagesByUnit, tasksByStage);
  }

  /// A site's roadmap stages only — unit stages never leak in.
  List<Stage> stagesForSite(String siteId) =>
      stagesBySite[siteId] ?? const [];

  /// One unit's roadmap stages, in order.
  List<Stage> stagesForUnit(String unitId) =>
      stagesByUnit[unitId] ?? const [];

  /// The stages of the scope a stage belongs to: its unit's
  /// roadmap when it has a `unitId`, the site's roadmap
  /// otherwise. Status, locks and visibility are always
  /// evaluated inside one scope, never across scopes.
  List<Stage> stagesInScopeOf(Stage stage) => stage.unitId != null
      ? stagesForUnit(stage.unitId!)
      : stagesForSite(stage.siteId);

  /// The stage a site is currently on: the first stage in
  /// roadmap order that is neither completed nor skipped — the
  /// one in progress, or the next one ready to start. Skipped
  /// stages are passed over. A locked stage can never be
  /// current: a not-yet-complete stage always stands before it
  /// (a stage only locks while its predecessor is unfinished).
  /// When every stage is completed or skipped, the last stage
  /// is returned so the site still shows its finished roadmap
  /// (at 100% when completed) instead of looking roadmap-less.
  /// Null only when the site has no stages at all.
  Stage? currentStageForSite(String siteId) {
    final list = stagesForSite(siteId);
    if (list.isEmpty) return null;
    for (final stage in list) {
      if (stage.skipped) continue;
      if (statusOf(stage) == StageStatus.completed) continue;
      return stage;
    }
    return list.last;
  }

  Stage? stageOf(TaskItem task) {
    if (isLoading) return null;
    return task.stageId == null ? null : byId[task.stageId];
  }

  List<TaskItem> tasksOf(Stage stage) => tasksByStage[stage.id] ?? const [];

  /// The stage directly before [stage] in its own roadmap's
  /// order (same unit, or the site when it has no unit), or
  /// null when it is the first.
  Stage? previousStage(Stage stage) {
    final list = stagesInScopeOf(stage);
    final i = list.indexWhere((s) => s.id == stage.id);
    return i > 0 ? list[i - 1] : null;
  }

  /// (done, total) for a stage. Only [TaskStatus.done] counts —
  /// a task waiting for confirmation does not.
  ({int done, int total}) progressOf(Stage stage) {
    final ts = tasksOf(stage);
    return (
      done: ts.where((t) => t.status == TaskStatus.done).length,
      total: ts.length,
    );
  }

  double fractionOf(Stage stage) {
    final p = progressOf(stage);
    return p.total == 0 ? 0.0 : p.done / p.total;
  }

  /// Derived status:
  /// - Skipped when skipped == true.
  /// - Completed when it has tasks and all of them are Done.
  ///   A stage with 0 tasks is 0% and never completes.
  /// - In progress when started.
  /// - Ready when it is the first stage, or the previous stage
  ///   is Completed or Skipped.
  /// - Locked otherwise.
  StageStatus statusOf(Stage stage) {
    // Loading sentinel: no stage is known, so any stage handed
    // in reads as locked (unknown = locked).
    if (isLoading) return StageStatus.locked;
    if (stage.skipped) return StageStatus.skipped;
    final p = progressOf(stage);
    if (p.total > 0 && p.done == p.total) return StageStatus.completed;
    if (stage.startedAt != null) return StageStatus.inProgress;
    final prev = previousStage(stage);
    if (prev == null) return StageStatus.ready;
    final ps = statusOf(prev);
    if (ps == StageStatus.completed || ps == StageStatus.skipped) {
      return StageStatus.ready;
    }
    return StageStatus.locked;
  }

  /// A task is locked by its stage while the stage is Locked,
  /// Ready (not started yet) or Skipped. Tasks in an Active or
  /// Completed stage — or with no stage — are not locked here.
  /// This combines with the chain lock (OR) wherever a task's
  /// locked state is computed. While the index is still loading
  /// ([isLoading]) every staged task reads as locked: the stage
  /// might be dormant, and starting a task that turns out to be
  /// locked is worse than waiting for the streams to land.
  bool isLockedByStage(TaskItem task) {
    if (isLoading) return task.stageId != null;
    final stage = stageOf(task);
    if (stage == null) return false;
    final status = statusOf(stage);
    return status == StageStatus.locked ||
        status == StageStatus.ready ||
        status == StageStatus.skipped;
  }

  /// A task counts as today's work only when its stage is Active
  /// or Completed (or it has no stage). Tasks in a dormant stage
  /// stay out of My Day / Today and out of the who's-where crew.
  /// While the index is still loading ([isLoading]) everything
  /// stays visible: hiding tasks on an unknown stage would drop
  /// them from Today and from run carry-over on a guess.
  bool isVisibleToday(TaskItem task) {
    if (isLoading) return true;
    final stage = stageOf(task);
    if (stage == null) return true;
    final status = statusOf(stage);
    return status == StageStatus.inProgress ||
        status == StageStatus.completed;
  }
}
