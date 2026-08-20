import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../models/daily_report.dart';
import '../../../theme/app_spacing.dart';

/// Compact card for a daily report — submitter, date, summary preview.
/// Tapping pushes the report's detail route.
class DailyReportCard extends StatelessWidget {
  const DailyReportCard({super.key, required this.report, this.projectName});

  final DailyReport report;
  final String? projectName;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: InkWell(
        onTap: () => context.push('/daily-reports/${report.id}'),
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(report.submittedByName, style: Theme.of(context).textTheme.titleMedium),
                  ),
                  Text(
                    DateFormat('yyyy-MM-dd').format(report.date),
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                report.summary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (projectName != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  projectName!,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
