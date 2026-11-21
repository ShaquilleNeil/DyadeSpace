import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_strings.dart';
import '../../models/delivery_run.dart';
import '../../models/material_request.dart';
import '../../models/run_stop.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/material_requests_provider.dart';
import '../../providers/photo_queue_provider.dart';
import '../../providers/sites_provider.dart';
import '../../providers/stages_provider.dart';
import '../../providers/tasks_provider.dart';
import '../../services/run_sync_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/run_progress_bar.dart';
import '../../widgets/status_indicator.dart';

/// Drew's runs (today's if there is one, otherwise the next one).
final _myRunsProvider = StreamProvider<List<DeliveryRun>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection('runs')
      .where('driverId', isEqualTo: user.id)
      .snapshots()
      .map((snap) {
    final runs = snap.docs.map(DeliveryRun.fromFirestore).toList();
    runs.sort((a, b) => a.date.compareTo(b.date));
    return runs;
  });
});

/// The driver's run-first home: greeting + today's run summary,
/// a big Next stop card with I'm here / delay actions, the stop
/// list, and odometer mileage. Runs show stops only - the
/// driver's tasks live in My Day, not on the run.
///
/// The run is reconciled (carry-over of unfinished stops) the
/// first time it is opened each day - see [RunSyncService].
/// Reordering here rewrites the same run document the manager
/// sees in the builder. Stops are closed with a photo (picked
/// up / delivered), so arrivals are confirmed the moment they
/// happen - no more "did Drew get the counter?". A stop that
/// cannot be done is closed as failed with a reason, which
/// pushes an alert to the managers (notifyStopFailed).
class RunScreen extends ConsumerStatefulWidget {
  const RunScreen({super.key});

  @override
  ConsumerState<RunScreen> createState() => _RunScreenState();
}

class _RunScreenState extends ConsumerState<RunScreen> {
  /// Run ids already reconciled this session (one sync per run
  /// per screen lifetime - the sync is idempotent, this only
  /// avoids repeating the Firestore read on every rebuild).
  final _synced = <String>{};

  /// Odometer fields, keyed by run id so switching runs resets.
  final _odoStartCtrl = TextEditingController();
  final _odoEndCtrl = TextEditingController();
  String? _odoRunId;

  @override
  void dispose() {
    _odoStartCtrl.dispose();
    _odoEndCtrl.dispose();
    super.dispose();
  }

  // ---------- Run sync ----------

