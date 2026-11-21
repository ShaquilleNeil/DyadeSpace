import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_strings.dart';
import '../../models/app_user.dart';
import '../../models/delivery_run.dart';
import '../../models/material_request.dart';
import '../../models/run_stop.dart';
import '../../models/task_item.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/material_requests_provider.dart';
import '../../providers/sites_provider.dart';
import '../../providers/stages_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../services/run_sync_service.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/status_indicator.dart';

/// One editable stop in the builder. Stops loaded from an existing
/// run keep their original RunStop in [existing], so status,
/// photo and timestamps survive an edit untouched; on save the
/// stop is rebuilt with its new orderIndex and everything else
/// carried over.
class _StopDraft {
  final String id;
  final RunStop? existing;
  final TextEditingController title;
  final TextEditingController address;
  final TextEditingController notes;
  final TextEditingController items;
  StopKind kind;
  String? scheduledTime;
  String? taskId;
  /// Material request this stop serves (a pickup added from the
  /// requests queue or the approved-requests list below). A
  /// request-linked stop is still just a pickup — completing it
  /// marks the request delivered.
  String? materialRequestId;

  _StopDraft._({
    required this.id,
    required this.existing,
    required this.title,
    required this.address,
    required this.notes,
    required this.items,
    required this.kind,
    this.scheduledTime,
    this.taskId,
    this.materialRequestId,
  });

  factory _StopDraft.fromStop(RunStop s) => _StopDraft._(
        id: s.id,
        existing: s,
        title: TextEditingController(text: s.title),
        address: TextEditingController(text: s.address),
        notes: TextEditingController(text: s.notes),
        items: TextEditingController(
            text: s.items.map((i) => i.label).join('\n')),
        kind: s.kind,
        scheduledTime: s.scheduledTime,
        taskId: s.taskId,
        materialRequestId: s.materialRequestId,
      );

  factory _StopDraft.fresh(String id) => _StopDraft._(
        id: id,
        existing: null,
        title: TextEditingController(),
        address: TextEditingController(),
        notes: TextEditingController(),
        items: TextEditingController(),
        kind: StopKind.dropoff,
      );

  /// A copy of [s] as a FRESH stop for another day: new id, and
  /// no status/photo/timestamps/failure carried over; checklist
  /// items are kept by label but start unchecked (existing stays
  /// null on purpose, so build() applies the fresh defaults -
  /// including photoPending false). A request link is NOT
  /// copied: the copy is a fresh stop, and the request stays
  /// attached to its own run until a manager re-adds it.
  factory _StopDraft.copied(RunStop s, String newId) => _StopDraft._(
        id: newId,
        existing: null,
        title: TextEditingController(text: s.title),
        address: TextEditingController(text: s.address),
        notes: TextEditingController(text: s.notes),
        items: TextEditingController(
            text: s.items.map((i) => i.label).join('\n')),
        kind: s.kind,
        scheduledTime: s.scheduledTime,
        taskId: s.taskId,
      );

  /// A pickup draft for an approved material request: titled
  /// with the item, addressed to the request's site, one
  /// checklist row for the quantity, and linked back to the
  /// request so completing it marks the request delivered.
  factory _StopDraft.forRequest(
    String id,
    MaterialRequest request,
    String siteAddress,
  ) =>
      _StopDraft._(
        id: id,
        existing: null,
        title: TextEditingController(text: request.item),
        address: TextEditingController(text: siteAddress),
        notes: TextEditingController(
          text: [
            'Requested by ${request.requesterName}',
            if (request.note.isNotEmpty) request.note,
          ].join(' — '),
        ),
        items: TextEditingController(
            text: '${request.quantity} × ${request.item}'),
        kind: StopKind.pickup,
        materialRequestId: request.id,
      );

