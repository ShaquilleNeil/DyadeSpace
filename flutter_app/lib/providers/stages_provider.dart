import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/roadmap_template.dart';
import '../models/stage.dart';
import '../services/stage_service.dart';
import 'auth_provider.dart';
import 'tasks_provider.dart';

final stageServiceProvider = Provider<StageService>((ref) => StageService());

/// All saved roadmap templates, by name. Gated on sign-in,
/// same pattern as [allStagesProvider].
final roadmapTemplatesProvider =
    StreamProvider<List<RoadmapTemplate>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(stageServiceProvider).watchTemplates();
});

/// All stages, ordered by `order`. Gated on sign-in so signing
/// out does not surface permission-denied errors — same pattern
/// as [teamsProvider].
final allStagesProvider = StreamProvider<List<Stage>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(stageServiceProvider).watchAllStages();
});

/// One site's stages, in roadmap order. Family provider.
final stagesForSiteProvider =
    StreamProvider.family<List<Stage>, String>((ref, siteId) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(stageServiceProvider).watchStagesForSite(siteId);
});

/// One unit's roadmap stages, in roadmap order. Family provider.
final stagesForUnitProvider =
    StreamProvider.family<List<Stage>, String>((ref, unitId) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.watch(stageServiceProvider).watchStagesForUnit(unitId);
});

/// The computed roadmap state for the whole app (stages +
/// tasks). Null only while NEITHER stream has loaded yet —
/// screens show their skeletons then. As soon as one stream
/// lands, the loading sentinel ([StageIndex.loading]) is
/// returned instead of null: staged tasks read as locked
/// (unknown = locked) while the other stream is still loading,
/// so a Start button can never fire on a task whose stage
/// turns out to be dormant — but nothing is hidden, so tasks
/// never vanish from Today or drop off a run on a guess. Once
/// both streams land, the real index replaces the sentinel.
final stageIndexProvider = Provider<StageIndex?>((ref) {
  final stages = ref.watch(allStagesProvider).valueOrNull;
  final tasks = ref.watch(allTasksProvider).valueOrNull;
  if (stages == null && tasks == null) return null;
  if (stages == null || tasks == null) return StageIndex.loading();
  return StageIndex.from(stages, tasks);
});
