import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../l10n/app_strings.dart';
import '../models/app_user.dart';
import '../models/pending_task_update.dart';
import '../models/task_item.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/photo_queue_provider.dart'
    if (dart.library.js_interop) '../providers/photo_queue_provider_web.dart';
import '../providers/sites_provider.dart';
import '../providers/stages_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/units_provider.dart';
import '../theme/app_theme.dart';
import '../theme/app_tokens.dart';
import '../widgets/app_date_field.dart';
import '../widgets/assignee_picker.dart';
import '../widgets/material_request_form.dart';
import '../widgets/member_tile.dart';
import '../widgets/pending_photo_thumbnail.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/primary_button.dart';
import '../widgets/section_label.dart';
import '../widgets/status_indicator.dart';
import '../widgets/task_card.dart';
import '../widgets/task_chain.dart';

/// Can [viewer] act on [task] (start it, close it, block it)?
/// The assignee can, and so can any admin/manager. Everyone
/// else - a driver opening a task linked from a run stop, a
/// worker opening a chain step that belongs to someone else -
/// gets the read-only view: Firestore rules would refuse their
/// task writes anyway. Posting to the task's Updates thread is
/// NOT covered by this: any signed-in user may post as
/// themselves, so the thread stays open in read-only mode.
bool taskEditableBy(TaskItem task, AppUser? viewer) {
  if (viewer == null) return false;
  return task.assigneeIds.contains(viewer.id) || viewer.isAdminOrManager;
}

/// All tasks that (transitively) depend on [taskId] — the
/// descendants that must never be offered as this task's own
/// "Starts after": pointing at one closes a dependency cycle
/// and deadlocks both tasks forever. A cycle already in the
/// data ends the walk instead of looping forever.
Set<String> taskDescendantIds(String taskId, List<TaskItem> all) {
  final byId = {for (final t in all) t.id: t};
  final children = <String, List<String>>{};
  for (final t in all) {
    final dep = t.dependsOnTaskId;
    if (dep != null && byId.containsKey(dep)) {
      children.putIfAbsent(dep, () => []).add(t.id);
    }
  }
  final out = <String>{};
  final queue = [...children[taskId] ?? const <String>[]];
  while (queue.isNotEmpty) {
    final id = queue.removeLast();
    // The task itself is never its own descendant, even when
    // a cycle already in the data leads back to it.
    if (id == taskId) continue;
    if (!out.add(id)) continue;
    queue.addAll(children[id] ?? const <String>[]);
  }
  return out;
}

/// True when pointing [taskId]'s "Starts after" at
/// [dependsOnId] would close a dependency cycle: following
/// the chain up from the chosen task reaches [taskId] again.
/// A cycle already in the data ends the walk instead of
/// looping forever.
bool createsDependencyCycle(
    String taskId, String? dependsOnId, List<TaskItem> all) {
  if (dependsOnId == null) return false;
  final byId = {for (final t in all) t.id: t};
  final seen = <String>{};
  String? current = dependsOnId;
  while (current != null) {
    if (current == taskId) return true;
    if (!seen.add(current)) return false;
    current = byId[current]?.dependsOnTaskId;
  }
  return false;
}

/// One task, two modes on a single screen.
///
/// * View mode shows the task detail exactly as the old detail
///   screen did: status, photos, Updates thread, and all status
///   actions (Start / Done with the photo requirement / Blocked
///   with a reason / pause-resume for admins and managers).
/// * Edit mode shows the old editor's fields inline in the same
///   screen. An Edit button in the AppBar (admin/manager only)
///   switches into it; saving returns to view mode.
/// * Workers see the same screen read-only with no Edit button.
/// * [task] null means create: the screen opens straight in edit
///   mode, and saving (or cancelling) pops back to the list, as
///   the old editor did - there is no view to return to yet.
class TaskScreen extends ConsumerStatefulWidget {
  final TaskItem? task; // null = create a new task
  final String? initialSiteId;
  final String? initialUnitId;
  final bool readOnly;
  const TaskScreen(
      {super.key,
      this.task,
      this.initialSiteId,
      this.initialUnitId,
      this.readOnly = false});

  @override
  ConsumerState<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends ConsumerState<TaskScreen> {
  // --- View-mode state (from the old detail screen) ---
  final List<String> _addedPhotos = [];

  /// Local paths of photos whose upload failed (offline). They
  /// count toward Done; on completion they move into the photo
  /// queue and send themselves when connection returns.
  final List<String> _pendingPhotoPaths = [];

  /// Paths in [_pendingPhotoPaths] already parked in the photo
  /// queue (at add time): Done must not enqueue them a second
  /// time. A path lands here only once its park succeeded.
  final Set<String> _queuedPhotoPaths = {};
  final TextEditingController _updateCtrl = TextEditingController();
  // Pending update-thread photo: picked locally, queued at Post
  // time (taskUpdate kind) so it survives being offline. The
  // bytes are only the composer thumbnail; the queue uploads
  // from the path.
  String? _updatePhotoPath;
  Uint8List? _updatePhotoBytes;
  bool _updateBusy = false;
  bool _busy = false;

  // --- Edit-mode state (from the old editor screen) ---
  late final TextEditingController _title;
  late final TextEditingController _unit;
  late final TextEditingController _notes;
  late final TextEditingController _materials;
  String? _siteId;
  Set<String> _assigneeIds = {};
  String? _dependsOnTaskId;
  String? _stageId;
  String? _unitId;
  TaskStatus _status = TaskStatus.todo;
  DateTime? _dueDate;
  DateTime? _startDate;
  bool _dependsSoft = false;
  bool _photoRequired = true;
  bool _saving = false;

  /// True while the screen is showing the edit form. Create
  /// opens in edit mode; an existing task opens in view mode.
  late bool _editing;

  /// True once the user has changed any edit field. While
  /// [_resetting] the controllers are being refilled from the
  /// live task, so their listeners must not mark the form dirty.
  bool _dirty = false;
  bool _resetting = false;

  @override
  void initState() {
    super.initState();
    _editing = widget.task == null;
    final t = widget.task;
    _title = TextEditingController(text: t?.title ?? '');
    _unit = TextEditingController(text: t?.unit ?? '');
    _notes = TextEditingController(text: t?.notes ?? '');
    _materials = TextEditingController(text: (t?.materials ?? []).join('\n'));
    _siteId = t?.siteId ?? widget.initialSiteId;
    _assigneeIds = Set.of(t?.assigneeIds ?? const <String>[]);
    _dependsOnTaskId = t?.dependsOnTaskId;
    _stageId = t?.stageId;
    _unitId = t?.unitId ?? widget.initialUnitId;
    _status = t?.status ?? TaskStatus.todo;
    _dueDate = t?.dueDate;
    _startDate = t?.startDate;
    _dependsSoft = t?.dependsSoft ?? false;
    _photoRequired = t?.photoRequired ?? true;
    for (final c in [_title, _unit, _notes, _materials]) {
      c.addListener(() {
        if (!_resetting) _dirty = true;
      });
    }
  }

  @override
  void dispose() {
    _updateCtrl.dispose();
    _title.dispose();
    _unit.dispose();
    _notes.dispose();
    _materials.dispose();
    super.dispose();
  }

  /// Refill every edit field from [source] (the live task when
  /// entering edit mode, so a status change that streamed in
  /// while viewing is not overwritten by stale form values).
  void _resetEditFields(TaskItem source) {
    _resetting = true;
    _title.text = source.title;
    _unit.text = source.unit;
    _notes.text = source.notes;
    _materials.text = source.materials.join('\n');
    _siteId = source.siteId;
    _assigneeIds = Set.of(source.assigneeIds);
    _dependsOnTaskId = source.dependsOnTaskId;
    _stageId = source.stageId;
    _unitId = source.unitId;
    _status = source.status;
    _dueDate = source.dueDate;
    _startDate = source.startDate;
    _dependsSoft = source.dependsSoft;
    _photoRequired = source.photoRequired;
    _resetting = false;
    _dirty = false;
  }

  void _enterEditMode(TaskItem live) {
    _resetEditFields(live);
    setState(() => _editing = true);
  }

  void _exitEditMode() {
    if (widget.task == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _editing = false);
    }
  }

