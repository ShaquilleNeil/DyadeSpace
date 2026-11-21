import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_strings.dart';
import '../../models/app_user.dart';
import '../../models/delivery_run.dart';
import '../../models/material_request.dart';
import '../../models/site.dart';
import '../../providers/auth_provider.dart';
import '../../providers/locale_provider.dart';
import '../../providers/material_requests_provider.dart';
import '../../providers/runs_provider.dart';
import '../../providers/sites_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/photo_viewer.dart';

/// The managers' material-requests queue, reached from the
/// Board's shortcuts row. Two tabs: Requests (still awaiting
/// a decision) and History (everything decided — approved,
/// on the run, delivered, denied). Approving a request moves
/// it to History at once. Each request: approve or deny (a
/// deny needs a short reason), and once approved, one tap to
/// add it to today's run as a pickup stop — the add-to-run
/// button lives on the History tab. A request never becomes
/// a task and never joins a run on its own — the manager
/// attaches it, and completing that pickup stop marks it
/// delivered. Delete (with a confirm dialog) is offered where
/// the rules allow it: admins/managers any request, the
/// requester only their own still-requested one.
class MaterialRequestsScreen extends ConsumerStatefulWidget {
  const MaterialRequestsScreen({super.key});

  @override
  ConsumerState<MaterialRequestsScreen> createState() =>
      _MaterialRequestsScreenState();
}

