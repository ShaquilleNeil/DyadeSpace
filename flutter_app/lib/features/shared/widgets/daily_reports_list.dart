import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/daily_reports_providers.dart';
import '../../../providers/projects_providers.dart';
import 'daily_report_card.dart';

/// Role-scoped daily report feed — mirrors [MaterialRequestsList].
class DailyReportsList extends ConsumerWidget {
  const DailyReportsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(visibleDailyReportsProvider);

    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (reports) {
        if (reports.isEmpty) {
          return const Center(child: Text('No daily reports yet'));
        }
        final sorted = [...reports]..sort((a, b) => b.date.compareTo(a.date));
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: sorted.length,
          itemBuilder: (context, index) {
            final report = sorted[index];
            final project = ref.watch(projectByIdProvider(report.projectId)).value;
            return DailyReportCard(report: report, projectName: project?.name);
          },
        );
      },
    );
  }
}
