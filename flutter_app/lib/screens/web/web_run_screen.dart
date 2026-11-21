import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_strings.dart';
import '../../models/delivery_run.dart';
import '../../models/run_stop.dart';
import '../../providers/locale_provider.dart';
import '../../providers/runs_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/run_progress_bar.dart';
import '../../widgets/status_indicator.dart';
import '../manager/run_builder_screen.dart';
import 'web_shared.dart';

/// One run, drivable from the web: stops with their status, the
/// odometer reading, and the progress bar. Opened from the
/// Overview's "View run" button. The run is watched live (by id)
/// so a stop completed here — or by the driver on the phone —
/// updates this screen at once.
///
/// Driving a run mirrors the phone driver screen's writes:
/// complete / fail a stop, mark arrival, report a delay,
/// odometer, stop photos, and completing a drop-off marks the
/// linked task's materials on site. Stop writes go through the
/// same transactional merge the phone screen uses, so a manager
/// edit landing at the same moment is not overwritten.
/// (Edit Run still opens the run builder for structural edits.)
class WebRunScreen extends ConsumerStatefulWidget {
  final DeliveryRun run;
  final String? driverName;
  const WebRunScreen({super.key, required this.run, this.driverName});

  @override
  ConsumerState<WebRunScreen> createState() => _WebRunScreenState();
}

class _WebRunScreenState extends ConsumerState<WebRunScreen> {
  final _odoStartCtrl = TextEditingController();
  final _odoEndCtrl = TextEditingController();
  String? _odoRunId;

  @override
  void dispose() {
    _odoStartCtrl.dispose();
    _odoEndCtrl.dispose();
    super.dispose();
  }

  // ---------- Firestore writes (phone driver screen's shape) ----------