  Future<void> _syncRun(DeliveryRun run) async {
    if (!mounted) return;
    final allTasks = ref.read(allTasksProvider).value;
    if (allTasks == null) return; // Not loaded yet - a later build retries.
    final stageIndex = ref.read(stageIndexProvider);
    try {
      final result = await RunSyncService.syncRun(
        run,
        allTasks: allTasks,
        stageIndex: stageIndex,
      );
      if (!mounted) return;
      if (result.carriedOver > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ref.read(stringsProvider).driverRunUpdated)),
        );
      }
      if (result.requestRepointFailures > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            // TODO(l10n): move to AppStrings.
            content: Text(
                'Run updated, but ${result.requestRepointFailures} material '
                'request(s) still point at the previous run.'),
          ),
        );
      }
    } catch (_) {
      // Sync is best-effort: the run still works without it, and
      // the next open retries.
    }
  }

  // ---------- Firestore writes ----------

  /// Runs are read and written whole (stops are embedded), so every
  /// stop change rewrites the stops array of the run doc.
  ///
  /// The write runs in a transaction: the fresh run doc is read
  /// inside it and the caller's stops are merged into that fresh
  /// list, so a manager edit landing at the same moment (a stop
  /// added, edited, or reordered in the builder) is not
  /// overwritten. The caller's version wins for the stops it
  /// knew about, in the caller's order (a reorder keeps its new
  /// order); stops the fresh doc has that the caller never saw
  /// are kept at the end; a stop the fresh doc no longer has was
  /// deleted meanwhile and is not resurrected. With no
  /// concurrent edit the merged list is exactly the caller's.
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

  Future<void> _saveOrderedStops(DeliveryRun run, List<RunStop> stops) async {
    final renumbered = [
      for (var i = 0; i < stops.length; i++)
        stops[i].copyWith(orderIndex: i),
    ];
    await _saveStops(run, renumbered);
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

  // ---------- Build ----------

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final runsAsync = ref.watch(_myRunsProvider);
    final allTasksAsync = ref.watch(allTasksProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    // Material requests, for the request line on request-linked
    // stops (item, quantity, requester, destination site).
    final requests = ref.watch(materialRequestsProvider).valueOrNull ?? [];
    final requestById = {for (final r in requests) r.id: r};
    final siteById = ref.watch(siteByIdProvider);
    MaterialRequest? requestFor(String? id) =>
        id == null ? null : requestById[id];
    String siteNameForRequest(String? id) {
      final request = requestFor(id);
      if (request == null) return '';
      return siteById[request.siteId]?.name ?? '';
    }
    return runsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (runs) {
        final now = DateTime.now();
        bool sameDay(DateTime d) =>
            d.year == now.year && d.month == now.month && d.day == now.day;
        DeliveryRun? found;
        for (final r in runs) {
          if (sameDay(r.date)) {
            found = r;
            break;
          }
        }
        final upcoming =
            runs.where((r) => r.date.isAfter(now) && !sameDay(r.date)).toList();

        if (found != null &&
            allTasksAsync.hasValue &&
            !_synced.contains(found.id)) {
          _synced.add(found.id);
          final runToSync = found;
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _syncRun(runToSync),
          );
        }

        if (found == null) {
          return _noRunView(s, tokens, upcoming);
        }

        final run = found;
        final stops = run.orderedStops;
        final pending =
            stops.where((st) => st.status == StopStatus.pending).toList();
        final next = pending.isEmpty ? null : pending.first;
        final carriedCount =
            stops.where((st) => st.carriedOver).length;

        // Odometer start prefills from the driver's previous run's
        // end reading when this run has none yet.
        if (_odoRunId != run.id) {
          _odoRunId = run.id;
          int? previousEnd;
          for (final r in runs) {
            if (!sameDay(r.date) &&
                r.date.isBefore(now) &&
                r.odometerEnd != null) {
              previousEnd = r.odometerEnd;
            }
          }
          _odoStartCtrl.text =
              run.odometerStart?.toString() ?? previousEnd?.toString() ?? '';
          _odoEndCtrl.text = run.odometerEnd?.toString() ?? '';
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
          children: [
            _greeting(s, tokens, me?.name),
            const SizedBox(height: 10),
            _summaryHeader(s, tokens, run, stops, pending),
            const SizedBox(height: 12),
            if (carriedCount > 0) ...[
              _carriedBanner(s, tokens, carriedCount),
              const SizedBox(height: 12),
            ],
            if (next != null) ...[
              _heroCard(
                  s,
                  tokens,
                  run,
                  next,
                  stops.indexOf(next) + 1,
                  requestFor(next.materialRequestId),
                  siteNameForRequest(next.materialRequestId)),
              const SizedBox(height: 14),
            ] else ...[
              _allDoneCard(s, tokens, run),
              const SizedBox(height: 14),
            ],
            for (final stop in stops)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: appCardDecoration(
                  context,
                  borderColor:
                      stop.id == next?.id ? AppTokens.accent : null,
                  borderWidth: stop.id == next?.id ? 1.5 : 1,
                ),
                padding: const EdgeInsets.all(13),
                child: _stopRow(
                    s,
                    tokens,
                    run,
                    stop,
                    stops,
                    requestFor(stop.materialRequestId),
                    siteNameForRequest(stop.materialRequestId)),
              ),
            const SizedBox(height: 10),
            _mileageCard(s, tokens, run),
          ],
        );
      },
    );
  }

  // ---------- Header ----------

  Widget _greeting(AppStrings s, AppColors tokens, String? name) {
    final hour = DateTime.now().hour;
    final hello = hour < 12
        ? s.driverHelloMorning
        : hour < 18
            ? s.driverHelloAfternoon
            : s.driverHelloEvening;
    final first = (name ?? '').trim().split(' ').first;
    return Text(
      first.isEmpty ? hello : '$hello, $first',
      style: TextStyle(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: tokens.textPrimary,
      ),
    );
  }

  Widget _summaryHeader(AppStrings s, AppColors tokens, DeliveryRun run,
      List<RunStop> stops, List<RunStop> pending) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              s.todaysRuns,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            Text(
              s.stopsDone(run.completedCount, stops.length),
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ],
        ),
        if (run.failedCount > 0)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              run.isFinished
                  ? s.runFinishedIssues
                  : s.stopsFailed(run.failedCount),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: tokens.danger,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: RunProgressBar(
            completed: run.completedCount,
            total: stops.length,
          ),
        ),
        if (pending.any((st) => st.address.trim().isNotEmpty))
          Padding(
            padding: const EdgeInsets.only(top: 9),
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTokens.accentMuted,
                foregroundColor: tokens.accentText,
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700),
              ),
              onPressed: () => _startRoute(pending),
              icon: const Icon(Icons.navigation_outlined, size: 17),
              label: Text(s.startRoute),
            ),
          ),
      ],
    );
  }

  Widget _carriedBanner(AppStrings s, AppColors tokens, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.accentMuted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.history, size: 18, color: tokens.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              s.driverCarriedBanner(count),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- Next stop hero ----------

  /// One line for a request-linked pickup: what Drew is
  /// fetching, how many, who asked, and for which site.
  Widget _requestLine(AppStrings s, AppColors tokens,
      MaterialRequest request, String siteName) {
    final where = siteName.isEmpty ? '' : ' · $siteName';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.inventory_2_outlined, size: 16, color: tokens.accentText),
        const SizedBox(width: 5),
        Expanded(
          child: Text(
            '${request.quantity} × ${request.item} — '
            '${s.materialRequestedBy(request.requesterName)}$where',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: tokens.accentText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _heroCard(AppStrings s, AppColors tokens, DeliveryRun run,
      RunStop stop, int number, MaterialRequest? request, String siteName) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.accent, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                s.driverNextStop(number),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: tokens.accent,
                ),
              ),
              const Spacer(),
              if (stop.scheduledTime != null &&
                  stop.scheduledTime!.isNotEmpty)
                Text(
                  '${s.beThereBy} ${stop.scheduledTime}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.textSecondary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            stop.title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: tokens.textPrimary,
            ),
          ),
          if (stop.address.isNotEmpty) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.place_outlined,
                    size: 16, color: tokens.textSecondary),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    stop.address,
                    style: TextStyle(
                        fontSize: 14, color: tokens.textSecondary),
                  ),
                ),
              ],
            ),
          ],
          if (request != null) ...[
            const SizedBox(height: 6),
            _requestLine(s, tokens, request, siteName),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(tokens,
                  stop.kind == StopKind.pickup ? s.driverPickup : s.driverDropOff),
              if (stop.items.isNotEmpty)
                _chip(tokens, s.driverItemsCount(stop.items.length)),
              if (stop.autoAdded) _chip(tokens, s.driverAutoAdded),
              if (stop.carriedOver) _chip(tokens, s.driverCarriedOver),
              if (stop.delayedMinutes != null)
                _chip(
                    tokens,
                    '${s.driverDelayed} ${stop.delayedMinutes} min',
                    warning: true),
              if (stop.arrivedAt != null)
                _chip(tokens,
                    '${s.driverArrivedAt} ${DateFormat.Hm().format(stop.arrivedAt!)}'),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: stop.address.isNotEmpty
                      ? () => _openDirections(stop.address)
                      : null,
                  icon: const Icon(Icons.directions_outlined, size: 20),
                  label: Text(s.driverDirections),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.accent,
                    foregroundColor: tokens.onAccent,
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: stop.arrivedAt == null
                      ? () => _markArrived(run, stop)
                      : null,
                  icon: const Icon(Icons.location_on_outlined, size: 20),
                  label: Text(
                    stop.arrivedAt == null
                        ? s.driverImHere
                        : '${s.driverArrivedAt} ${DateFormat.Hm().format(stop.arrivedAt!)}',
                    // Half-width button on a narrow phone: the
                    // arrival time makes this label long in
                    // French — ellipsize instead of overflowing.
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: tokens.statusDone,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(0, 48),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _markDelayed(run, stop, 15),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                  child: Text(s.driverDelay15),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _markDelayed(run, stop, 30),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 44),
                  ),
                  child: Text(s.driverDelay30),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _allDoneCard(AppStrings s, AppColors tokens, DeliveryRun run) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: tokens.statusDone, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.driverAllDone,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: tokens.textPrimary,
                  ),
                ),
                Text(
                  run.failedCount > 0
                      ? s.runFinishedIssues
                      : s.driverNoStopsLeft,
                  style: TextStyle(fontSize: 13, color: tokens.textSecondary),
                ),
                if (run.distanceKm != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    s.driverDistanceKm(run.distanceKm!),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tokens.statusDone,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(AppColors tokens, String label, {bool warning = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
      color: warning
          ? tokens.danger.withValues(alpha: 0.14)
          : tokens.accentMuted,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: warning ? tokens.danger : tokens.accent,
        ),
      ),
    );
  }

  // ---------- Mileage ----------

  Widget _mileageCard(AppStrings s, AppColors tokens, DeliveryRun run) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.speed_outlined,
                  size: 18, color: tokens.textSecondary),
              const SizedBox(width: 8),
              Text(
                s.driverMileage,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              const Spacer(),
              if (run.distanceKm != null)
                Text(
                  s.driverDistanceKm(run.distanceKm!),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: tokens.statusDone,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
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
              const SizedBox(width: 8),
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
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => _saveMileage(run),
              child: Text(s.driverSaveMileage),
            ),
          ),
        ],
      ),
    );
  }

  // ---------- No run today ----------

  Widget _noRunView(
      AppStrings s, AppColors tokens, List<DeliveryRun> upcoming) {
    final nextRun = upcoming.isEmpty ? null : upcoming.first;
    return ListView(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 28),
      children: [
        _greeting(s, tokens, ref.read(currentUserProvider).valueOrNull?.name),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: tokens.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                s.driverNoRunYet,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                s.driverRunComing,
                style: TextStyle(fontSize: 13, color: tokens.textSecondary),
              ),
              if (nextRun != null) ...[
                const SizedBox(height: 12),
                Text(
                  s.driverUpcomingRun,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: tokens.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat.yMMMd().format(nextRun.date)} · '
                  '${s.stopsCount(nextRun.stops.length)}',
                  style: TextStyle(fontSize: 14, color: tokens.textPrimary),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ---------- Stop rows ----------

  Widget _stopRow(AppStrings s, AppColors tokens, DeliveryRun run,
      RunStop stop, List<RunStop> stops,
      MaterialRequest? request, String siteName) {
    final isDone = stop.status == StopStatus.completed;
    final isFailed = stop.status == StopStatus.failed;
    final pending =
        stops.where((st) => st.status == StopStatus.pending).toList();
    final nextId = pending.isEmpty ? null : pending.first.id;
    final number = stops.indexOf(stop) + 1;
    final tags = <String>[
      if (stop.autoAdded) s.driverAutoAdded,
      if (stop.carriedOver) s.driverCarriedOver,
      if (stop.delayedMinutes != null)
        '${s.driverDelayed} ${stop.delayedMinutes} min',
      if (stop.arrivedAt != null)
        '${s.driverArrivedAt} ${DateFormat.Hm().format(stop.arrivedAt!)}',
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Circular number badge: filled accent for the next stop,
        // green check when completed, red X when failed, muted
        // outline otherwise.
        Container(
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: stop.status == StopStatus.completed
                ? tokens.statusDone
                : stop.status == StopStatus.failed
                    ? tokens.danger
                    : stop.id == nextId
                        ? AppTokens.accent
                        : null,
            border: stop.status == StopStatus.completed ||
                    stop.status == StopStatus.failed ||
                    stop.id == nextId
                ? null
                : Border.all(color: tokens.border),
          ),
          child: stop.status == StopStatus.completed
              ? const Icon(Icons.check, size: 14, color: Colors.white)
              : stop.status == StopStatus.failed
                  ? const Icon(Icons.close, size: 14, color: Colors.white)
                  : Text('${stop.orderIndex + 1}',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: stop.id == nextId
                              ? Colors.white
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant)),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Flexible(
                  child: Text(stop.title,
                      style: Theme.of(context).textTheme.titleMedium),
                ),
                if (stop.photoPending &&
                    stop.status == StopStatus.completed) ...[
                  const SizedBox(width: 6),
                  Icon(Icons.schedule,
                      size: 15,
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant),
                ],
              ]),
              if (tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    tags.join(' · '),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: tokens.accentText,
                    ),
                  ),
                ),
              if (stop.scheduledTime != null &&
                  stop.scheduledTime!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Row(children: [
                    Icon(Icons.schedule,
                        size: 14, color: tokens.accentText),
                    const SizedBox(width: 5),
                    Text('${s.beThereBy} ${stop.scheduledTime}',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: tokens.accentText)),
                  ]),
                ),
              if (stop.address.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(stop.address,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              // Request-linked pickup: the item, quantity,
              // requester and destination site, so Drew never
              // has to guess what he's fetching.
              if (request != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: _requestLine(s, tokens, request, siteName),
                ),
              if (stop.notes.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(stop.notes,
                      style: Theme.of(context).textTheme.bodyMedium),
                ),
              if (stop.items.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < stop.items.length; i++)
                        _itemRow(run, stop, i),
                    ],
                  ),
                ),
              if (stop.status == StopStatus.failed ||
                  (stop.carriedOver && stop.failReason != null))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.error_outline,
                          size: 15, color: tokens.danger),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          stopFailReasonLabel(s, stop.failReason) +
                              (stop.failNote != null &&
                                      stop.failNote!.isNotEmpty
                                  ? ' - ${stop.failNote}'
                                  : ''),
                          style: TextStyle(
                              fontSize: 12.5, color: tokens.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              if (stop.id == nextId)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Text(s.nextStop.toUpperCase(),
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.4,
                          color: tokens.accentText)),
                ),
              // Proof photos: the completion photo plus any extra
              // proof shots, with the hint that a photo is
              // appreciated but never a gate. Tapping any photo
              // opens the viewer on it, swipeable across the
              // stop's whole set.
              if (stop.photoUrls.isNotEmpty || stop.photoUrl != null) ...[
                const SizedBox(height: 8),
                SizedBox(
                  height: 56,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (var i = 0; i < _stopPhotos(stop).length; i++)
                        _proofThumb(
                          _stopPhotos(stop)[i],
                          () => showPhotoViewer(
                            context,
                            items: _stopPhotos(stop)
                                .map((u) => PhotoViewerItem(
                                      url: u,
                                      label: stop.address,
                                    ))
                                .toList(),
                            initialIndex: i,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  s.driverPhotoHint,
                  style: TextStyle(
                      fontSize: 12, color: tokens.textTertiary),
                ),
              ],
              if (stop.status == StopStatus.pending) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 9),
                  child: FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTokens.accentMuted,
                      foregroundColor: tokens.accentText,
                      minimumSize: const Size(0, 38),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      textStyle: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    onPressed: _pickupGateOpen(stop)
                        ? null
                        : () => _completeStop(run, stop),
                    child: Text(stop.kind == StopKind.pickup
                        ? s.pickedUp
                        : s.delivered),
                  ),
                ),
                if (_pickupGateOpen(stop))
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(s.checkItemsHint,
                        style: Theme.of(context).textTheme.bodySmall),
                  ),
                Wrap(
                  spacing: 4,
                  children: [
                    if (stop.address.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(Icons.directions_outlined,
                            size: 16),
                        label: Text(s.directions),
                        onPressed: () => _openDirections(stop.address),
                      ),
                    TextButton.icon(
                      icon: const Icon(Icons.add_a_photo_outlined,
                          size: 16),
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
              ],
            ],
          ),
        ),
        if (!isDone && !isFailed)
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 19),
                tooltip: s.moveUp,
                onPressed: number <= 1
                    ? null
                    : () => _moveStop(run, stop, -1),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 19),
                tooltip: s.moveDown,
                onPressed: number >= stops.length
                    ? null
                    : () => _moveStop(run, stop, 1),
              ),
            ],
          ),
        if (stop.photoUrl != null)
          GestureDetector(
            onTap: () => showPhotoViewer(
              context,
              items: _stopPhotos(stop)
                  .map((u) => PhotoViewerItem(url: u, label: stop.address))
                  .toList(),
              initialIndex: 0,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(stop.photoUrl!,
                  width: 52, height: 52, fit: BoxFit.cover),
            ),
          ),
      ],
    );
  }

  /// A stop's proof photos in display order: the completion
  /// photo first, then the extra proof shots.
  List<String> _stopPhotos(RunStop stop) => [
        if (stop.photoUrl != null) stop.photoUrl!,
        ...stop.photoUrls,
      ];

  Widget _proofThumb(String url, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child:
              Image.network(url, width: 56, height: 56, fit: BoxFit.cover),
        ),
      ),
    );
  }

  /// A pickup with a checklist stays gated until every item is
  /// ticked - the driver confirms the load piece by piece.
  bool _pickupGateOpen(RunStop stop) =>
      stop.kind == StopKind.pickup &&
      stop.items.isNotEmpty &&
      stop.items.any((i) => !i.done);

  Widget _itemRow(DeliveryRun run, RunStop stop, int index) {
    final item = stop.items[index];
    final interactive =
        stop.status == StopStatus.pending && stop.kind == StopKind.pickup;
    if (interactive) {
      return Row(children: [
        Checkbox(
          value: item.done,
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          onChanged: (v) => _toggleItem(run, stop, index, v ?? false),
        ),
        Expanded(
          child: Text(item.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface)),
        ),
      ]);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(
          item.done ? Icons.check_circle_outline : Icons.circle_outlined,
          size: 15,
          color: item.done
              ? AppTokens.of(context).statusDone
              : Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(item.label,
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      ]),
    );
  }

  // ---------- Stop actions ----------

  Future<void> _moveStop(DeliveryRun run, RunStop stop, int delta) async {
    final stops = List<RunStop>.from(run.orderedStops);
    final i = stops.indexWhere((s) => s.id == stop.id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= stops.length) return;
    final moved = stops.removeAt(i);
    stops.insert(j, moved);
    await _saveOrderedStops(run, stops);
  }

  Future<void> _markArrived(DeliveryRun run, RunStop stop) async {
    final updated = stop.copyWith(arrivedAt: DateTime.now());
    await _saveStop(run, updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ref.read(stringsProvider).driverArrivedMarked)),
    );
  }

  Future<void> _markDelayed(DeliveryRun run, RunStop stop, int minutes) async {
    final updated = stop.copyWith(
      delayedMinutes: minutes,
      delayedAt: DateTime.now(),
    );
    await _saveStop(run, updated);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(ref.read(stringsProvider).driverDelayedBy(minutes))),
    );
  }

  /// Extra proof photo on a stop (on top of the completion
  /// photo). Uploaded straight away; when the upload fails the
  /// photo goes into the offline queue (runExtra) and is
  /// attached to the stop when connection returns.
  Future<void> _addProofPhoto(DeliveryRun run, RunStop stop) async {
    final photos = ref.read(photoServiceProvider);
    final picked = await photos.takePhoto();
    if (picked == null) return; // Camera cancelled.
    String? url;
    try {
      url = await photos.uploadFile(picked.path, 'runPhotos', run.id);
    } catch (_) {
      // No signal: the photo goes into the offline queue and is
      // attached when connection returns — unless parking the
      // photo fails, in which case the photo is gone and the
      // driver must be told instead of shown "queued".
      final queued =
          await ref.read(photoQueueServiceProvider).enqueue(
                kind: 'runExtra',
                sourcePath: picked.path,
                folder: 'runPhotos',
                runId: run.id,
                stopId: stop.id,
              );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(queued
                  ? ref.read(stringsProvider).photoQueuedOffline
                  : ref.read(stringsProvider).photoUploadFailed)),
        );
      }
      return;
    }
    await _saveStop(run, stop.copyWith(photoUrls: [...stop.photoUrls, url]));
  }

  Future<void> _completeStop(DeliveryRun run, RunStop stop) async {
    final photos = ref.read(photoServiceProvider);
    final picked = await photos.takePhoto();
    if (picked == null) return; // camera cancelled - stop stays open
    String? url;
    var photoPending = false;
    try {
      url = await photos.uploadFile(picked.path, 'runPhotos', run.id);
    } catch (_) {
      // No signal: the photo goes into the offline queue and the
      // stop still closes now, flagged photoPending. The queue
      // attaches the photo when connection returns — unless
      // parking the photo fails (false): then the photo is gone
      // and the stop must NOT close, or the proof is lost with
      // nothing to retry from. The driver retakes the photo.
      photoPending = true;
      final queued =
          await ref.read(photoQueueServiceProvider).enqueue(
                kind: 'runStop',
                sourcePath: picked.path,
                folder: 'runPhotos',
                runId: run.id,
                stopId: stop.id,
              );
      if (!queued) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    ref.read(stringsProvider).photoUploadFailed)),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(ref.read(stringsProvider).photoQueuedOffline)),
        );
      }
    }
    final updated = run.stops
        .map((s) => s.id == stop.id
            ? s.copyWith(
                status: StopStatus.completed,
                photoUrl: url,
                photoPending: photoPending,
                completedAt: DateTime.now(),
              )
            : s)
        .toList();
    await _saveStops(run, updated);
    // A completed drop-off linked to a task means that task's
    // materials are now on site. The task itself is NOT
    // completed here - tasks live in My Day, separate from runs.
    // The task may have been deleted after the stop was planned:
    // the stop is already completed above, so a NOT_FOUND here
    // must not throw the completion away — the run sync prunes
    // the orphaned planned stop on the next open.
    final taskId = stop.taskId;
    if (stop.kind == StopKind.dropoff && taskId != null) {
      try {
        await ref.read(taskServiceProvider).markMaterialsOnSite(taskId);
      } catch (_) {}
    }
  }

  Future<void> _toggleItem(
      DeliveryRun run, RunStop stop, int index, bool value) async {
    final items = [
      for (var i = 0; i < stop.items.length; i++)
        i == index ? stop.items[i].copyWith(done: value) : stop.items[i],
    ];
    final updated = run.stops
        .map((s) => s.id == stop.id ? s.copyWith(items: items) : s)
        .toList();
    await _saveStops(run, updated);
  }

  /// "Why couldn't this stop be completed?" The sheet owns its
  /// note controller; this just applies the returned result.
  /// The save happens after the sheet closes (and inside the
  /// transactional _saveStops), never across the sheet's pop.
  Future<void> _failStop(DeliveryRun run, RunStop stop) async {
    final result = await showModalBottomSheet<_FailStopResult>(
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => _FailStopSheet(run: run, stop: stop),
    );
    if (result == null || !mounted) return;
    final updated = run.stops
        .map((x) => x.id == stop.id
            ? x.copyWith(
                status: StopStatus.failed,
                failReason: result.reasonKey,
                failNote: result.note.isEmpty ? null : result.note,
                photoUrl: result.photoUrl,
                completedAt: DateTime.now(),
              )
            : x)
        .toList();
    await _saveStops(run, updated);
    // Evidence photo whose upload failed: the stop is already
    // failed above; the photo follows through the offline queue
    // (runFail) and attaches when connection returns — unless
    // parking the photo fails, in which case the photo is gone
    // and the driver must be told instead of shown "queued".
    if (result.photoUrl == null && result.photoPath != null) {
      final queued =
          await ref.read(photoQueueServiceProvider).enqueue(
                kind: 'runFail',
                sourcePath: result.photoPath!,
                folder: 'runPhotos',
                runId: run.id,
                stopId: stop.id,
              );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(queued
                  ? ref.read(stringsProvider).photoQueuedOffline
                  : ref.read(stringsProvider).photoUploadFailed)),
        );
      }
    }
  }

  Future<void> _openDirections(String address) async {
    final uri = Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(address)}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _startRoute(List<RunStop> pendingStops) async {
    final addresses = pendingStops
        .map((st) => st.address.trim())
        .where((a) => a.isNotEmpty)
        .toList();
    if (addresses.isEmpty) return;
    final destination = Uri.encodeComponent(addresses.last);
    final waypoints = addresses
        .sublist(0, addresses.length - 1)
        .map(Uri.encodeComponent)
        .join('|');
    final url = 'https://www.google.com/maps/dir/?api=1'
        '&destination=$destination'
        '${waypoints.isEmpty ? '' : '&waypoints=$waypoints'}';
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }
}