  /// Leave edit mode: straight out when nothing changed, or
  /// after confirming that unsaved edits are discarded.
  Future<void> _cancelEdit() async {
    if (!_dirty) {
      _exitEditMode();
      return;
    }
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.discardChanges),
        content: Text(s.discardChangesConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.discard)),
        ],
      ),
    );
    if (ok == true) _exitEditMode();
  }

  /// The live task: the streamed list wins; the task the
  /// screen was opened with stands in only while the stream
  /// is still loading ([streamLoading]). Once the stream has
  /// landed and the task is not in it, the task was deleted —
  /// never fall back to the stale opened copy, or the screen
  /// would show (and let the user edit) a task that no longer
  /// exists.
  TaskItem? _liveTask(List<TaskItem> allTasks,
      {required bool streamLoading}) {
    final opened = widget.task;
    if (opened == null) return null;
    for (final t in allTasks) {
      if (t.id == opened.id) return t;
    }
    return streamLoading ? opened : null;
  }

  Future<void> _save() async {
    final s = ref.read(stringsProvider);
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.taskNeedsTitle)),
      );
      return;
    }
    if (_siteId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.taskNeedsSite)),
      );
      return;
    }
    // Refuse to save while any stream this save reads from
    // has not loaded (or errored): valueOrNull ?? [] would
    // treat "not loaded" as "empty" and wipe the assignees,
    // unit, stage and dependency with no warning. The editor
    // stays open so nothing is lost.
    final allTasksAsync = ref.read(allTasksProvider);
    final crewAsync = ref.read(allUsersProvider);
    final unitsAsync = ref.read(unitsForSiteProvider(_siteId ?? ''));
    if (allTasksAsync.isLoading ||
        allTasksAsync.hasError ||
        crewAsync.isLoading ||
        crewAsync.hasError ||
        unitsAsync.isLoading ||
        unitsAsync.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Still loading — wait a moment, then tap Save again.'),
        ),
      );
      return;
    }
    final allTasks = allTasksAsync.valueOrNull ?? [];
    final existing =
        _liveTask(allTasks, streamLoading: allTasksAsync.isLoading);
    if (existing == null && widget.task != null) {
      // Deleted while the editor was open: saving here would
      // recreate it as a brand-new task. Refuse instead.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.taskDeleted)),
      );
      return;
    }
    // The picked site's units: a unit that no longer exists is
    // dropped on save, so a deleted unit never leaves a dangling
    // link behind (same guard as the "Starts after" dependency).
    final units = unitsAsync.valueOrNull ?? [];
    final savedUnitId =
        _unitId != null && units.any((u) => u.id == _unitId)
            ? _unitId
            : null;
    // The stages of the task's saved scope: a stage from the
    // wrong scope (or one that no longer exists) is dropped on
    // save, so a task can never point at a stage in another
    // roadmap. Same not-loaded guard as above: an empty stage
    // list must never silently drop the task's stage.
    final stagesAsync = savedUnitId != null
        ? ref.read(stagesForUnitProvider(savedUnitId))
        : ref.read(stagesForSiteProvider(_siteId ?? ''));
    if (stagesAsync.isLoading || stagesAsync.hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Still loading — wait a moment, then tap Save again.'),
        ),
      );
      return;
    }
    final stages = savedUnitId != null
        ? stagesAsync.valueOrNull ?? []
        : (stagesAsync.valueOrNull ?? [])
            .where((st) => st.unitId == null)
            .toList();
    // The assignees, saved in crew-list order (not tap order)
    // so the card and detail screen always list them the same
    // way. A removed user is dropped, like the site/unit/stage
    // guards above. Empty = unassigned.
    final crew = crewAsync.valueOrNull ?? [];
    final savedAssigneeIds = crew
        .map((u) => u.id)
        .where((id) => _assigneeIds.contains(id))
        .toList();
    // The dependency, after the dangling-link guard: a
    // dependency on a task that no longer exists is dropped on
    // save, so a deleted task never leaves a dangling link
    // behind (a dangling link crashes the "Starts after"
    // dropdown the next time the task is opened).
    String? savedDependsOnTaskId =
        _dependsOnTaskId != null &&
                allTasks.any((t) => t.id == _dependsOnTaskId)
            ? _dependsOnTaskId
            : null;
    if (existing != null &&
        createsDependencyCycle(
            existing.id, savedDependsOnTaskId, allTasks)) {
      if (savedDependsOnTaskId != existing.dependsOnTaskId) {
        // The user just picked a link that closes a cycle:
        // refuse, and keep the editor open.
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'That "Starts after" would create a dependency cycle.'),
          ),
        );
        return;
      }
      // A cycle already in the data, which the form no longer
      // shows (the dropdown excludes descendants): drop the
      // link instead of saving the deadlock back.
      savedDependsOnTaskId = null;
    }
    // Marking Done stamps when it finished and needs a photo
    // when one is required; reopening a finished task clears
    // the stamp, so it stops counting as finished.
    final wasDone = existing?.status == TaskStatus.done;
    final becomingDone = _status == TaskStatus.done && !wasDone;
    DateTime? finishedAt = existing?.finishedAt;
    if (becomingDone) {
      final hasPhoto = (existing?.photoUrls.isNotEmpty ?? false) ||
          _addedPhotos.isNotEmpty ||
          _pendingPhotoPaths.isNotEmpty;
      if (_photoRequired && !hasPhoto) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'A photo is required before this task can be marked Done.'),
          ),
        );
        return;
      }
      finishedAt = DateTime.now();
    } else if (_status != TaskStatus.done && wasDone) {
      finishedAt = null;
    }
    final task = TaskItem(
      id: existing?.id ?? '',
      title: _title.text.trim(),
      siteId: _siteId!,
      unit: _unit.text.trim(),
      assigneeIds: savedAssigneeIds,
      createdBy: existing?.createdBy ?? me.id,
      status: _status,
      // Saving with Paused must remember where the task came
      // from so resume restores it; a task that was already
      // paused keeps its original pre-pause status. Any other
      // status clears the stored value. A brand-new task saved
      // straight into Paused resumes to To do.
      pausedFrom: _status == TaskStatus.paused
          ? (existing?.status == TaskStatus.paused
              ? existing?.pausedFrom
              : (existing?.status ?? TaskStatus.todo))
          : null,
      dueDate: _dueDate,
      startDate: _startDate,
      notes: _notes.text.trim(),
      materials: _materials.text
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(),
      materialsOnSite: existing?.materialsOnSite ?? false,
      // The materials checklist is toggled from view mode and
      // persisted there; saving the editor must not wipe it.
      materialsChecked: existing?.materialsChecked ?? const [],
      dependsOnTaskId: savedDependsOnTaskId,
      stageId: _stageId != null && stages.any((x) => x.id == _stageId)
          ? _stageId
          : null,
      unitId: savedUnitId,
      dependsSoft: savedDependsOnTaskId == null ? false : _dependsSoft,
      photoRequired: _photoRequired,
      // A stale blocked reason must not survive a status
      // change away from Blocked; staying Blocked keeps the
      // reason the detail screen recorded.
      blockedReason:
          _status == TaskStatus.blocked ? existing?.blockedReason : null,
      blockedNote:
          _status == TaskStatus.blocked ? (existing?.blockedNote ?? '') : '',
      photoUrls: existing?.photoUrls ?? const [],
      photoPending: existing?.photoPending ?? false,
      createdAt: existing?.createdAt ?? DateTime.now(),
      startedAt: existing?.startedAt,
      finishedAt: finishedAt,
    );
    // Backstop for the status dropdown: a forward step (Start
    // / Done) that the chain or stage locks forbid must not be
    // saved even if the form was built before the lock landed.
    // Only a *change* to a forward status is blocked — saving
    // any other edit to a task that is already In progress (or
    // already Done) must still work.
    TaskItem? dependency;
    if (task.dependsOnTaskId != null) {
      for (final t in allTasks) {
        if (t.id == task.dependsOnTaskId) dependency = t;
      }
    }
    final locked = task.isLocked(dependency) ||
        (ref.read(stageIndexProvider)?.isLockedByStage(task) ?? false);
    final changingForward =
        (task.status == TaskStatus.inProgress &&
                existing?.status != TaskStatus.inProgress) ||
            (task.status == TaskStatus.done &&
                existing?.status != TaskStatus.done);
    if (locked && changingForward) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(task.status == TaskStatus.done
              ? 'This task is locked — it can’t be marked Done yet.'
              : 'This task is locked — it can’t be started yet.'),
        ),
      );
      return;
    }
    final service = ref.read(taskServiceProvider);
    setState(() => _saving = true);
    try {
      if (existing == null) {
        await service.createTask(task);
      } else {
        await service.updateTask(task);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.taskSaveFailed('$e'))),
        );
      }
      return;
    }
    if (!mounted) return;
    if (existing == null) {
      // Created: no view to return to - back to the list, as
      // the old editor did.
      Navigator.of(context).pop();
    } else {
      // Edited: back to view mode on the same screen.
      setState(() {
        _saving = false;
        _dirty = false;
        _editing = false;
      });
    }
  }

  Future<void> _pauseTask(TaskItem live) async {
    final s = ref.read(stringsProvider);
    await ref.read(taskServiceProvider).pauseTask(live);
    if (mounted) {
      // Keep the form's status in step so a later save does
      // not silently undo the pause.
      setState(() => _status = TaskStatus.paused);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.taskPaused)));
    }
  }

  Future<void> _resumeTask(TaskItem live) async {
    final s = ref.read(stringsProvider);
    await ref.read(taskServiceProvider).resumeTask(live);
    if (mounted) {
      setState(
          () => _status = live.pausedFrom ?? TaskStatus.todo);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(s.taskResumed)));
    }
  }

  Future<void> _confirmDelete(TaskItem live) async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.deleteTask),
        content: Text(s.deleteTaskConfirm),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.delete)),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(taskServiceProvider).deleteTask(live.id);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _addPhoto(TaskItem task) async {
    final photos = ref.read(photoServiceProvider);
    final picked = await photos.takePhoto();
    if (picked == null) return; // camera cancelled - nothing changes
    setState(() => _busy = true);
    try {
      final url =
          await photos.uploadFile(picked.path, 'taskPhotos', task.id);
      // Persist the photo on the task at once: a URL that only
      // lives in _addedPhotos is lost — and its Storage file
      // orphaned — when the user leaves before Done.
      try {
        await ref.read(taskServiceProvider).updateTask(
              task.copyWith(photoUrls: [...task.photoUrls, url]),
            );
      } catch (_) {
        // The write failed (connection dropped just after the
        // upload, or a rules refusal): keep the old in-memory
        // path so Done still attaches it.
        if (mounted) setState(() => _addedPhotos.add(url));
      }
    } catch (_) {
      // No signal: park the photo in the offline queue right
      // away instead of holding only the camera temp path —
      // the queue owns a copy under pending_uploads, so
      // leaving the screen (or the OS purging the temp file)
      // cannot lose it. The path is still held so the photo
      // shows and counts toward Done.
      final parked = await ref.read(photoQueueServiceProvider).enqueue(
            kind: 'taskDone',
            sourcePath: picked.path,
            folder: 'taskPhotos',
            taskId: task.id,
          );
      if (mounted) {
        if (parked) {
          setState(() {
            _pendingPhotoPaths.add(picked.path);
            _queuedPhotoPaths.add(picked.path);
          });
          // Best effort: tell the task a photo is on its way.
          // The queue clears the flag when the photo lands;
          // if this write fails the photo is still safe in
          // the queue, only the flag is lost.
          try {
            await ref.read(taskServiceProvider).updateTask(
                  task.copyWith(photoPending: true),
                );
          } catch (_) {}
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text(ref.read(stringsProvider).photoQueuedOffline)),
            );
          }
        } else {
          // Parking failed too: hold the temp path so Done
          // can retry the park — never drop the photo
          // silently. Done refuses to close on a failed park.
          setState(() => _pendingPhotoPaths.add(picked.path));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text(ref.read(stringsProvider).photoUploadFailed)),
          );
        }
      }
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Mark Done from view mode, with the photo requirement.
  /// Photos that could not upload are parked in the offline
  /// queue first; a parking failure aborts the completion —
  /// the photo would otherwise be lost while photoPending
  /// stays true. Any failure leaves the screen usable with a
  /// message instead of stuck busy.
  Future<void> _completeTask(TaskItem live) async {
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      // A photo parked in an earlier session counts too: the
      // queue still owns it, so the flag stays set until it
      // lands instead of being cleared by this completion.
      final hadPendingPhotos =
          _pendingPhotoPaths.isNotEmpty || live.photoPending;
      if (_pendingPhotoPaths.isNotEmpty) {
        final queue = ref.read(photoQueueServiceProvider);
        for (final path in List.of(_pendingPhotoPaths)) {
          // Already parked at add time: the queue owns this
          // photo — enqueueing again would attach it twice.
          if (_queuedPhotoPaths.contains(path)) continue;
          final parked = await queue.enqueue(
            kind: 'taskDone',
            sourcePath: path,
            folder: 'taskPhotos',
            taskId: live.id,
          );
          if (!parked) {
            // Parking failed: the photo is gone if we complete
            // now. Stay on the screen with an error — the path
            // is still held, so Done can be retried.
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(s.photoUploadFailed)),
              );
            }
            return;
          }
          // Parked: the queue owns this photo now — drop it
          // from the held list so a retry never enqueues it
          // twice.
          if (mounted) setState(() => _pendingPhotoPaths.remove(path));
        }
      }
      await ref.read(taskServiceProvider).completeTask(
            live,
            _addedPhotos,
            photoPending: hadPendingPhotos,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.taskSaveFailed('$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Update-thread photo: picked now, queued at Post time (see
  /// _postUpdate). Nothing uploads until the user posts, so a
  /// cancelled composer never leaves an orphan upload, and a
  /// photo picked offline still posts when connection returns.
  Future<void> _addUpdatePhoto(TaskItem task) async {
    setState(() => _updateBusy = true);
    try {
      final picked = await ref.read(photoServiceProvider).takePhoto();
      if (picked == null) return; // camera cancelled
      final bytes = await picked.readAsBytes();
      if (mounted) {
        setState(() {
          _updatePhotoPath = picked.path;
          _updatePhotoBytes = bytes;
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(ref.read(stringsProvider).photoUploadFailed)),
        );
      }
    }
    if (mounted) setState(() => _updateBusy = false);
  }

  Future<void> _postUpdate(TaskItem task) async {
    final s = ref.read(stringsProvider);
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    final text = _updateCtrl.text.trim();
    if (text.isEmpty && _updatePhotoPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.updateNeedsContent)),
      );
      return;
    }
    setState(() => _updateBusy = true);
    try {
      final photoPath = _updatePhotoPath;
      if (photoPath != null) {
        // Photo post: parked in the offline queue, which creates
        // the Updates-thread doc once the photo lands — online
        // that is near-instant, offline it waits for connection.
        // The parked post renders as a pending row below, so the
        // user sees it at once; and if parking itself fails the
        // composer keeps the post and shows the error instead of
        // clearing for a post that will never land (that silent
        // loss is the bug this fixes).
        final parked =
            await ref.read(photoQueueServiceProvider).enqueue(
                  kind: 'taskUpdate',
                  sourcePath: photoPath,
                  folder: 'taskPhotos',
                  taskId: task.id,
                  authorId: me.id,
                  authorName: me.name,
                  text: text,
                );
        if (!parked) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(s.photoUploadFailed)),
            );
          }
          return;
        }
      } else {
        await ref.read(taskServiceProvider).addUpdate(
              task.id,
              authorId: me.id,
              authorName: me.name,
              text: text,
            );
      }
      if (mounted) {
        setState(() {
          _updateCtrl.clear();
          _updatePhotoPath = null;
          _updatePhotoBytes = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.updatePostFailed('$e'))),
        );
      }
      // The composer keeps the text and photo on failure: the
      // clear above only runs on the success path.
    } finally {
      if (mounted) setState(() => _updateBusy = false);
    }
  }

  /// A task-update post parked in the offline queue: the photo
  /// and text the user just posted, shown until the queue lands
  /// it as a real update — so a post is never invisible while
  /// its photo uploads. The label says whether it is sending
  /// or waiting for a connection.
  Widget _pendingUpdateRow(AppStrings s, PendingTaskUpdate p) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          pendingPhotoThumbnail(p.localPath),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(p.authorName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13.5)),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: FutureBuilder<List<ConnectivityResult>>(
                      future: Connectivity().checkConnectivity(),
                      builder: (context, snap) {
                        final offline = snap.hasData &&
                            !snap.data!.any(
                                (r) => r != ConnectivityResult.none);
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!offline) ...[
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Flexible(
                              child: Text(
                                offline
                                    ? s.updateWaitingForConnection
                                    : s.updateSending,
                                overflow: TextOverflow.ellipsis,
                                style:
                                    Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ]),
                if (p.text.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(p.text,
                      style: Theme.of(context).textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Toggles one materials-checklist item and persists it to
  /// Firestore through the normal task update path. The checked
  /// state is stored as the item's label (TaskItem
  /// .materialsChecked), so it survives materials-list edits and
  /// reloads. The live stream re-renders the tick as soon as
  /// the local write lands — no local copy is kept. The rules
  /// let the assignee (and admins/managers) update the task,
  /// which is why the tap is only offered to them (see
  /// _buildViewScaffold).
  Future<void> _toggleMaterial(TaskItem live, String label) async {
    final checked = live.materialsChecked.toSet();
    if (checked.contains(label)) {
      checked.remove(label);
    } else {
      checked.add(label);
    }
    // Keep only labels still on the list, in list order.
    final next =
        live.materials.where((m) => checked.contains(m)).toList();
    try {
      await ref.read(taskServiceProvider).updateTask(
            live.copyWith(materialsChecked: next),
          );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  ref.read(stringsProvider).taskSaveFailed('$e'))),
        );
      }
    }
  }

  /// Start, after confirmation. The button itself stays
  /// fire-and-forget, as before — only the dialog is new.
  Future<void> _confirmStart(TaskItem live) async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.confirmStartTask),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.confirm)),
        ],
      ),
    );
    if (ok != true) return;
    ref.read(taskServiceProvider).startTask(live);
  }

  Future<void> _markBlocked(TaskItem task) async {
    final result = await showDialog<_BlockedResult>(
      context: context,
      builder: (ctx) =>
          _MarkBlockedDialog(strings: ref.read(stringsProvider)),
    );
    // The dialog owns its note controller and reads it before
    // popping, so nothing is ever read after a dispose.
    if (result == null) return;
    await ref
        .read(taskServiceProvider)
        .blockTask(task, result.reason, result.note);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final isManager = me?.isAdminOrManager ?? false;
    // The Edit button is admin/manager only, and never in a
    // read-only opening (a driver linked from a run, a chain
    // step that belongs to someone else).
    final canEdit = isManager && !widget.readOnly;
    final allTasksAsync = ref.watch(allTasksProvider);
    final allTasks = allTasksAsync.valueOrNull ?? [];
    final live =
        _liveTask(allTasks, streamLoading: allTasksAsync.isLoading);
    if (live == null &&
        widget.task != null &&
        !allTasksAsync.isLoading &&
        !allTasksAsync.hasError) {
      // The stream has landed and the task is not in it: it
      // was deleted (here or on another device). Say so and
      // offer the way out instead of showing a stale copy.
      return Scaffold(
        appBar: AppBar(title: Text(s.appTitle)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(s.taskDeleted,
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(s.close),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_editing || live == null) {
      return _buildEditScaffold(context, s, live, allTasks);
    }
    return _buildViewScaffold(context, s, live, allTasks, canEdit);
  }

  /// View mode: the old detail screen, unchanged in behaviour.
  /// The Updates thread is watched here (only view mode has a
  /// task id to watch); Riverpod resubscribes when the screen
  /// switches modes, so the conditional watch is safe.
  Widget _buildViewScaffold(BuildContext context, AppStrings s,
      TaskItem live, List<TaskItem> allTasks, bool canEdit) {
    final tokens = AppTokens.of(context);
    final siteById = ref.watch(siteByIdProvider);
    final site = siteById[live.siteId];
    // The linked unit's name, when the task belongs to one —
    // the free-text unit field is the fallback for older tasks.
    final units =
        ref.watch(unitsForSiteProvider(live.siteId)).valueOrNull ?? [];
    final unitName = live.unitId == null
        ? null
        : units.where((u) => u.id == live.unitId).firstOrNull?.name;

    // Dependency / locked state: look the dependency up in the
    // full task list (crew can read tasks - see firestore.rules).
    // The same list feeds the chain strip (Step X of N). The
    // stage locks too: a task in a stage that is not Active yet
    // cannot be started, and the banner names the stage.
    TaskItem? dependency;
    if (live.dependsOnTaskId != null) {
      for (final t in allTasks) {
        if (t.id == live.dependsOnTaskId) dependency = t;
      }
    }
    final chainLocked = live.isLocked(dependency);
    final stageIndex = ref.watch(stageIndexProvider);
    final stage = stageIndex?.stageOf(live);
    final stageLocked = stageIndex?.isLockedByStage(live) ?? false;
    final locked = chainLocked || stageLocked;
    final chainIndex = ChainIndex.from(allTasks);
    final chain = chainIndex.chainOf[live.id];
    final chainPos = chainIndex.positionOf[live.id];
    final nextStep = chainIndex.nextAfter(live);
    final updatesAsync = ref.watch(taskUpdatesProvider(live.id));
    // Posts parked in the offline queue for this task: rendered
    // as pending rows below the real updates until they land.
    final pendingAsync = ref.watch(pendingTaskUpdatesProvider(live.id));
    final pending = pendingAsync.valueOrNull ?? [];
    // Pause/resume is an admin/manager-only action.
    final me = ref.watch(currentUserProvider).valueOrNull;
    final isManager = me?.isAdminOrManager ?? false;
    // The materials checklist writes the task doc, so only
    // someone who may act on the task (assignee or
    // admin/manager) can tick it — and never in read-only mode.
    // The checked labels come from the live task itself, so the
    // ticks survive reloads and other devices.
    final checkedMaterials = live.materialsChecked.toSet();
    final canToggleMaterials =
        !widget.readOnly && taskEditableBy(live, me);
    final allPhotos = [...live.photoUrls, ..._addedPhotos];
    // A photo parked in the offline queue counts toward Done:
    // no signal must not trap the worker on this screen. A
    // photo queued in an earlier session counts too — the task
    // still carries photoPending until the queue lands it.
    final canComplete = live.photoRequired
        ? allPhotos.isNotEmpty ||
            _pendingPhotoPaths.isNotEmpty ||
            live.photoPending
        : true;

    return Scaffold(
      appBar: AppBar(
        title: Text(site?.name ?? s.appTitle),
        actions: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: s.edit,
              onPressed: () => _enterEditMode(live),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(live.title,
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            [
              if (site != null) site.name,
              if (unitName != null)
                'Unit $unitName'
              else if (live.unit.isNotEmpty)
                'Unit ${live.unit}',
              if (live.dueDate != null)
                '${s.due}: ${DateFormat('EEE MMM d').format(live.dueDate!)}',
            ].join(' · '),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          StatusIndicator(status: live.status, overdue: live.isOverdue),
          const SizedBox(height: 14),
          // Who is on this task: every assignee, avatar + name.
          // Unassigned tasks say so instead of showing nobody.
          Builder(builder: (context) {
            final users =
                ref.watch(allUsersProvider).valueOrNull ?? <AppUser>[];
            final userById = {for (final u in users) u.id: u};
            final assignees = taskAssignees(live, userById, s);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.assignee,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 7),
                if (assignees.isEmpty)
                  Text(s.unassigned,
                      style: Theme.of(context).textTheme.bodyMedium),
                if (assignees.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      for (final a in assignees)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            RoleAvatar(
                              name: a.name,
                              role: a.role,
                              size: 28,
                              photoUrl: a.photoUrl,
                            ),
                            const SizedBox(width: 6),
                            Text(a.name,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium),
                          ],
                        ),
                    ],
                  ),
              ],
            );
          }),
          if (chain != null && chainPos != null) ...[
            const SizedBox(height: 14),
            Text(s.stepOf(chainPos + 1, chain.length),
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 7),
            ChainStrip(index: chainIndex, chain: chain, currentId: live.id),
          ],
          if (locked) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(children: [
                Icon(Icons.lock_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(
                        chainLocked
                            ? (dependency != null
                                ? s.waitingOn(dependency.title)
                                : s.locked)
                            : (stage != null
                                ? s.waitingOn(stage.name)
                                : s.locked),
                        style: Theme.of(context).textTheme.bodyMedium)),
              ]),
            ),
          ],
          if (!locked &&
              dependency != null &&
              dependency.status != TaskStatus.done &&
              live.dependsSoft) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(children: [
                Icon(Icons.link, size: 16, color: tokens.accentText),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(s.usuallyAfter(dependency.title),
                        style: Theme.of(context).textTheme.bodyMedium)),
              ]),
            ),
          ],
          if (!locked && nextStep != null && !nextStep.dependsSoft) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Row(children: [
                Icon(Icons.lock_open_outlined,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(s.unlocksNext(nextStep.title),
                        style: Theme.of(context).textTheme.bodyMedium)),
              ]),
            ),
          ],
          if (live.notes.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(s.notes,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Text(live.notes,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface)),
          ],
          if (live.materialsOnSite) ...[
            const SizedBox(height: 18),
            Row(children: [
              Icon(Icons.check_circle,
                  size: 18,
                  color: tokens.statusDone),
              const SizedBox(width: 7),
              Text(s.materialsOnSite,
                  style: Theme.of(context).textTheme.titleSmall),
            ]),
          ],
          if (live.materials.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(s.materials,
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 4),
            Container(
              decoration: appCardDecoration(context),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Column(
                children: [
                  for (var i = 0; i < live.materials.length; i++) ...[
                    if (i > 0) const _DashedDivider(),
                    InkWell(
                      // Persisted to Firestore on every toggle
                      // (TaskItem.materialsChecked); in read-only
                      // mode — or for someone who may not act on
                      // this task — the screen is look-don't-touch,
                      // so the tap is off.
                      onTap: canToggleMaterials
                          ? () => _toggleMaterial(live, live.materials[i])
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        child: Row(children: [
                          Icon(
                            checkedMaterials.contains(live.materials[i])
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                            size: 21,
                            color: checkedMaterials.contains(live.materials[i])
                                ? tokens.accentText
                                : Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(live.materials[i],
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                  decoration: checkedMaterials
                                          .contains(live.materials[i])
                                      ? TextDecoration.lineThrough
                                      : null,
                                )),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          if (allPhotos.isNotEmpty || _pendingPhotoPaths.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < allPhotos.length; i++)
                  GestureDetector(
                    onTap: () => showPhotoViewer(
                      context,
                      items: [
                        for (final url in allPhotos)
                          PhotoViewerItem(url: url, label: live.title),
                        for (final path in _pendingPhotoPaths)
                          PhotoViewerItem(
                              localPath: path, label: live.title),
                      ],
                      initialIndex: i,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(allPhotos[i],
                          width: 96, height: 96, fit: BoxFit.cover),
                    ),
                  ),
                for (var j = 0; j < _pendingPhotoPaths.length; j++)
                  GestureDetector(
                    onTap: () => showPhotoViewer(
                      context,
                      items: [
                        for (final url in allPhotos)
                          PhotoViewerItem(url: url, label: live.title),
                        for (final path in _pendingPhotoPaths)
                          PhotoViewerItem(
                              localPath: path, label: live.title),
                      ],
                      initialIndex: allPhotos.length + j,
                    ),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _PendingPhotoThumb(
                              path: _pendingPhotoPaths[j]),
                        ),
                        const Positioned(
                          right: 5,
                          bottom: 5,
                          child: Icon(Icons.schedule,
                              size: 17, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
          if (live.photoPending || _pendingPhotoPaths.isNotEmpty) ...[
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.schedule,
                  size: 15,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(s.photoPendingUpload,
                    style: Theme.of(context).textTheme.bodySmall),
              ),
            ]),
          ],
          const SizedBox(height: 24),
          Text(s.updates,
              style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          updatesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Text('$e',
                style: Theme.of(context).textTheme.bodySmall),
            data: (updates) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (updates.isEmpty && pending.isEmpty)
                  Text(s.noUpdatesYet,
                      style: Theme.of(context).textTheme.bodyMedium),
                for (final u in updates)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(u.authorName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5)),
                          const SizedBox(width: 8),
                          Text(
                              u.createdAt == null
                                  ? ''
                                  : DateFormat('MMM d, HH:mm')
                                      .format(u.createdAt!),
                              style:
                                  Theme.of(context).textTheme.bodySmall),
                        ]),
                        if (u.text.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(u.text,
                              style:
                                  Theme.of(context).textTheme.bodyMedium),
                        ],
                        if (u.photoUrl != null) ...[
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: () => showPhotoViewer(
                              context,
                              items: [
                                PhotoViewerItem(
                                  url: u.photoUrl,
                                  label: u.authorName,
                                ),
                              ],
                              initialIndex: 0,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(u.photoUrl!,
                                  width: 96,
                                  height: 96,
                                  fit: BoxFit.cover),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
          // Posts still uploading: visible at once, gone the
          // moment the queue lands them as real updates above.
          for (final p in pending) _pendingUpdateRow(s, p),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _updateCtrl,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                      labelText: s.addAnUpdate,
                      border: const OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.photo_camera_outlined),
                onPressed:
                    _updateBusy ? null : () => _addUpdatePhoto(live),
              ),
              FilledButton(
                // The app-wide FilledButton theme is full-width
                // (minimumSize Size.fromHeight(50) = infinite
                // width), which explodes inside this Row - a Row
                // hands non-flex children unbounded width. Keep
                // this button content-sized, like the run sheet's
                // confirm button.
                style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44)),
                onPressed: _updateBusy ? null : () => _postUpdate(live),
                child: _updateBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(s.post),
              ),
            ],
          ),
          if (_updatePhotoPath != null) ...[
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: GestureDetector(
                onTap: () => showPhotoViewer(
                  context,
                  items: [
                    PhotoViewerItem(
                      localPath: _updatePhotoPath,
                      label: live.title,
                    ),
                  ],
                  initialIndex: 0,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _updatePhotoBytes != null
                      ? Image.memory(_updatePhotoBytes!,
                          width: 64, height: 64, fit: BoxFit.cover)
                      : const SizedBox(width: 64, height: 64),
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          // The whole action area (add photo for Done, Start,
          // Done, Blocked) writes the task doc - hidden in
          // read-only mode. The Updates thread above stays: it
          // is a separate collection the rules open to everyone.
          if (!widget.readOnly && live.status != TaskStatus.done) ...[
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                side: BorderSide(
                    color: Theme.of(context).colorScheme.outline),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
              onPressed: _busy ? null : () => _addPhoto(live),
              icon: const Icon(Icons.photo_camera_outlined, size: 19),
              label: Text(s.addPhoto),
            ),
            const SizedBox(height: 12),
            if (live.status == TaskStatus.todo ||
                live.status == TaskStatus.toConfirm ||
                live.status == TaskStatus.blocked)
              FilledButton(
                onPressed: locked || _busy
                    ? null
                    : () => _confirmStart(live),
                child: Text(s.start),
              ),
            if (live.status == TaskStatus.inProgress) ...[
              FilledButton(
                onPressed: locked || _busy || !canComplete
                    ? null
                    : () => _completeTask(live),
                child: Text(live.photoRequired
                    ? '${s.markDone} — ${s.photoRequiredNote}'
                    : s.markDone),
              ),
              if (live.photoRequired &&
                  allPhotos.isEmpty &&
                  _pendingPhotoPaths.isEmpty &&
                  !live.photoPending)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(s.photoRequiredNote,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall),
                ),
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.danger,
                side: BorderSide(color: tokens.dangerBorder, width: 1.5),
              ),
              onPressed: _busy ? null : () => _markBlocked(live),
              child: Text(s.markBlocked),
            ),
            // Materials request: any crew member on the task can
            // ask for what they're short on. It lands with the
            // managers as a request — never a task, never a run
            // stop by itself.
            const SizedBox(height: 12),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(44),
                foregroundColor: Theme.of(context).colorScheme.onSurface,
                side: BorderSide(
                    color: Theme.of(context).colorScheme.outline),
                textStyle: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
              ),
              onPressed: _busy
                  ? null
                  : () async {
                      final sent = await showMaterialRequestSheet(
                        context,
                        ref,
                        siteId: live.siteId,
                        taskId: live.id,
                      );
                      // The sheet is fully closed by now: the
                      // confirmation comes from here, never from
                      // inside the sheet across its own pop.
                      if (sent == true && context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(s.materialRequestSent)),
                        );
                      }
                    },
              icon: const Icon(Icons.inventory_2_outlined, size: 19),
              label: Text(s.requestMaterials),
            ),
            // Pause / resume: admin/manager only, below Blocked.
            // The action area already hides for done tasks, so a
            // paused task shows Resume and any other open task
            // shows Pause. The live stream flips the label back
            // once the write lands.
            if (isManager) ...[
              const SizedBox(height: 12),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: _busy
                    ? null
                    : () async {
                        final service = ref.read(taskServiceProvider);
                        if (live.status == TaskStatus.paused) {
                          await service.resumeTask(live);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s.taskResumed)),
                            );
                          }
                        } else {
                          await service.pauseTask(live);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(s.taskPaused)),
                            );
                          }
                        }
                      },
                child: Text(live.status == TaskStatus.paused
                    ? s.resume
                    : s.pause),
              ),
            ],
          ],
        ],
      ),
    );
  }

  /// Edit mode: the old editor screen, inline in this screen.
  /// [live] is null while creating a new task. The popup menu
  /// (pause / resume / delete) only exists for a saved task.
  Widget _buildEditScaffold(BuildContext context, AppStrings s,
      TaskItem? live, List<TaskItem> allTasks) {
    final tokens = AppTokens.of(context);
    final sites = ref.watch(sitesProvider).valueOrNull ?? [];
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    // The stages of the picked site (empty while no site is
    // picked). Watched unconditionally with '' as the key so
    // the subscription order never changes between builds.
    // The stage list follows the unit: a task in a unit picks
    // from that unit's roadmap; a task with no unit picks from
    // the site roadmap (site stages only — a unit's stages
    // never appear there). One roadmap or the other, never both.
    final siteStages =
        ref.watch(stagesForSiteProvider(_siteId ?? '')).valueOrNull ?? [];
    final unitStages =
        ref.watch(stagesForUnitProvider(_unitId ?? '')).valueOrNull ?? [];
    final stages = _unitId != null
        ? unitStages
        : siteStages.where((st) => st.unitId == null).toList();
    // The units of the picked site, same pattern as the stages.
    final units =
        ref.watch(unitsForSiteProvider(_siteId ?? '')).valueOrNull ?? [];
    // "Starts after" must never offer a descendant of this
    // task: pointing at one would close a dependency cycle
    // and deadlock both tasks forever. A new task has no
    // descendants yet. (_save rejects a cycle too, for a link
    // picked before the list changed under it.)
    final descendantIds = live == null
        ? const <String>{}
        : taskDescendantIds(live.id, allTasks);
    final others = allTasks
        .where((t) => t.id != live?.id && !descendantIds.contains(t.id))
        .toList();
    // Lock state for the form as it stands: the status
    // dropdown must not offer a forward step (Start / Done)
    // the chain or stage locks forbid — Start is lock-gated
    // everywhere else, and _save refuses the transition too.
    final previewTask = TaskItem(
      id: live?.id ?? '',
      title: _title.text.trim(),
      siteId: _siteId ?? '',
      assigneeIds: _assigneeIds.toList(),
      createdBy: live?.createdBy ?? '',
      status: _status,
      dependsOnTaskId: _dependsOnTaskId,
      dependsSoft: _dependsSoft,
      stageId: _stageId,
    );
    TaskItem? previewDependency;
    if (_dependsOnTaskId != null) {
      for (final t in allTasks) {
        if (t.id == _dependsOnTaskId) previewDependency = t;
      }
    }
    final editLocked = previewTask.isLocked(previewDependency) ||
        (ref.watch(stageIndexProvider)?.isLockedByStage(previewTask) ??
            false);
    // The AppBar popup menu (pause / resume / delete), built
    // eagerly here so the entries close over the final
    // [existing] task instead of a nullable parameter.
    final existing = live;
    final List<PopupMenuEntry<String>> editMenu = [];
    if (existing != null) {
      if (existing.status == TaskStatus.paused) {
        editMenu.add(
          PopupMenuItem(
            value: 'resume',
            child: Text(s.resume),
          ),
        );
      }
      if (existing.status != TaskStatus.paused &&
          existing.status != TaskStatus.done) {
        editMenu.add(
          PopupMenuItem(
            value: 'pause',
            child: Text(s.pause),
          ),
        );
      }
      // A task that belongs to a roadmap stage can only be
      // deleted from inside the roadmap — the menu shows why
      // instead of the Delete action.
      if (existing.stageId != null) {
        editMenu.add(
          PopupMenuItem(
            enabled: false,
            child: Text(s.deleteStagedTaskNote,
                style: TextStyle(
                    color: tokens.textTertiary, fontSize: 13)),
          ),
        );
      } else {
        editMenu.add(
          PopupMenuItem(
            value: 'delete',
            child: Text(s.deleteTask,
                style: TextStyle(color: tokens.danger)),
          ),
        );
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(live == null ? s.newTask : s.editTask),
        actions: [
          TextButton(
            onPressed: _saving ? null : _cancelEdit,
            child: Text(s.cancel),
          ),
          if (existing != null)
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'delete') _confirmDelete(existing);
                if (value == 'pause') _pauseTask(existing);
                if (value == 'resume') _resumeTask(existing);
              },
              itemBuilder: (ctx) => editMenu,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // --- Details ---
          SectionLabel(s.details),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: InputDecoration(labelText: s.title),
          ),
          const SizedBox(height: 12),
          // Controlled `value:` (not `initialValue:`) with a
          // membership guard on every dropdown below: the lists
          // (sites, users, stages, units) stream in and can lose
          // an entry while the editor is open, and a Dropdown
          // whose value is no longer among its items red-screens
          // ("exactly one item with value"). Re-validating the
          // value on every build falls back to null instead.
          DropdownButtonFormField<String>(
            initialValue: _siteId != null &&
                    sites.any((x) => x.id == _siteId)
                ? _siteId
                : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.site),
            items: [
              for (final site in sites)
                DropdownMenuItem(
                    value: site.id,
                    child: Text(site.name,
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              // A new site means a different roadmap and
              // different units: a stage or unit from the old
              // site must not carry over.
              _siteId = v;
              _stageId = null;
              _unitId = null;
              _dirty = true;
            }),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _unit,
            decoration: InputDecoration(labelText: s.unit),
          ),
          const SizedBox(height: 12),
          // Multi-select assignment: the picker renders its own
          // header row — "Assigned to" + search box — then the
          // selected people as pills. Matching people appear only
          // while searching, in a dropdown menu anchored under the
          // search box; there is no crew checklist.
          // Everyone can be assigned a task — workers, delivery,
          // managers and admins alike. The role is shown so it is
          // obvious an admin (Sam, Alex) can take tasks
          // too. Removing everyone leaves the task unassigned.
          AssigneePicker(
            users: users,
            selectedIds: _assigneeIds,
            onChanged: (next) =>
                setState(() { _assigneeIds = next; _dirty = true; }),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<TaskStatus>(
            initialValue: _status,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.status),
            items: [
              for (final st in TaskStatus.values)
                DropdownMenuItem(
                    value: st,
                    // A locked task cannot start or finish:
                    // those transitions are disabled here (and
                    // refused by _save too) instead of letting
                    // the editor bypass the locks Start and
                    // Done enforce everywhere else.
                    enabled: !(editLocked &&
                        (st == TaskStatus.inProgress ||
                            st == TaskStatus.done)),
                    child: Text(statusLabel(s, st),
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) =>
                setState(() { _status = v ?? _status; _dirty = true; }),
          ),
          if (editLocked)
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: Text(
                'Locked — start and finish are unavailable until the task is unlocked.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          const SizedBox(height: 24),
          // --- Schedule ---
          SectionLabel(s.schedule),
          const SizedBox(height: 12),
          AppDateField(
            label: s.startsOn,
            value: _startDate,
            onPick: (picked) =>
                setState(() { _startDate = picked; _dirty = true; }),
            onClear: () => setState(() { _startDate = null; _dirty = true; }),
            firstDate: DateTime(2025),
            lastDate: DateTime(2100),
          ),
          const SizedBox(height: 12),
          AppDateField(
            label: s.due,
            value: _dueDate,
            onPick: (picked) =>
                setState(() { _dueDate = picked; _dirty = true; }),
            onClear: () => setState(() { _dueDate = null; _dirty = true; }),
            firstDate: DateTime(2025),
            lastDate: DateTime(2100),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.arrow_forward_outlined, size: 17),
              label: Text(s.pushToTomorrow),
              style: TextButton.styleFrom(
                  foregroundColor: tokens.accentText),
              onPressed: () => setState(() {
                final now = DateTime.now();
                _dueDate = DateTime(now.year, now.month, now.day)
                    .add(const Duration(days: 1));
                if (_startDate != null && _startDate!.isAfter(_dueDate!)) {
                  _startDate = _dueDate;
                }
                _dirty = true;
              }),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: _dependsOnTaskId != null &&
                    others.any((t) => t.id == _dependsOnTaskId)
                ? _dependsOnTaskId
                : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.startsAfter),
            items: [
              DropdownMenuItem<String?>(
                  value: null,
                  child: Text(s.noneOption,
                      overflow: TextOverflow.ellipsis)),
              for (final t in others)
                DropdownMenuItem<String?>(
                    value: t.id,
                    child: Text(t.title,
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) =>
                setState(() { _dependsOnTaskId = v; _dirty = true; }),
          ),
          if (_dependsOnTaskId != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.canStartEarly,
                  style: const TextStyle(fontSize: 14)),
              value: _dependsSoft,
              onChanged: (v) {
                HapticFeedback.lightImpact();
                setState(() { _dependsSoft = v; _dirty = true; });
              },
            ),
          const SizedBox(height: 12),
          // Roadmap stage: the stages of the task's scope —
          // its unit's roadmap when it has a unit, the site
          // roadmap otherwise — plus "No stage". A task in a
          // stage stays locked until an admin starts that stage.
          DropdownButtonFormField<String?>(
            initialValue:
                _stageId != null && stages.any((x) => x.id == _stageId)
                    ? _stageId
                    : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.stage),
            items: [
              DropdownMenuItem<String?>(
                  value: null,
                  child: Text(s.noStage,
                      overflow: TextOverflow.ellipsis)),
              for (final st in stages)
                DropdownMenuItem<String?>(
                    value: st.id,
                    child: Text(st.name,
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) =>
                setState(() { _stageId = v; _dirty = true; }),
          ),
          const SizedBox(height: 12),
          // Apartment (unit): only the picked site's units,
          // plus "No unit". A unit is a grouping only — unlike
          // a stage it never locks the task. A task can have a
          // stage and a unit together, but the stage must come
          // from the same scope: its unit's roadmap when it has
          // a unit, the site roadmap otherwise.
          DropdownButtonFormField<String?>(
            initialValue:
                _unitId != null && units.any((x) => x.id == _unitId)
                    ? _unitId
                    : null,
            isExpanded: true,
            decoration: InputDecoration(labelText: s.apartment),
            items: [
              DropdownMenuItem<String?>(
                  value: null,
                  child: Text(s.noUnit,
                      overflow: TextOverflow.ellipsis)),
              for (final u in units)
                DropdownMenuItem<String?>(
                    value: u.id,
                    child: Text(u.name,
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() {
              // A different unit means a different roadmap: a
              // stage from the old scope must not carry over.
              _unitId = v;
              _stageId = null;
              _dirty = true;
            }),
          ),
          const SizedBox(height: 24),
          // --- On site ---
          SectionLabel(s.onSite),
          const SizedBox(height: 12),
          TextField(
            controller: _materials,
            maxLines: 4,
            decoration:
                InputDecoration(labelText: '${s.materials} (one per line)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: InputDecoration(labelText: s.notes),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.photoRequired,
                style: const TextStyle(fontSize: 14)),
            subtitle: Text(s.photoRequiredNote,
                style: TextStyle(
                    fontSize: 12, color: tokens.textTertiary)),
            value: _photoRequired,
            onChanged: (v) {
              HapticFeedback.lightImpact();
              setState(() { _photoRequired = v; _dirty = true; });
            },
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: PrimaryButton(
            label: s.save,
            onPressed: _saving
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    _save();
                  },
            loading: _saving,
          ),
        ),
      ),
    );
  }
}

/// What the Blocked dialog returns: the picked reason and the
/// note, read while the dialog is still mounted.
class _BlockedResult {
  final BlockedReason reason;
  final String note;
  const _BlockedResult({required this.reason, required this.note});
}

/// The "mark blocked" dialog. It owns its note controller (and
/// the reason state) and disposes the controller in dispose —
/// the parent reads the result before the dialog is gone, never
/// after, so the old "used after being disposed" crash cannot
/// happen here.
class _MarkBlockedDialog extends StatefulWidget {
  final AppStrings strings;
  const _MarkBlockedDialog({required this.strings});

  @override
  State<_MarkBlockedDialog> createState() => _MarkBlockedDialogState();
}

class _MarkBlockedDialogState extends State<_MarkBlockedDialog> {
  final _noteCtrl = TextEditingController();
  BlockedReason _reason = BlockedReason.waitingMaterials;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      title: Text(s.blockedReason),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<BlockedReason>(
            initialValue: _reason,
            items: [
              for (final r in BlockedReason.values)
                DropdownMenuItem(
                    value: r, child: Text(blockedReasonLabel(s, r))),
            ],
            onChanged: (v) =>
                setState(() => _reason = v ?? _reason),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _noteCtrl,
            decoration: InputDecoration(labelText: s.notes),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.cancel)),
        FilledButton(
            onPressed: () => Navigator.pop(
                context,
                _BlockedResult(
                    reason: _reason, note: _noteCtrl.text.trim())),
            child: Text(s.confirm)),
      ],
    );
  }
}

/// Dashed separator between materials rows (mockup detail).
class _DashedDivider extends StatelessWidget {
  const _DashedDivider();

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(
        painter: _DashedLinePainter(
          tokens.border,
        ),
      ),
    );
  }
}

class _DashedLinePainter extends CustomPainter {
  final Color color;
  const _DashedLinePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 5.0;
    const gap = 4.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, 0.5), Offset(x + dash, 0.5), paint);
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter old) => old.color != color;
}

/// Thumbnail for a photo whose upload failed (still only on this
/// device). Reads the bytes instead of File so it renders on web
/// too (blob URLs included); a placeholder shows while the bytes
/// load or when the file is gone.
class _PendingPhotoThumb extends StatelessWidget {
  final String path;
  const _PendingPhotoThumb({required this.path});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: XFile(path).readAsBytes(),
      builder: (context, snap) {
        if (snap.hasData) {
          return Image.memory(snap.data!,
              width: 96, height: 96, fit: BoxFit.cover);
        }
        return Container(
          width: 96,
          height: 96,
          color: AppTokens.of(context).surfaceRaised,
          child: Icon(Icons.image_outlined,
              color: AppTokens.of(context).textTertiary),
        );
      },
    );
  }
}