  RunStop build(int orderIndex) {
    final labels = items.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    // Keep the checked state of items that survive the edit
    // (matched by label); new labels start unchecked.
    final oldDoneByLabel = {
      for (final i in existing?.items ?? const <StopItem>[]) i.label: i.done,
    };
    return RunStop(
      id: id,
      orderIndex: orderIndex,
      title: title.text.trim(),
      address: address.text.trim(),
      notes: notes.text.trim(),
      kind: kind,
      status: existing?.status ?? StopStatus.pending,
      photoUrl: existing?.photoUrl,
      photoPending: existing?.photoPending ?? false,
      completedAt: existing?.completedAt,
      scheduledTime: scheduledTime,
      items: [
        for (final label in labels)
          StopItem(label: label, done: oldDoneByLabel[label] ?? false),
      ],
      failReason: existing?.failReason,
      failNote: existing?.failNote,
      taskId: taskId,
      materialRequestId: materialRequestId,
      arrivedAt: existing?.arrivedAt,
      delayedMinutes: existing?.delayedMinutes,
      delayedAt: existing?.delayedAt,
      photoUrls: existing?.photoUrls ?? const [],
      autoAdded: existing?.autoAdded ?? false,
      carriedOver: existing?.carriedOver ?? false,
      carriedFromStopId: existing?.carriedFromStopId,
    );
  }

  void dispose() {
    title.dispose();
    address.dispose();
    notes.dispose();
    items.dispose();
  }
}

/// A delivery run form (admin/manager): pick the day and the
/// driver, line up the stops in order, save. Two modes:
/// - CREATE (no [existingRun]): ALWAYS a blank form. An existing
///   run for the chosen day + driver is never auto-loaded; on
///   Save, if one exists, a dialog asks before a duplicate is
///   created (open the existing one instead / create a second
///   run anyway / cancel).
/// - EDIT ([existingRun] given): the form preloads that run and
///   Save updates the same document.
/// Runs are whole documents (stops embedded), and there is still
/// no run service - like the driver screen, this talks to
/// Firestore directly.
class RunBuilderScreen extends ConsumerStatefulWidget {
  final DeliveryRun? existingRun;
  const RunBuilderScreen({super.key, this.existingRun});

  @override
  ConsumerState<RunBuilderScreen> createState() => _RunBuilderScreenState();
}

