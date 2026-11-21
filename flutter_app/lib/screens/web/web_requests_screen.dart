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
import '../../widgets/material_request_form.dart';
import '../../widgets/photo_viewer.dart';
import 'web_shared.dart';

enum _ReqTab { requests, history }

/// Requests: the materials queue. Same service calls as the
/// phone queue (approve / deny with a reason / add to today's
/// run / delete with confirm), same two tabs: Requests
/// (still awaiting a decision) and History (everything
/// decided — approved, on the run, delivered, denied). The
/// photo opens the shared viewer. The web shell is
/// admin/manager-only, so delete is offered on every card.
/// New requests are created here too, with the same fields as
/// the phone sheet (item, quantity, needed-by, note, photo) —
/// pick a site first, then the shared request sheet opens.
class WebRequestsScreen extends ConsumerStatefulWidget {
  const WebRequestsScreen({super.key});

  @override
  ConsumerState<WebRequestsScreen> createState() => _WebRequestsScreenState();
}

class _WebRequestsScreenState extends ConsumerState<WebRequestsScreen> {
  _ReqTab _tab = _ReqTab.requests;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final requests = ref.watch(materialRequestsProvider).valueOrNull ?? [];
    final sitesById = ref.watch(siteByIdProvider);
    // Watched (not just read in _newRequest) so the stream is
    // warm when the picker opens — a StreamProvider read with
    // ref.read sees null until something has listened to it.
    final sites = ref.watch(sitesProvider).valueOrNull ?? [];
    final runs = ref.watch(allRunsProvider).valueOrNull ?? [];
    final runById = {for (final r in runs) r.id: r};

    List<MaterialRequest> filtered;
    switch (_tab) {
      case _ReqTab.requests:
        filtered = requests
            .where((r) => r.status == MaterialRequestStatus.requested)
            .toList();
      case _ReqTab.history:
        filtered = requests
            .where((r) => r.status != MaterialRequestStatus.requested)
            .toList();
    }

