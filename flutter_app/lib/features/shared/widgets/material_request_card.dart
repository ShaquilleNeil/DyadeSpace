import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/material_request.dart';
import '../../../theme/app_spacing.dart';
import '../../../theme/status_colors.dart';

/// Compact card for a material request — requester, item count, status chip.
/// Tapping pushes the request's detail route.
class MaterialRequestCard extends StatelessWidget {
  const MaterialRequestCard({super.key, required this.request, this.projectName});

  final MaterialRequest request;
  final String? projectName;

  @override
  Widget build(BuildContext context) {
    final palette = materialRequestStatusPalette(context, request.status);
    final itemSummary = request.items.isEmpty
        ? 'No items'
        : request.items.map((i) => '${i.quantity}${i.unit != null ? ' ${i.unit}' : ''} ${i.name}').join(', ');

    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: InkWell(
        onTap: () => context.push('/material-requests/${request.id}'),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      request.requestedByName,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                    decoration: BoxDecoration(
                      color: palette.background,
                      borderRadius: BorderRadius.circular(AppSpacing.chipRadius),
                    ),
                    child: Text(
                      MaterialRequestStatus.label(request.status),
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: palette.foreground, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                itemSummary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                [
                  ?projectName,
                  if (request.createdAt != null) DateFormat('yyyy-MM-dd').format(request.createdAt!),
                ].join(' · '),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
