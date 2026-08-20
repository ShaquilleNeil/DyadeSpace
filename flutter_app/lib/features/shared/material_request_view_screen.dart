import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../models/material_request.dart';
import '../../providers/auth_providers.dart';
import '../../providers/material_requests_providers.dart';
import '../../providers/projects_providers.dart';
import '../../theme/app_spacing.dart';
import '../../theme/status_colors.dart';
import '../../utils/confirm.dart';
import '../../utils/friendly_error.dart';

class MaterialRequestViewScreen extends ConsumerWidget {
  const MaterialRequestViewScreen({super.key, required this.requestId});

  final String requestId;

  Future<void> _decide(BuildContext context, WidgetRef ref, String status) async {
    final me = ref.read(currentEmployeeProvider).value;
    if (me == null) return;
    try {
      await ref.read(materialRequestControllerProvider).decide(
            requestId,
            status: status,
            decidedById: me.id,
          );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e, fallback: 'Could not update request. Please try again.')),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestAsync = ref.watch(materialRequestByIdProvider(requestId));
    final me = ref.watch(currentEmployeeProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Material Request')),
      body: SafeArea(
        child: requestAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('Error: $e')),
          data: (request) {
            if (request == null) {
              return const Center(child: Text('Request not found'));
            }
            final project = ref.watch(projectByIdProvider(request.projectId)).value;
            final palette = materialRequestStatusPalette(context, request.status);
            final canDecide = me != null &&
                request.status == MaterialRequestStatus.pending &&
                (me.isAdmin || (me.isManager && me.projectIds.contains(request.projectId)));
            final canDelete = me != null &&
                request.status == MaterialRequestStatus.pending &&
                request.requestedById == me.id;

            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: palette.background,
                      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                    ),
                    child: Text(
                      MaterialRequestStatus.label(request.status),
                      style: Theme.of(context)
                          .textTheme
                          .labelMedium
                          ?.copyWith(color: palette.foreground, fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Requested by', style: Theme.of(context).textTheme.labelMedium),
                  Text(request.requestedByName, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  Text('Project', style: Theme.of(context).textTheme.labelMedium),
                  Text(project?.name ?? '—', style: Theme.of(context).textTheme.titleMedium),
                  if (request.createdAt != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text('Submitted', style: Theme.of(context).textTheme.labelMedium),
                    Text(
                      DateFormat('yyyy-MM-dd – kk:mm').format(request.createdAt!),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Text('Items', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: request.items.isEmpty
                            ? [const Text('No items listed')]
                            : request.items
                                .map((item) => Padding(
                                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                                      child: Text(
                                        '${item.quantity}${item.unit != null ? ' ${item.unit}' : ''} — ${item.name}',
                                      ),
                                    ))
                                .toList(),
                      ),
                    ),
                  ),
                  if (request.notes?.isNotEmpty ?? false) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text('Notes', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: SizedBox(width: double.infinity, child: Text(request.notes!)),
                      ),
                    ),
                  ],
                  if (request.photoUrls.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text('Photos', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: request.photoUrls.map((url) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(AppSpacing.controlRadius),
                          child: CachedNetworkImage(
                            imageUrl: url,
                            width: 110,
                            height: 110,
                            fit: BoxFit.cover,
                            placeholder: (context, url) => Container(
                              width: 110,
                              height: 110,
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                            ),
                            errorWidget: (context, url, error) => Container(
                              width: 110,
                              height: 110,
                              color: Theme.of(context).colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.broken_image),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                  if (request.managerNote?.isNotEmpty ?? false) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text('Manager Note', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: SizedBox(width: double.infinity, child: Text(request.managerNote!)),
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),
                  if (canDecide) ...[
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Theme.of(context).colorScheme.error,
                              side: BorderSide(color: Theme.of(context).colorScheme.error),
                            ),
                            onPressed: () => _decide(context, ref, MaterialRequestStatus.rejected),
                            child: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => _decide(context, ref, MaterialRequestStatus.approved),
                            child: const Text('Approve'),
                          ),
                        ),
                      ],
                    ),
                  ] else if (me != null &&
                      request.status == MaterialRequestStatus.approved &&
                      (me.isAdmin || (me.isManager && me.projectIds.contains(request.projectId))))
                    FilledButton(
                      onPressed: () => _decide(context, ref, MaterialRequestStatus.fulfilled),
                      child: const Text('Mark as Fulfilled'),
                    ),
                  if (canDelete) ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: BorderSide(color: Theme.of(context).colorScheme.error),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete Request'),
                      onPressed: () async {
                        final confirmed = await confirmDialog(
                          context,
                          title: 'Delete request?',
                          message: 'This permanently deletes this material request.',
                        );
                        if (confirmed) {
                          await ref.read(materialRequestControllerProvider).delete(requestId);
                          if (context.mounted) context.pop();
                        }
                      },
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