    return ListView(
      padding: webContentPadding(MediaQuery.sizeOf(context).width),
      children: [
        WebSectionHeader(
          title: s.materialRequests,
          trailing: FilledButton.icon(
            onPressed: () => _newRequest(ref, sites),
            icon: const Icon(Icons.add, size: 18),
            label: Text(s.requestMaterials),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip(tokens, s.materialRequestTabRequests, _ReqTab.requests),
            _chip(tokens, s.materialRequestTabHistory, _ReqTab.history),
          ],
        ),
        const SizedBox(height: 16),
        if (filtered.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 24),
            child: Text(s.materialRequestNoRequests,
                style: TextStyle(color: tokens.textSecondary)),
          )
        else
          for (final r in filtered) ...[
            _requestCard(
                context, s, tokens, r, sitesById[r.siteId]?.name,
                runById[r.runId]?.date),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  Widget _chip(AppColors tokens, String label, _ReqTab tab) {
    return ChoiceChip(
      label: Text(label),
      selected: _tab == tab,
      onSelected: (_) => setState(() => _tab = tab),
      selectedColor: tokens.accentMuted,
      backgroundColor: tokens.surface,
      side: BorderSide(color: tokens.border),
      labelStyle: TextStyle(
        color:
            _tab == tab ? tokens.accentText : tokens.textPrimary,
        fontWeight:
            _tab == tab ? FontWeight.w600 : FontWeight.normal,
      ),
    );
  }

  Widget _requestCard(BuildContext context, AppStrings s, AppColors tokens,
      MaterialRequest r, String? siteName, DateTime? runDate) {
    final (String label, Color color) = switch (r.status) {
      MaterialRequestStatus.requested =>
        (s.materialRequestStatusRequested, tokens.statusTodo),
      MaterialRequestStatus.approved =>
        (s.materialRequestStatusApproved, tokens.statusInProgress),
      MaterialRequestStatus.onRun =>
        (s.materialRequestStatusOnRun, tokens.accent),
      MaterialRequestStatus.delivered =>
        (s.materialRequestStatusDelivered, tokens.statusDone),
      MaterialRequestStatus.denied =>
        (s.materialRequestStatusDenied, tokens.danger),
    };
    return WebCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (r.photoUrl != null) ...[
            InkWell(
              onTap: () => showPhotoViewer(context,
                  items: [PhotoViewerItem(url: r.photoUrl)],
                  initialIndex: 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  r.photoUrl!,
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${r.quantity} × ${r.item}',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                    ),
                    WebPill(label: label, color: color),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      color: tokens.danger,
                      tooltip: s.materialRequestDelete,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _delete(r),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '${s.materialRequestedBy(r.requesterName)} · ${siteName ?? ''}',
                  style: TextStyle(
                      fontSize: 13, color: tokens.textSecondary),
                ),
                if (r.neededBy != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '${s.materialNeededBy} ${DateFormat('MMM d').format(r.neededBy!)}',
                    style: TextStyle(
                        fontSize: 13, color: tokens.textSecondary),
                  ),
                ],
                if (r.note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(r.note, style: const TextStyle(fontSize: 13)),
                ],
                if (r.status == MaterialRequestStatus.denied &&
                    r.denyReason != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    r.denyReason!,
                    style: TextStyle(fontSize: 13, color: tokens.danger),
                  ),
                ],
                if (r.status == MaterialRequestStatus.onRun &&
                    runDate != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    s.materialRequestOnRunFor(
                        DateFormat('EEE MMM d').format(runDate)),
                    style: TextStyle(
                        fontSize: 13, color: tokens.textSecondary),
                  ),
                ],
                if (r.status == MaterialRequestStatus.requested) ...[
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: () => _approve(r),
                        // The theme gives every FilledButton an infinite minimum
                        // width — bound it to its content (same fix as the
                        // topbar button).
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                        child: Text(s.materialRequestApprove),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => _denyDialog(r),
                        // The theme gives every OutlinedButton an infinite minimum
                        // width — bound it to its content (same fix as the
                        // topbar button).
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 52),
                        ),
                        child: Text(s.materialRequestDeny),
                      ),
                    ],
                  ),
                ],
                if (r.status == MaterialRequestStatus.approved) ...[
                  const SizedBox(height: 10),
                  OutlinedButton(
                    onPressed: () => _addToTodayRun(r),
                    child: Text(s.materialRequestAddToRun),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// New request on web: pick a site first, then the same
  /// request sheet the phone uses (item, quantity, needed-by,
  /// note, optional photo). The sheet returns true when the
  /// request was sent; the confirmation is the caller's job.
  Future<void> _newRequest(WidgetRef ref, List<Site> sites) async {
    final s = ref.read(stringsProvider);
    if (sites.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.noSites)),
      );
      return;
    }
    Site? picked = sites.first;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(s.pickSite),
          content: DropdownButtonFormField<Site>(
            initialValue: picked,
            isExpanded: true,
            items: [
              for (final site in sites)
                DropdownMenuItem(
                    value: site,
                    child: Text(site.name,
                        overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => picked = v),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(s.cancel)),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 52),
                ),
                child: Text(s.confirm)),
          ],
        ),
      ),
    );
    final site = picked;
    if (ok != true || site == null || !mounted) return;
    final sent = await showMaterialRequestSheet(
      context,
      ref,
      siteId: site.id,
    );
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestSent)),
      );
    }
  }

  Future<void> _approve(MaterialRequest r) async {
    final s = ref.read(stringsProvider);
    try {
      await ref.read(materialRequestServiceProvider).approve(r);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestApproved)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestFailed(e.toString()))),
      );
    }
  }

  Future<void> _denyDialog(MaterialRequest r) async {
    final s = ref.read(stringsProvider);
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.materialRequestDeny),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: s.materialRequestDenyReason,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            // The theme gives every FilledButton an infinite minimum
            // width — bound it to its content (same fix as the
            // topbar button).
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
            ),
            child: Text(s.materialRequestDeny),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    try {
      await ref.read(materialRequestServiceProvider).deny(r, reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestDenied)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestFailed(e.toString()))),
      );
    }
  }

  /// Deleting asks first: the dialog's Delete is the only
  /// path to the delete call. The web shell is
  /// admin/manager-only, so the button is offered on every
  /// card; the rules still enforce it server-side.
  Future<void> _delete(MaterialRequest r) async {
    final s = ref.read(stringsProvider);
    final tokens = AppTokens.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(s.materialRequestDeleteTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: tokens.danger,
              minimumSize: const Size(0, 52),
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(s.materialRequestDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(materialRequestServiceProvider).deleteRequest(r.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestDeleted)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestFailed(e.toString()))),
      );
    }
  }

  Future<void> _addToTodayRun(MaterialRequest r) async {
    final s = ref.read(stringsProvider);
    final runs = ref.read(allRunsProvider).valueOrNull ?? [];
    final users = ref.read(allUsersProvider).valueOrNull ?? [];
    final run = _todayRun(runs, users);
    if (run == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestNoRunToday)),
      );
      return;
    }
    final sitesById = ref.read(siteByIdProvider);
    try {
      await ref.read(materialRequestServiceProvider).attachToRun(
            request: r,
            run: run,
            siteName: sitesById[r.siteId]?.name ?? '',
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestAddedToRun)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.materialRequestFailed(e.toString()))),
      );
    }
  }

  /// Today's run, preferring a delivery driver's run — the same
  /// rule as the phone queue.
  DeliveryRun? _todayRun(List<DeliveryRun> runs, List<AppUser> users) {
    final now = DateTime.now();
    final today = runs.where((r) => isSameDay(r.date, now)).toList();
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
}