/// What the fail-stop sheet returns: the picked reason, the
/// note, and the optional evidence photo — read while the sheet
/// is still mounted.
class _FailStopResult {
  final String reasonKey;
  final String note;
  final String? photoUrl;
  // Set when the photo was picked but its upload failed: the
  // parent queues it (runFail) instead of dropping it.
  final String? photoPath;

  const _FailStopResult({
    required this.reasonKey,
    required this.note,
    this.photoUrl,
    this.photoPath,
  });
}

/// "Why couldn't this stop be completed?" sheet. It owns its
/// note controller and disposes it in dispose — the parent
/// reads the result before the sheet is gone, never after, so
/// the old "used after being disposed" crash cannot happen
/// here. The save itself happens in the parent, after the
/// sheet closes.
class _FailStopSheet extends ConsumerStatefulWidget {
  final DeliveryRun run;
  final RunStop stop;

  const _FailStopSheet({required this.run, required this.stop});

  @override
  ConsumerState<_FailStopSheet> createState() => _FailStopSheetState();
}

class _FailStopSheetState extends ConsumerState<_FailStopSheet> {
  final _noteCtrl = TextEditingController();
  String? _reasonKey;
  String? _photoUrl;
  // Local path of a picked photo whose upload failed; the
  // parent queues it (runFail) after the sheet closes.
  String? _photoPath;

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  /// Optional evidence photo for a FAILED stop: picked here,
  /// uploaded right away; when the upload fails the local path
  /// is kept and the parent queues it (runFail) instead of
  /// dropping the photo.
  Future<void> _addPhoto() async {
    final picked =
        await ref.read(photoServiceProvider).takePhoto();
    if (picked == null) return; // camera cancelled
    try {
      final url = await ref
          .read(photoServiceProvider)
          .uploadFile(picked.path, 'runPhotos', widget.run.id);
      if (mounted) {
        setState(() {
          _photoUrl = url;
          _photoPath = null;
        });
      }
    } catch (_) {
      // Upload failed (offline): keep the path for the queue.
      if (mounted) setState(() => _photoPath = picked.path);
    }
  }

