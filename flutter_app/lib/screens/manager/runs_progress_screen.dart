import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../l10n/app_strings.dart';
import '../../models/delivery_run.dart';
import '../../models/run_stop.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/runs_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/photo_viewer.dart';
import '../../widgets/run_progress_bar.dart';
import '../../widgets/status_indicator.dart';
import 'run_builder_screen.dart';

/// Manager view of the day's delivery runs, LIVE: pick a day,
/// see each driver's progress and every stop as it closes. Read
/// only - the builder stays the editor (the pencil on a card
/// opens it in edit mode). Pass [readOnly] to hide the pencil
/// entirely (the Board's runs-at-a-glance card uses this).
class RunsProgressScreen extends ConsumerStatefulWidget {
  final bool readOnly;
  const RunsProgressScreen({super.key, this.readOnly = false});

  @override
  ConsumerState<RunsProgressScreen> createState() =>
      _RunsProgressScreenState();
}

class _RunsProgressScreenState extends ConsumerState<RunsProgressScreen> {
  DateTime _date = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    final runsAsync = ref.watch(allRunsProvider);
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final userName = {for (final u in users) u.id: u.name};
    return Scaffold(
      appBar: AppBar(title: Text(s.runProgress)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 2),
            child: Row(children: [
              Text('${s.date}: ',
                  style: Theme.of(context).textTheme.titleSmall),
              Text(DateFormat('EEE MMM d, yyyy').format(_date),
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.calendar_month_outlined),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _date,
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
              ),
            ]),
          ),
          Expanded(
            child: runsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (runs) {
                final day =
                    runs.where((r) => isSameDay(r.date, _date)).toList();
                if (day.isEmpty) {
                  return Center(child: Text(s.noRunsForDay));
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
                  children: [
                    for (final run in day)
                      RunProgressCard(
                        run: run,
                        s: s,
                        driverName: userName[run.driverId] ?? s.driver,
                        onEdit: widget.readOnly
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        RunBuilderScreen(existingRun: run),
                                  ),
                                ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One run as a progress card: driver, progress line, then the
/// stops in order. Full form (this screen): address, be-there-by
/// time, fail reason, closing time, photo. Compact form (By
/// Person): badge, title, status only. [onEdit] shows a pencil;
/// [onTap] makes the whole card tappable (the two are alternatives
/// for opening the builder in edit mode - callers pass one).
class RunProgressCard extends StatelessWidget {
  final DeliveryRun run;
  final AppStrings s;
  final String? driverName;
  final bool compact;
  final VoidCallback? onEdit;
  final VoidCallback? onTap;

  const RunProgressCard({
    super.key,
    required this.run,
    required this.s,
    this.driverName,
    this.compact = false,
    this.onEdit,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final stops = run.orderedStops;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: appCardDecoration(context),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(13),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (driverName != null || onEdit != null)
                  Row(children: [
                    if (driverName != null)
                      Expanded(
                        child: Text(driverName!,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium),
                      ),
                    if (onEdit != null)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 19),
                        tooltip: s.editRun,
                        visualDensity: VisualDensity.compact,
                        onPressed: onEdit,
                      ),
                  ]),
                Text(s.stopsDone(run.completedCount, stops.length),
                    style: Theme.of(context).textTheme.titleSmall),
                if (run.isComplete)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Row(children: [
                      Icon(Icons.check_circle,
                          size: 14,
                          color: tokens.statusDone),
                      const SizedBox(width: 5),
                      Text(s.done,
                          style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: tokens.statusDone)),
                    ]),
                  )
                else if (run.failedCount > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      run.isFinished
                          ? s.runFinishedIssues
                          : s.stopsFailed(run.failedCount),
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: tokens.danger),
                    ),
                  ),
                // Monday-style progress bar: blue while the run is
                // going, green once every stop is done.
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: RunProgressBar(
                      completed: run.completedCount, total: stops.length),
                ),
                const SizedBox(height: 8),
                for (final stop in stops)
                  _stopRow(context, stop),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _stopRow(BuildContext context, RunStop stop) {
    final tokens = AppTokens.of(context);
    final closedAt = stop.completedAt == null
        ? null
        : DateFormat('HH:mm').format(stop.completedAt!);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StopBadge(stop: stop),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(stop.title,
                        style:
                            Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface,
                                )),
                  ),
                  if (compact && stop.status == StopStatus.failed)
                    Text(s.failedStop,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: tokens.danger)),
                  if (compact &&
                      stop.status == StopStatus.completed &&
                      closedAt != null)
                    Text(closedAt,
                        style: Theme.of(context).textTheme.bodySmall),
                  if (!compact && closedAt != null) ...[
                    const SizedBox(width: 8),
                    Text(closedAt,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ]),
                if (!compact) ...[
                  if (stop.scheduledTime != null &&
                      stop.scheduledTime!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(children: [
                        Icon(Icons.schedule,
                            size: 13, color: tokens.accentText),
                        const SizedBox(width: 5),
                        Text('${s.beThereBy} ${stop.scheduledTime}',
                            style: TextStyle(
                                fontSize: 12.5,
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
                  if (stop.autoAdded ||
                      stop.carriedOver ||
                      stop.delayedMinutes != null ||
                      stop.arrivedAt != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        [
                          if (stop.autoAdded) s.driverAutoAdded,
                          if (stop.carriedOver) s.driverCarriedOver,
                          if (stop.delayedMinutes != null)
                            '${s.driverDelayed} ${stop.delayedMinutes} min',
                          if (stop.arrivedAt != null)
                            '${s.driverArrivedAt} ${DateFormat('HH:mm').format(stop.arrivedAt!)}',
                        ].join(' · '),
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: tokens.accentText),
                      ),
                    ),
                  if (stop.status == StopStatus.failed)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline,
                              size: 14,
                              color: tokens.danger),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              stopFailReasonLabel(s, stop.failReason) +
                                  (stop.failNote != null &&
                                          stop.failNote!.isNotEmpty
                                      ? ' - ${stop.failNote}'
                                      : ''),
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: tokens.danger),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          if (!compact && stop.photoUrl != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => showPhotoViewer(
                context,
                items: [
                  if (stop.photoUrl != null)
                    PhotoViewerItem(
                        url: stop.photoUrl, label: stop.address),
                  for (final u in stop.photoUrls)
                    PhotoViewerItem(url: u, label: stop.address),
                ],
                initialIndex: 0,
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(stop.photoUrl!,
                    width: 52, height: 52, fit: BoxFit.cover),
              ),
            ),
          ],
          // Extra proof photos the driver attached at the stop.
          if (!compact && stop.photoUrls.isNotEmpty)
            for (var i = 0; i < stop.photoUrls.length; i++)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: GestureDetector(
                  onTap: () => showPhotoViewer(
                    context,
                    items: [
                      if (stop.photoUrl != null)
                        PhotoViewerItem(
                            url: stop.photoUrl, label: stop.address),
                      for (final u in stop.photoUrls)
                        PhotoViewerItem(url: u, label: stop.address),
                    ],
                    initialIndex:
                        stop.photoUrl == null ? i : i + 1,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(stop.photoUrls[i],
                        width: 52, height: 52, fit: BoxFit.cover),
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// The numbered stop badge, same language as the driver screen:
/// green check when completed, red X when failed, plain number
/// while pending.
class _StopBadge extends StatelessWidget {
  final RunStop stop;
  const _StopBadge({required this.stop});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final done = stop.status == StopStatus.completed;
    final failed = stop.status == StopStatus.failed;
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Monday fills: the bright status colour, not the dark
        // text shade — green done, red failed.
        color: done
            ? tokens.statusDone
            : failed
                ? tokens.danger
                : null,
        border: done || failed
            ? null
            : Border.all(color: tokens.border),
      ),
      child: done
          ? const Icon(Icons.check, size: 13, color: Colors.white)
          : failed
              ? const Icon(Icons.close, size: 13, color: Colors.white)
              : Text('${stop.orderIndex + 1}',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant)),
    );
  }
}
