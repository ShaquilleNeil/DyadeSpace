import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../providers/auth_providers.dart';
import '../../providers/daily_reports_providers.dart';
import '../../providers/projects_providers.dart';
import '../../theme/app_spacing.dart';
import '../../utils/confirm.dart';
import '../../utils/friendly_error.dart';

class DailyReportViewScreen extends ConsumerWidget {
  const DailyReportViewScreen({super.key, required this.reportId});

  final String reportId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportAsync = ref.watch(dailyReportByIdProvider(reportId));
    final me = ref.watch(currentEmployeeProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Daily Report')),
      body: SafeArea(
        child: reportAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text(friendlyErrorMessage(e))),
          data: (report) {
            if (report == null) {
              return const Center(child: Text('Report not found'));
            }
            final project = ref.watch(projectByIdProvider(report.projectId)).value;
            final canDelete = me != null && (me.isAdmin || report.submittedById == me.id);

            return SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Submitted by', style: Theme.of(context).textTheme.labelMedium),
                  Text(report.submittedByName, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  Text('Project', style: Theme.of(context).textTheme.labelMedium),
                  Text(project?.name ?? '—', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  Text('Date', style: Theme.of(context).textTheme.labelMedium),
                  Text(DateFormat('yyyy-MM-dd').format(report.date), style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.lg),
                  Text('Summary', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: SizedBox(width: double.infinity, child: Text(report.summary)),
                    ),
                  ),
                  if (report.taskNotes?.isNotEmpty ?? false) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text('Task / Progress Notes', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        child: SizedBox(width: double.infinity, child: Text(report.taskNotes!)),
                      ),
                    ),
                  ],
                  if (report.photoUrls.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Text('Photos', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.sm,
                      runSpacing: AppSpacing.sm,
                      children: report.photoUrls.map((url) {
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
                  if (canDelete) ...[
                    const SizedBox(height: AppSpacing.xl),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error,
                        side: BorderSide(color: Theme.of(context).colorScheme.error),
                      ),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Delete Report'),
                      onPressed: () async {
                        final confirmed = await confirmDialog(
                          context,
                          title: 'Delete report?',
                          message: 'This permanently deletes this daily report.',
                        );
                        if (confirmed) {
                          await ref.read(dailyReportControllerProvider).delete(reportId);
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