  void _confirm() {
    // Dismiss the keyboard before popping: popping while it is
    // still animating down races the inset notification against
    // the sheet's unmount (the same race that red-screened the
    // material request form on Send).
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(_FailStopResult(
      reasonKey: _reasonKey!,
      note: _noteCtrl.text.trim(),
      photoUrl: _photoUrl,
      photoPath: _photoPath,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final stop = widget.stop;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
        // Scrollable so the keyboard can never overflow the
        // sheet on a small phone (same fix as the material
        // request form).
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.whyNotComplete,
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in stopFailReasonKeys)
                    ChoiceChip(
                      label: Text(stopFailReasonLabel(s, key)),
                      selected: _reasonKey == key,
                      onSelected: (_) => setState(() => _reasonKey = key),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _noteCtrl,
                decoration: InputDecoration(
                    labelText: s.notes,
                    border: const OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    icon: const Icon(Icons.photo_camera_outlined, size: 18),
                    label: Text(s.addPhoto),
                    onPressed: _addPhoto,
                  ),
                  if (_photoUrl != null) ...[
                    const SizedBox(width: 10),
                    GestureDetector(
                      onTap: () => showPhotoViewer(
                        context,
                        items: [
                          PhotoViewerItem(
                            url: _photoUrl,
                            label: stop.address,
                          ),
                        ],
                        initialIndex: 0,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(_photoUrl!,
                            width: 44, height: 44, fit: BoxFit.cover),
                      ),
                    ),
                  ],
                  if (_photoUrl == null && _photoPath != null) ...[
                    const SizedBox(width: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(_photoPath!),
                          width: 44, height: 44, fit: BoxFit.cover),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(s.cancel),
                  ),
                  const Spacer(),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44)),
                    onPressed: _reasonKey == null ? null : _confirm,
                    child: Text(s.confirm),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