class _MaterialRequestsScreenState
    extends ConsumerState<MaterialRequestsScreen> {
  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Today's run for the delivery driver (Drew). If the crew
  /// has no delivery-role user, any run today will do.
  DeliveryRun? _todayRun(List<DeliveryRun> runs, List<AppUser> users) {
    final now = DateTime.now();
    final today = runs.where((r) => _sameDay(r.date, now)).toList();
    if (today.isEmpty) return null;
    final driverIds = {
      for (final u in users)
        if (u.role == UserRole.delivery) u.id,
    };
    for (final r in today) {
      if (driverIds.contains(r.driverId)) return r;
    }
    return today.first;
  }

  Future<void> _addToTodayRun(MaterialRequest request) async {
    final s = ref.read(stringsProvider);
    final runs = ref.read(allRunsProvider).valueOrNull ?? [];
    final users = ref.read(allUsersProvider).valueOrNull ?? [];
    final siteById = ref.read(siteByIdProvider);
    final run = _todayRun(runs, users);
    if (run == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestNoRunToday)),
      );
      return;
    }
    try {
      await ref.read(materialRequestServiceProvider).attachToRun(
            request: request,
            run: run,
            siteName: siteById[request.siteId]?.name ?? '',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestAddedToRun)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestFailed('$e'))),
      );
    }
  }

  /// Approving asks first: the dialog's Confirm is the only
  /// path to the approve call. (Deny already asks for a reason;
  /// it is untouched.)
  Future<void> _approve(MaterialRequest request) async {
    final s = ref.read(stringsProvider);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.confirmApproveRequest),
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
    if (ok != true || !mounted) return;
    try {
      await ref.read(materialRequestServiceProvider).approve(request);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestApproved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestFailed('$e'))),
      );
    }
  }

  Future<void> _deny(MaterialRequest request) async {
    final s = ref.read(stringsProvider);
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => _DenyReasonDialog(strings: s),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    try {
      await ref
          .read(materialRequestServiceProvider)
          .deny(request, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestDenied)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestFailed('$e'))),
      );
    }
  }

  /// Deleting asks first: the dialog's Delete is the only
  /// path to the delete call. The button is only shown where
  /// the rules allow it (admins/managers any request, the
  /// requester only their own still-requested one); a denied
  /// delete surfaces as an error snackbar.
  Future<void> _delete(MaterialRequest request) async {
    final s = ref.read(stringsProvider);
    final tokens = AppTokens.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.materialRequestDeleteTitle),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s.cancel)),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: tokens.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s.materialRequestDelete)),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref
          .read(materialRequestServiceProvider)
          .deleteRequest(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestDeleted)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestFailed('$e'))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final requestsAsync = ref.watch(materialRequestsProvider);
    final siteById = ref.watch(siteByIdProvider);
    final runs = ref.watch(allRunsProvider).valueOrNull ?? [];
    final runById = {for (final r in runs) r.id: r};
    final me = ref.watch(currentUserProvider).valueOrNull;
    final isManager = me?.isAdminOrManager ?? false;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.materialRequests),
          bottom: TabBar(
            tabs: [
              Tab(text: s.materialRequestTabRequests),
              Tab(text: s.materialRequestTabHistory),
            ],
          ),
        ),
        body: requestsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error: $e')),
          data: (all) {
            final pending = all
                .where((r) => r.status == MaterialRequestStatus.requested)
                .toList();
            final history = all
                .where((r) => r.status != MaterialRequestStatus.requested)
                .toList();
            return TabBarView(
              children: [
                _requestList(
                    s, tokens, pending, siteById, runById, me, isManager),
                _requestList(
                    s, tokens, history, siteById, runById, me, isManager),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _requestList(
    AppStrings s,
    AppColors tokens,
    List<MaterialRequest> visible,
    Map<String, Site> siteById,
    Map<String, DeliveryRun> runById,
    AppUser? me,
    bool isManager,
  ) {
    if (visible.isEmpty) {
      return Center(child: Text(s.materialRequestNoRequests));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 28),
      itemCount: visible.length,
      itemBuilder: (ctx, i) {
        final r = visible[i];
        return _requestCard(
          context,
          s,
          tokens,
          r,
          siteById[r.siteId]?.name ?? '',
          runById[r.runId ?? ''],
          isManager,
          _canDelete(me, isManager, r),
        );
      },
    );
  }

  bool _canDelete(AppUser? me, bool isManager, MaterialRequest r) =>
      isManager ||
      (me != null &&
          me.id == r.requesterId &&
          r.status == MaterialRequestStatus.requested);

  String _statusLabel(AppStrings s, MaterialRequestStatus status) {
    switch (status) {
      case MaterialRequestStatus.requested:
        return s.materialRequestStatusRequested;
      case MaterialRequestStatus.approved:
        return s.materialRequestStatusApproved;
      case MaterialRequestStatus.onRun:
        return s.materialRequestStatusOnRun;
      case MaterialRequestStatus.delivered:
        return s.materialRequestStatusDelivered;
      case MaterialRequestStatus.denied:
        return s.materialRequestStatusDenied;
    }
  }

  Color _statusColor(AppColors tokens, MaterialRequestStatus status) {
    switch (status) {
      case MaterialRequestStatus.requested:
        return tokens.accent;
      case MaterialRequestStatus.approved:
        return tokens.accentText;
      case MaterialRequestStatus.onRun:
        return tokens.accentText;
      case MaterialRequestStatus.delivered:
        return tokens.statusDone;
      case MaterialRequestStatus.denied:
        return tokens.danger;
    }
  }

  Widget _requestCard(
    BuildContext context,
    AppStrings s,
    AppColors tokens,
    MaterialRequest request,
    String siteName,
    DeliveryRun? run,
    bool isManager,
    bool canDelete,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${request.quantity} × ${request.item}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor(tokens, request.status)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _statusLabel(s, request.status),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _statusColor(tokens, request.status),
                    ),
                  ),
                ),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: tokens.danger,
                    tooltip: s.materialRequestDelete,
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _delete(request),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (siteName.isNotEmpty) siteName,
                s.materialRequestedBy(request.requesterName),
                if (request.neededBy != null)
                  '${s.materialNeededBy} ${DateFormat('EEE MMM d').format(request.neededBy!)}',
                if (request.createdAt != null)
                  DateFormat('EEE MMM d').format(request.createdAt!),
              ].join(' · '),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            if (request.note.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(request.note,
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (request.status == MaterialRequestStatus.denied &&
                (request.denyReason ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '${s.materialRequestDenyReason}: ${request.denyReason}',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.danger),
              ),
            ],
            if (request.status == MaterialRequestStatus.onRun &&
                run != null) ...[
              const SizedBox(height: 4),
              Text(
                s.materialRequestOnRunFor(
                    DateFormat('EEE MMM d').format(run.date)),
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: tokens.accentText),
              ),
            ],
            if (request.photoUrl != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => showPhotoViewer(
                  context,
                  items: [
                    PhotoViewerItem(
                      url: request.photoUrl,
                      label: request.item,
                    ),
                  ],
                  initialIndex: 0,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(request.photoUrl!,
                      width: 56, height: 56, fit: BoxFit.cover),
                ),
              ),
            ],
            if (isManager &&
                request.status == MaterialRequestStatus.requested) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: tokens.danger,
                        side: BorderSide(color: tokens.danger, width: 1.5),
                        minimumSize: const Size(0, 44),
                      ),
                      onPressed: () => _deny(request),
                      child: Text(s.materialRequestDeny),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44)),
                      onPressed: () => _approve(request),
                      child: Text(s.materialRequestApprove),
                    ),
                  ),
                ],
              ),
            ],
            if (isManager &&
                request.status == MaterialRequestStatus.approved) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44)),
                  icon: const Icon(Icons.local_shipping_outlined, size: 19),
                  label: Text(s.materialRequestAddToRun),
                  onPressed: () => _addToTodayRun(request),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The "deny this request" dialog: asks for the short reason.
/// It owns its controller and disposes it in dispose — the
/// parent reads the returned reason string before the dialog
/// is gone, never after, so the old "used after being disposed"
/// crash cannot happen here.
class _DenyReasonDialog extends StatefulWidget {
  final AppStrings strings;
  const _DenyReasonDialog({required this.strings});

  @override
  State<_DenyReasonDialog> createState() => _DenyReasonDialogState();
}

class _DenyReasonDialogState extends State<_DenyReasonDialog> {
  final _reasonCtrl = TextEditingController();

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AlertDialog(
      title: Text(s.materialRequestDeny),
      content: TextField(
        controller: _reasonCtrl,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: s.materialRequestDenyReason,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => setState(() {}),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(s.cancel),
        ),
        FilledButton(
          onPressed: _reasonCtrl.text.trim().isEmpty
              ? null
              : () => Navigator.of(context).pop(_reasonCtrl.text.trim()),
          child: Text(s.materialRequestDeny),
        ),
      ],
    );
  }
}