class _RunBuilderScreenState extends ConsumerState<RunBuilderScreen> {
  DateTime _date = _dayOnly(DateTime.now());
  String? _driverId;
  List<_StopDraft> _stops = [];
  bool _saving = false;
  bool _driverDefaulted = false;

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _isEdit => widget.existingRun != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existingRun;
    if (existing != null) {
      _date = _dayOnly(existing.date);
      _driverId = existing.driverId;
      _stops = [
        for (final st in existing.orderedStops) _StopDraft.fromStop(st),
      ];
    }
  }

  @override
  void dispose() {
    for (final d in _stops) {
      d.dispose();
    }
    super.dispose();
  }

  /// Turns a materials-blocked task into a pickup stop draft:
  /// linked to the task, titled "Materials for <task>", with the
  /// task's materials list as the stop notes. Address stays
  /// empty - the manager fills in where to pick the load up.
  void _addPickupForTask(AppStrings s, TaskItem task) {
    final draft = _StopDraft.fresh(
        FirebaseFirestore.instance.collection('runs').doc().id);
    draft.kind = StopKind.pickup;
    draft.taskId = task.id;
    draft.title.text = s.materialsFor(task.title);
    draft.notes.text = task.materials.join(', ');
    setState(() => _stops.add(draft));
  }

  /// Copy a run: pick the SOURCE day (default yesterday), take
  /// that day's run for the currently selected driver (else the
  /// first run that day), and load its stops as fresh drafts for
  /// the CURRENT target date + driver. Saving then follows the
  /// normal path. (Week-to-week duplication is just: open next
  /// week's day, copy last week's run.)
  Future<void> _copyRun() async {
    final s = ref.read(stringsProvider);
    final sourceDate = await showDatePicker(
      context: context,
      initialDate: _date.subtract(const Duration(days: 1)),
      firstDate: DateTime(2025),
      lastDate: DateTime(2100),
      helpText: s.copyFromDate,
    );
    if (sourceDate == null || !mounted) return;
    final day = _dayOnly(sourceDate);
    DeliveryRun? source;
    try {
      // Date-range query on the one day being copied — never a
      // whole-collection read as runs accumulate.
      final snap = await FirebaseFirestore.instance
          .collection('runs')
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(day))
          .where('date',
              isLessThan: Timestamp.fromDate(day.add(const Duration(days: 1))))
          .get();
      final thatDay =
          snap.docs.map(DeliveryRun.fromFirestore).toList();
      for (final r in thatDay) {
        if (r.driverId == _driverId) {
          source = r;
          break;
        }
      }
      source ??= thatDay.isEmpty ? null : thatDay.first;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.runSaveFailed('$e'))),
        );
      }
      return;
    }
    if (!mounted) return;
    if (source == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.runCopyNone)),
      );
      return;
    }
    if (_stops.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(s.copyRun),
          content: Text(s.runCopyConfirm),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                // The theme gives every FilledButton an infinite minimum
                // width — bound it to its content (same fix as the
                // topbar button).
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                ),
                child: Text(s.confirm)),
          ],
        ),
      );
      if (ok != true || !mounted) return;
    }
    final old = _stops;
    final drafts = [
      for (final st in source.orderedStops)
        _StopDraft.copied(
          st,
          FirebaseFirestore.instance.collection('runs').doc().id,
        ),
    ];
    setState(() => _stops = drafts);
    for (final d in old) {
      d.dispose();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.runCopied(drafts.length))),
    );
  }

  /// Drivers are the users with the delivery role; until one
  /// exists, fall back to every active user so a run can still
  /// be planned.
  List<AppUser> _pickDrivers(List<AppUser> users) {
    final delivery = users
        .where((u) => u.active && u.role == UserRole.delivery)
        .toList();
    if (delivery.isNotEmpty) return delivery;
    return users.where((u) => u.active).toList();
  }

  /// CREATE mode's duplicate guard: if a run already exists for
  /// the chosen day + driver, ask BEFORE writing - never a
  /// silent duplicate, never a silent overwrite. Returns true
  /// when the save may proceed (no duplicate, or the manager
  /// chose "create a second run anyway"). Choosing "open the
  /// existing run instead" pops this blank form, pushes the
  /// builder in edit mode for that run, and returns false.
  Future<bool> _confirmDuplicateIfAny() async {
    final s = ref.read(stringsProvider);
    DeliveryRun? existing;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('runs')
          .where('driverId', isEqualTo: _driverId)
          .get();
      for (final doc in snap.docs) {
        final r = DeliveryRun.fromFirestore(doc);
        if (_dayOnly(r.date) == _date) {
          existing = r;
          break;
        }
      }
    } catch (e) {
      // The check itself failed: surface it and stop rather
      // than risk writing a duplicate blind.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.runSaveFailed('$e'))),
        );
      }
      return false;
    }
    if (existing == null) return true;
    if (!mounted) return false;
    final users = ref.read(allUsersProvider).valueOrNull ?? [];
    var driverName = s.driver;
    for (final u in users) {
      if (u.id == _driverId) driverName = u.name;
    }
    final found = existing;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.runExistsTitle),
        content: Text(s.runExistsMessage(driverName, found.stops.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'open'),
            child: Text(s.openExistingRun),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'second'),
            // The theme gives every FilledButton an infinite minimum
            // width — bound it to its content (same fix as the
            // topbar button).
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
            ),
            child: Text(s.createSecondRun),
          ),
        ],
      ),
    );
    if (choice == 'second') return true;
    if (choice == 'open' && mounted) {
      final nav = Navigator.of(context);
      nav.pop();
      nav.push(
        MaterialPageRoute(
          builder: (_) => RunBuilderScreen(existingRun: found),
        ),
      );
    }
    return false;
  }

  Future<void> _save() async {
    final s = ref.read(stringsProvider);
    final me = ref.read(currentUserProvider).valueOrNull;
    if (me == null) return;
    if (_driverId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.pickDriverFirst)),
      );
      return;
    }
    if (_stops.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.runNeedsStop)),
      );
      return;
    }
    if (_stops.any((d) => d.title.text.trim().isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.stopNeedsTitle)),
      );
      return;
    }
    if (!_isEdit) {
      final proceed = await _confirmDuplicateIfAny();
      if (!proceed || !mounted) return;
    }
    setState(() => _saving = true);
    final stops = [
      for (var i = 0; i < _stops.length; i++) _stops[i].build(i),
    ];
    String? savedRunId;
    try {
      final runs = FirebaseFirestore.instance.collection('runs');
      if (_isEdit) {
        savedRunId = widget.existingRun!.id;
        // Transactional merge, like the driver screen's
        // _saveStops: the fresh run doc is read inside the
        // transaction and this editor's stops are merged into
        // it, so a driver closing stops (or a reorder landing
        // from another editor) at the same moment is not
        // overwritten. This editor's version wins for the stops
        // it knew about, in this editor's order; stops the fresh
        // doc has that this editor never saw are kept at the
        // end; a stop the fresh doc no longer has was deleted
        // meanwhile and is not resurrected. The plain
        // .update({'stops': ...}) this replaced clobbered all
        // of that from a stale draft.
        await FirebaseFirestore.instance.runTransaction((tx) async {
          final docRef = runs.doc(savedRunId!);
          final snap = await tx.get(docRef);
          if (!snap.exists) {
            throw StateError('run-not-found');
          }
          final fresh = DeliveryRun.fromFirestore(snap).stops;
          final freshIds = {for (final f in fresh) f.id};
          final callerIds = {for (final s in stops) s.id};
          final merged = <RunStop>[
            for (final s in stops)
              if (freshIds.contains(s.id)) s,
            for (final f in fresh)
              if (!callerIds.contains(f.id)) f,
          ];
          tx.update(docRef, {
            'date': Timestamp.fromDate(_date),
            'driverId': _driverId,
            'stops': merged.map((x) => x.toMap()).toList(),
          });
        });
      } else {
        final run = DeliveryRun(
          id: '',
          date: _date,
          driverId: _driverId!,
          createdBy: me.id,
          stops: stops,
        );
        final docRef = await runs.add(run.toMap());
        savedRunId = docRef.id;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.runSaveFailed('$e'))),
        );
      }
      return;
    }
    // Requests attached in this editor: any approved request
    // whose id now appears on a saved stop becomes onRun for
    // this run. A failure here is NOT swallowed any more: the
    // sync is retried once, and a persistent failure stops the
    // save from reporting success — a request left approved
    // while its stop sits on this run could otherwise be
    // attached to a second run too.
    final requestFailures = <String>[];
    Future<void> syncRequest(
        MaterialRequest request, Future<void> Function() call) async {
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          await call();
          return;
        } catch (_) {
          if (attempt == 1) requestFailures.add(request.id);
        }
      }
    }

    final requestIds = {
      for (final st in stops)
        if (st.materialRequestId != null) st.materialRequestId!,
    };
    if (requestIds.isNotEmpty) {
      final requests = ref.read(materialRequestsProvider).valueOrNull ?? [];
      final service = ref.read(materialRequestServiceProvider);
      for (final request in requests) {
        if (requestIds.contains(request.id) &&
            request.status == MaterialRequestStatus.approved) {
          await syncRequest(
              request, () => service.markOnRun(request, savedRunId));
        }
      }
    }
    // Stops removed from a saved run: their requests go back
    // to approved so they can be attached again. Only for
    // requests that were onRun on THIS run — a stop deleted
    // from a draft that was never saved reverts nothing.
    if (_isEdit) {
      final savedRequestIds = {
        for (final st in stops)
          if (st.materialRequestId != null) st.materialRequestId!,
      };
      final removedRequestIds = {
        for (final st in widget.existingRun!.orderedStops)
          if (st.materialRequestId != null &&
              !savedRequestIds.contains(st.materialRequestId))
            st.materialRequestId!,
      };
      if (removedRequestIds.isNotEmpty) {
        final requests = ref.read(materialRequestsProvider).valueOrNull ?? [];
        final service = ref.read(materialRequestServiceProvider);
        for (final request in requests) {
          if (removedRequestIds.contains(request.id) &&
              request.status == MaterialRequestStatus.onRun &&
              request.runId == widget.existingRun!.id) {
            await syncRequest(
                request, () => service.revertToApproved(request));
          }
        }
      }
    }
    if (requestFailures.isNotEmpty) {
      // The run itself is saved; the requests are not in sync
      // with it. Stay on the editor and say so plainly —
      // never show "run saved" when part of the save failed.
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // TODO(l10n): move to AppStrings.
            content: Text(
                'Run saved, but ${requestFailures.length} material '
                'request(s) could not be updated. Save again to retry.'),
          ),
        );
      }
      return;
    }
    // Reconcile the saved run (carry-over of unfinished stops)
    // before leaving. Only when the task list is loaded - with
    // no tasks in hand the sync could not tell a qualifying stop
    // from a stale one, so it waits for the driver screen's
    // own sync on open instead.
    final allTasks = ref.read(allTasksProvider).value;
    if (allTasks != null) {
      try {
        await RunSyncService.syncRun(
          DeliveryRun(
            id: savedRunId,
            date: _date,
            driverId: _driverId!,
            createdBy: me.id,
            stops: stops,
          ),
          allTasks: allTasks,
          stageIndex: ref.read(stageIndexProvider),
        );
      } catch (_) {
        // Best-effort: the driver screen syncs on open anyway.
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.runSaved)),
      );
      Navigator.of(context).pop();
    }
  }

  /// Deletes this run (edit mode only): after confirmation the
  /// run doc goes, with its stops. Linked tasks and material
  /// requests are NOT deleted — a request riding on this run
  /// goes back to approved so it can be attached to another
  /// run. Managers only: this screen never renders for other
  /// roles.
  Future<void> _deleteRun() async {
    final s = ref.read(stringsProvider);
    final run = widget.existingRun;
    if (run == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.delete),
        // TODO(l10n): move to AppStrings.
        content: Text(
            'Delete this run? Its ${run.stops.length} stop(s) go with it. '
            'Linked tasks and material requests are kept — requests on '
            'this run go back to Approved so they can ride another run.'),
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
    if (ok != true || !mounted) return;
    setState(() => _saving = true);
    try {
      final requests = ref.read(materialRequestsProvider).valueOrNull ?? [];
      final onThisRun = requests
          .where((r) =>
              r.status == MaterialRequestStatus.onRun && r.runId == run.id)
          .toList();
      // Chunked like the roadmap deletes: a run's request count
      // is small, but a batch must never exceed 500 writes.
      var batch = FirebaseFirestore.instance.batch();
      var writes = 0;
      Future<void> flush() async {
        if (writes == 0) return;
        await batch.commit();
        batch = FirebaseFirestore.instance.batch();
        writes = 0;
      }

      for (final request in onThisRun) {
        batch.update(
          FirebaseFirestore.instance
              .collection('materialRequests')
              .doc(request.id),
          {
            'status': MaterialRequestStatus.approved.name,
            'runId': null,
          },
        );
        writes++;
        if (writes >= 400) await flush();
      }
      await flush();
      await FirebaseFirestore.instance
          .collection('runs')
          .doc(run.id)
          .delete();
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          // TODO(l10n): move to AppStrings.
          SnackBar(content: Text('Could not delete the run: $e')),
        );
      }
      return;
    }
    if (mounted) {
      // TODO(l10n): move to AppStrings.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Run deleted.')),
      );
      Navigator.of(context).pop();
    }
  }

  TimeOfDay? _parseTime(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final drivers = _pickDrivers(users);
    final allTasks = ref.watch(allTasksProvider).valueOrNull ?? [];
    final siteById = ref.watch(siteByIdProvider);
    // Tasks blocked on materials suggest their own pickup stop -
    // unless a stop in this editor already serves that task.
    final linkedTaskIds = _stops.map((d) => d.taskId).toSet();
    final suggestions = allTasks
        .where((t) =>
            t.status == TaskStatus.blocked &&
            t.blockedReason == BlockedReason.waitingMaterials &&
            !linkedTaskIds.contains(t.id))
        .toList();
    // Approved material requests not yet on a stop in this
    // editor: one tap adds a linked pickup stop for them.
    final approvedRequests =
        ref.watch(approvedMaterialRequestsProvider).valueOrNull ?? [];
    final attachedRequestIds = {
      for (final d in _stops)
        if (d.materialRequestId != null) d.materialRequestId!,
    };
    final attachableRequests = approvedRequests
        .where((r) => !attachedRequestIds.contains(r.id))
        .toList();

    // Default to the first driver once the user list arrives.
    // CREATE mode stays blank either way - nothing auto-loads.
    if (_driverId == null && drivers.isNotEmpty && !_driverDefaulted) {
      _driverDefaulted = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _driverId != null) return;
        setState(() => _driverId = drivers.first.id);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? s.editRun : s.planRun),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: s.delete,
              onPressed: _saving ? null : _deleteRun,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(s.date),
            subtitle:
                Text(DateFormat('EEE MMM d, yyyy').format(_date)),
            trailing: IconButton(
              icon: const Icon(Icons.calendar_month_outlined),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2025),
                  lastDate: DateTime(2100),
                );
                if (picked != null) {
                  setState(() => _date = _dayOnly(picked));
                }
              },
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: _driverId != null &&
                    drivers.any((u) => u.id == _driverId)
                ? _driverId
                : null,
            decoration: InputDecoration(
                labelText: s.driver, border: const OutlineInputBorder()),
            items: [
              for (final u in drivers)
                DropdownMenuItem(value: u.id, child: Text(u.name)),
            ],
            onChanged: (v) {
              setState(() => _driverId = v);
            },
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: Text(s.copyRun),
              onPressed: _copyRun,
            ),
          ),
          const SizedBox(height: 8),
          if (suggestions.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(s.materialsSuggestions,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final t in suggestions)
              _suggestionCard(context, s, t, siteById[t.siteId]?.name ?? ''),
            const SizedBox(height: 8),
          ],
          if (attachableRequests.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 2),
              child: Text(s.materialRequestApprovedTitle,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            for (final r in attachableRequests)
              _requestCard(context, s, r, siteById[r.siteId]?.name ?? '',
                  siteById[r.siteId]?.address ?? ''),
            const SizedBox(height: 8),
          ],
          for (var i = 0; i < _stops.length; i++)
            _stopCard(context, s, i, allTasks),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: Text(s.addStop),
            onPressed: () => setState(() => _stops.add(_StopDraft.fresh(
                FirebaseFirestore.instance.collection('runs').doc().id))),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(s.save),
          ),
        ],
      ),
    );
  }

  /// One materials-blocked task offered as a ready-made pickup.
  Widget _suggestionCard(
      BuildContext context, AppStrings s, TaskItem task, String siteName) {
    final tokens = AppTokens.of(context);
    final subtitleParts = <String>[
      if (siteName.isNotEmpty) siteName,
      if (task.materials.isNotEmpty) task.materials.join(', '),
    ];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        // A materials suggestion is a thing, not a person: neutral
        // grey dot instead of the default blue.
        leading: CircleAvatar(
          backgroundColor: tokens.surfaceRaised,
          child: Icon(Icons.inventory_2_outlined,
              size: 19, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        title: Text(task.title),
        subtitle:
            subtitleParts.isEmpty ? null : Text(subtitleParts.join('\n')),
        trailing: TextButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(s.addPickupStop),
          onPressed: () => _addPickupForTask(s, task),
        ),
      ),
    );
  }

  /// One approved material request offered as a ready-made
  /// pickup stop, linked back to the request.
  Widget _requestCard(BuildContext context, AppStrings s,
      MaterialRequest request, String siteName, String siteAddress) {
    final tokens = AppTokens.of(context);
    final subtitleParts = <String>[
      if (siteName.isNotEmpty) siteName,
      s.materialRequestedBy(request.requesterName),
      if (request.neededBy != null)
        '${s.materialNeededBy} ${DateFormat('EEE MMM d').format(request.neededBy!)}',
    ];
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: tokens.surfaceRaised,
          child: Icon(Icons.inventory_2_outlined,
              size: 19, color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        title: Text('${request.quantity} × ${request.item}'),
        subtitle:
            subtitleParts.isEmpty ? null : Text(subtitleParts.join('\n')),
        trailing: TextButton.icon(
          icon: const Icon(Icons.add, size: 18),
          label: Text(s.materialRequestAddToRun),
          onPressed: () => setState(() => _stops.add(
                _StopDraft.forRequest(
                  FirebaseFirestore.instance.collection('runs').doc().id,
                  request,
                  siteAddress,
                ),
              )),
        ),
      ),
    );
  }

  Widget _stopCard(
      BuildContext context, AppStrings s, int i, List<TaskItem> allTasks) {
    final tokens = AppTokens.of(context);
    final draft = _stops[i];
    final existing = draft.existing;
    final closed = existing != null && existing.status != StopStatus.pending;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Text(s.stopNumber(i + 1),
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 19),
                tooltip: s.moveUp,
                onPressed: i == 0
                    ? null
                    : () => setState(() {
                          final d = _stops.removeAt(i);
                          _stops.insert(i - 1, d);
                        }),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 19),
                tooltip: s.moveDown,
                onPressed: i == _stops.length - 1
                    ? null
                    : () => setState(() {
                          final d = _stops.removeAt(i);
                          _stops.insert(i + 1, d);
                        }),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 19),
                tooltip: s.removeStop,
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: Text(s.confirmDeleteStopDraft),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: Text(s.cancel),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          // The theme gives every FilledButton an infinite minimum
                          // width — bound it to its content (same fix as the
                          // topbar button).
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 52),
                          ),
                          child: Text(s.confirm),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    setState(() {
                      _stops.removeAt(i).dispose();
                    });
                  }
                },
              ),
            ]),
            if (closed)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  existing.status == StopStatus.completed
                      ? s.done
                      : '${s.failedStop} - ${stopFailReasonLabel(s, existing.failReason)}',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: existing.status == StopStatus.completed
                          ? tokens.statusDone
                          : tokens.danger),
                ),
              ),
            TextField(
              controller: draft.title,
              decoration: InputDecoration(
                  labelText: s.title, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<StopKind>(
              initialValue: draft.kind,
              decoration: InputDecoration(
                  labelText: s.stopKind,
                  border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem(
                    value: StopKind.pickup, child: Text(s.pickup)),
                DropdownMenuItem(
                    value: StopKind.dropoff, child: Text(s.dropoff)),
              ],
              onChanged: (v) => setState(() => draft.kind = v ?? draft.kind),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: draft.address,
              decoration: InputDecoration(
                  labelText: s.address, border: const OutlineInputBorder()),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.beThereBy),
              subtitle: Text(draft.scheduledTime ?? '-'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (draft.scheduledTime != null)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () =>
                          setState(() => draft.scheduledTime = null),
                    ),
                  IconButton(
                    icon: const Icon(Icons.schedule_outlined),
                    onPressed: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime:
                            _parseTime(draft.scheduledTime) ??
                                TimeOfDay.now(),
                      );
                      if (picked != null) {
                        setState(() =>
                            draft.scheduledTime = _formatTime(picked));
                      }
                    },
                  ),
                ],
              ),
            ),
            TextField(
              controller: draft.items,
              maxLines: 3,
              decoration: InputDecoration(
                  labelText: s.itemsOnePerLine,
                  border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String?>(
              initialValue: draft.taskId != null &&
                      allTasks.any((t) => t.id == draft.taskId)
                  ? draft.taskId
                  : null,
              decoration: InputDecoration(
                  labelText: s.linkedTask,
                  border: const OutlineInputBorder()),
              items: [
                DropdownMenuItem<String?>(
                    value: null, child: Text(s.noneOption)),
                for (final t in allTasks)
                  DropdownMenuItem<String?>(
                      value: t.id, child: Text(t.title)),
              ],
              onChanged: (v) => setState(() => draft.taskId = v),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: draft.notes,
              maxLines: 2,
              decoration: InputDecoration(
                  labelText: s.notes, border: const OutlineInputBorder()),
            ),
          ],
        ),
      ),
    );
  }
}