  /// Runs are read and written whole (stops are embedded), so every
  /// stop change rewrites the stops array of the run doc. The write
  /// runs in a transaction: the fresh run doc is read inside it and
  /// the caller's stops are merged into that fresh list, so a manager
  /// edit landing at the same moment is not overwritten.
  Future<void> _saveStops(DeliveryRun run, List<RunStop> stops) async {
    final docRef =
        FirebaseFirestore.instance.collection('runs').doc(run.id);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) return;
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
        'stops': merged.map((s) => s.toMap()).toList(),
      });
    });
  }

  Future<void> _saveStop(DeliveryRun run, RunStop updated) async {
    final stops =
        run.stops.map((s) => s.id == updated.id ? updated : s).toList();
    await _saveStops(run, stops);
  }

  Future<void> _saveMileage(DeliveryRun run) async {
    final s = ref.read(stringsProvider);
    final start = int.tryParse(_odoStartCtrl.text.trim());
    final end = int.tryParse(_odoEndCtrl.text.trim());
    if (start == null || end == null || end < start) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.driverMileageInvalid)),
      );
      return;
    }
    await FirebaseFirestore.instance.collection('runs').doc(run.id).update({
      'odometerStart': start,
      'odometerEnd': end,
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.driverMileageSaved)),
    );
  }

  Future<void> _markArrived(DeliveryRun run, RunStop stop) async {
    final s = ref.read(stringsProvider);
    await _saveStop(run, stop.copyWith(arrivedAt: DateTime.now()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.driverArrivedMarked)),
    );
  }

  Future<void> _markDelayed(
      DeliveryRun run, RunStop stop, int minutes) async {
    final s = ref.read(stringsProvider);
    await _saveStop(run, stop.copyWith(
      delayedMinutes: minutes,
      delayedAt: DateTime.now(),
    ));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.driverDelayedBy(minutes))),
    );
  }

  /// Completes a stop. A photo is appreciated but never a gate
  /// on web: the dialog offers "Add photo and complete" (camera
  /// / file picker) and "Complete without photo". A failed
  /// upload shows an error and leaves the dialog open — the
  /// photo is never silently dropped, and the stop can still be
  /// completed without it.
  Future<void> _completeStop(DeliveryRun run, RunStop stop) async {
    final s = ref.read(stringsProvider);
    String? photoUrl;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(stop.title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.runStopPhotoHint),
              if (photoUrl != null) ...[
                const SizedBox(height: 12),
                Text(s.photoProof,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel),
            ),
            OutlinedButton(
              onPressed: () async {
                try {
                  final url = await ref
                      .read(photoServiceProvider)
                      .takePhotoAndUpload('runPhotos', run.id);
                  if (url != null && ctx.mounted) {
                    setState(() => photoUrl = url);
                  }
                } catch (_) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text(s.photoUploadFailed)),
                    );
                  }
                }
              },
              child: Text(photoUrl == null
                  ? s.addPhoto
                  : s.runStopAddPhotoAndComplete),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
              ),
              child: Text(photoUrl == null
                  ? s.runStopCompleteWithoutPhoto
                  : (stop.kind == StopKind.pickup ? s.pickedUp : s.delivered)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final updated = run.stops
        .map((x) => x.id == stop.id
            ? x.copyWith(
                status: StopStatus.completed,
                photoUrl: photoUrl,
                completedAt: DateTime.now(),
              )
            : x)
        .toList();
    await _saveStops(run, updated);
    // A completed drop-off linked to a task means that task's
    // materials are now on site. The task itself is NOT
    // completed here. A deleted task must not throw after the
    // stop is saved, so the mark is best-effort.
    final taskId = stop.taskId;
    if (stop.kind == StopKind.dropoff && taskId != null) {
      try {
        await ref.read(taskServiceProvider).markMaterialsOnSite(taskId);
      } catch (_) {
        // The stop is already complete; a gone task changes
        // nothing about the run.
      }
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.runStopCompleted)),
    );
  }

  /// "Why couldn't this stop be completed?" — reason + optional
  /// note + optional evidence photo. The save happens after the
  /// sheet closes (and inside the transactional _saveStops),
  /// never across the dialog's pop.
  Future<void> _failStop(DeliveryRun run, RunStop stop) async {
    final s = ref.read(stringsProvider);
    String reasonKey = stopFailReasonKeys.first;
    final noteCtrl = TextEditingController();
    String? photoUrl;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(s.couldNotComplete),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: reasonKey,
                isExpanded: true,
                items: [
                  for (final key in stopFailReasonKeys)
                    DropdownMenuItem(
                        value: key,
                        child: Text(stopFailReasonLabel(s, key))),
                ],
                onChanged: (v) =>
                    setState(() => reasonKey = v ?? reasonKey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: noteCtrl,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: s.whyNotComplete,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    icon:
                        const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: Text(s.addPhoto),
                    onPressed: () async {
                      try {
                        final url = await ref
                            .read(photoServiceProvider)
                            .takePhotoAndUpload('runPhotos', run.id);
                        if (url != null && ctx.mounted) {
                          setState(() => photoUrl = url);
                        }
                      } catch (_) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                                content: Text(s.photoUploadFailed)),
                          );
                        }
                      }
                    },
                  ),
                  if (photoUrl != null) ...[
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(photoUrl!,
                          width: 44, height: 44, fit: BoxFit.cover),
                    ),
                  ],
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 52),
              ),
              child: Text(s.failedStop),
            ),
          ],
        ),
      ),
    );
    noteCtrl.dispose();
    if (confirmed != true || !mounted) return;
    final updated = run.stops
        .map((x) => x.id == stop.id
            ? x.copyWith(
                status: StopStatus.failed,
                failReason: reasonKey,
                failNote:
                    noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                photoUrl: photoUrl,
                completedAt: DateTime.now(),
              )
            : x)
        .toList();
    await _saveStops(run, updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(s.runStopFailed)),
    );
  }

  /// Extra proof photo on a stop (on top of the completion
  /// photo). Uploaded straight away; when the upload fails the
  /// photo is NOT queued on web (the web queue is a no-op) — the
  /// error shows and the photo stays un-added, never silently
  /// dropped.
  Future<void> _addProofPhoto(DeliveryRun run, RunStop stop) async {
    final s = ref.read(stringsProvider);
    String? url;
    try {
      url = await ref
          .read(photoServiceProvider)
          .takePhotoAndUpload('runPhotos', run.id);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.photoUploadFailed)),
      );
      return;
    }
    if (url == null || !mounted) return;
    await _saveStop(
        run, stop.copyWith(photoUrls: [...stop.photoUrls, url]));
  }

  Future<void> _toggleItem(
      DeliveryRun run, RunStop stop, int index, bool value) async {
    final items = [
      for (var i = 0; i < stop.items.length; i++)
        i == index ? stop.items[i].copyWith(done: value) : stop.items[i],
    ];
    await _saveStop(run, stop.copyWith(items: items));
  }

  bool _pickupGateOpen(RunStop stop) =>
      stop.kind == StopKind.pickup &&
      stop.items.isNotEmpty &&
      stop.items.any((i) => !i.done);

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final runs = ref.watch(allRunsProvider).valueOrNull ?? [];
    // Live run by id; the snapshot passed in is the fallback
    // while the stream loads.
    final run = runs
            .where((r) => r.id == widget.run.id)
            .firstOrNull ??
        widget.run;
    final tasks = ref.watch(allTasksProvider).valueOrNull ?? [];
    final taskById = {for (final t in tasks) t.id: t};
    final done =
        run.stops.where((st) => st.status == StopStatus.completed).length;
    final failed =
        run.stops.where((st) => st.status == StopStatus.failed).length;
    if (_odoRunId != run.id) {
      _odoRunId = run.id;
      _odoStartCtrl.text = run.odometerStart?.toString() ?? '';
      _odoEndCtrl.text = run.odometerEnd?.toString() ?? '';
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.driverName ?? run.driverId),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: Text(s.editRun),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                    builder: (_) =>
                        RunBuilderScreen(existingRun: run)),
              );
            },
          ),
        ],
      ),
      body: ListView(
        padding: webContentPadding(MediaQuery.sizeOf(context).width),
        children: [
          WebCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RunProgressBar(completed: done, total: run.stops.length),
                const SizedBox(height: 8),
                Text(
                  '${s.stopsDone(done, run.stops.length)} · ${s.stopsFailed(failed)}',
                  style: TextStyle(color: tokens.textSecondary),
                ),
                const SizedBox(height: 12),
                Text(
                  s.driverMileage,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _odoStartCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: s.driverOdometerStart,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _odoEndCtrl,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: s.driverOdometerEnd,
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () => _saveMileage(run),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 52),
                      ),
                      child: Text(s.driverSaveMileage),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (run.stops.isEmpty)
            Text(s.noStops, style: TextStyle(color: tokens.textSecondary))
          else
            for (final stop in run.orderedStops) ...[
              _stopCard(context, ref, s, tokens, run, stop,
                  taskById[stop.taskId]?.materialsOnSite ?? false),
              const SizedBox(height: 10),
            ],
        ],
      ),
    );
  }

  Widget _stopCard(BuildContext context, WidgetRef ref, AppStrings s,
      AppColors tokens, DeliveryRun run, RunStop stop, bool materialsOnSite) {
    final (String label, Color color) = switch (stop.status) {
      StopStatus.completed => (s.done, tokens.statusDone),
      StopStatus.failed => (s.failedStop, tokens.danger),
      StopStatus.pending => (s.pending, tokens.statusTodo),
    };
    final photos = [
      if (stop.photoUrl != null) stop.photoUrl!,
      ...stop.photoUrls,
    ];
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(stop.title,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (stop.address.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(stop.address,
                          style: TextStyle(
                              fontSize: 13, color: tokens.textSecondary)),
                    ],
                    if (stop.notes.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(stop.notes,
                          style: TextStyle(
                              fontSize: 13, color: tokens.textSecondary)),
                    ],
                    if (stop.failReason != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        stopFailReasonLabel(s, stop.failReason) +
                            (stop.failNote != null &&
                                    stop.failNote!.isNotEmpty
                                ? ' — ${stop.failNote}'
                                : ''),
                        style:
                            TextStyle(fontSize: 13, color: tokens.danger),
                      ),
                    ],
                    if (stop.scheduledTime != null) ...[
                      const SizedBox(height: 2),
                      Text(stop.scheduledTime!,
                          style: TextStyle(
                              fontSize: 12, color: tokens.textTertiary)),
                    ],
                    if (stop.arrivedAt != null) ...[
                      const SizedBox(height: 2),
                      Text(
                          '${s.driverArrivedAt} ${DateFormat.Hm().format(stop.arrivedAt!)}',
                          style: TextStyle(
                              fontSize: 12, color: tokens.textSecondary)),
                    ],
                    if (stop.delayedMinutes != null) ...[
                      const SizedBox(height: 2),
                      Text(
                          '${s.driverDelayed} ${stop.delayedMinutes} min',
                          style: TextStyle(
                              fontSize: 12, color: tokens.accentText)),
                    ],
                    if (materialsOnSite) ...[
                      const SizedBox(height: 6),
                      WebPill(
                          label: s.materialsOnSite,
                          color: tokens.statusDone),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              WebPill(label: label, color: color),
            ],
          ),
          if (stop.items.isNotEmpty) ...[
            const SizedBox(height: 8),
            for (var i = 0; i < stop.items.length; i++)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(stop.items[i].label),
                value: stop.items[i].done,
                onChanged: stop.status == StopStatus.pending
                    ? (v) => _toggleItem(run, stop, i, v ?? false)
                    : null,
              ),
          ],
          if (photos.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 56,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: photos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () => showPhotoViewer(
                    context,
                    items: photos
                        .map((u) =>
                            PhotoViewerItem(url: u, label: stop.title))
                        .toList(),
                    initialIndex: index,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      photos[index],
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 56,
                        height: 56,
                        color: tokens.surfaceRaised,
                        child: Icon(Icons.broken_image_outlined,
                            color: tokens.textTertiary),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
          if (stop.status == StopStatus.pending) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _pickupGateOpen(stop)
                      ? null
                      : () => _completeStop(run, stop),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                  child: Text(stop.kind == StopKind.pickup
                      ? s.pickedUp
                      : s.delivered),
                ),
                if (stop.arrivedAt == null)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.location_on_outlined, size: 18),
                    label: Text(s.driverImHere),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    onPressed: () => _markArrived(run, stop),
                  ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                  onPressed: () => _markDelayed(run, stop, 15),
                  child: Text(s.driverDelay15),
                ),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 52),
                  ),
                  onPressed: () => _markDelayed(run, stop, 30),
                  child: Text(s.driverDelay30),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                  label: Text(s.addPhoto),
                  onPressed: () => _addProofPhoto(run, stop),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                      foregroundColor: tokens.danger),
                  onPressed: () => _failStop(run, stop),
                  child: Text(s.couldNotComplete),
                ),
              ],
            ),
            if (_pickupGateOpen(stop))
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(s.checkItemsHint,
                    style: TextStyle(
                        fontSize: 13, color: tokens.textSecondary)),
              ),
          ],
        ],
      ),
    );
  }
}
