import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/daily_report.dart';
import '../../models/material_request.dart';
import '../../providers/auth_providers.dart';
import '../../providers/daily_reports_providers.dart';
import '../../providers/material_requests_providers.dart';
import '../../providers/projects_providers.dart';
import '../../utils/friendly_error.dart';
import 'widgets/daily_report_form.dart';
import 'widgets/daily_reports_list.dart';
import 'widgets/material_request_form.dart';
import 'widgets/material_requests_list.dart';

/// Shared by all three shells: material requests and daily reports live
/// under one "Reports" tab so the bottom nav doesn't grow to six items.
/// The provider layer (not this widget) decides what's visible per role.
class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(length: 2, vsync: this)
    ..addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _openMaterialRequestForm() {
    final projects = ref.read(visibleProjectsProvider).value ?? const [];
    if (projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're not assigned to a project yet")),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => MaterialRequestForm(
        projects: projects,
        onSave: (projectId, items, notes, photos) async {
          try {
            final me = ref.read(currentEmployeeProvider).value!;
            await ref.read(materialRequestControllerProvider).submit(
                  MaterialRequest(
                    id: '',
                    projectId: projectId,
                    requestedById: me.id,
                    requestedByName: me.fullName,
                    items: items,
                    notes: notes,
                  ),
                  photos: photos,
                );
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          } catch (e) {
            if (!sheetContext.mounted) return;
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(
                content: Text(
                  friendlyErrorMessage(e, fallback: 'Could not submit request. Please try again.'),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  void _openDailyReportForm() {
    final projects = ref.read(visibleProjectsProvider).value ?? const [];
    if (projects.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You're not assigned to a project yet")),
      );
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => DailyReportForm(
        projects: projects,
        onSave: (projectId, date, summary, taskNotes, photos) async {
          try {
            final me = ref.read(currentEmployeeProvider).value!;
            await ref.read(dailyReportControllerProvider).submit(
                  DailyReport(
                    id: '',
                    projectId: projectId,
                    submittedById: me.id,
                    submittedByName: me.fullName,
                    date: date,
                    summary: summary,
                    taskNotes: taskNotes,
                  ),
                  photos: photos,
                );
            if (sheetContext.mounted) Navigator.of(sheetContext).pop();
          } catch (e) {
            if (!sheetContext.mounted) return;
            ScaffoldMessenger.of(sheetContext).showSnackBar(
              SnackBar(
                content: Text(
                  friendlyErrorMessage(e, fallback: 'Could not submit report. Please try again.'),
                ),
              ),
            );
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(currentEmployeeProvider).value;
    final canSubmit = me != null && !me.isAdmin;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        automaticallyImplyLeading: false,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Material Requests'),
            Tab(text: 'Daily Reports'),
          ],
        ),
      ),
      floatingActionButton: !canSubmit
          ? null
          : FloatingActionButton(
              onPressed:
                  _tabController.index == 0 ? _openMaterialRequestForm : _openDailyReportForm,
              child: const Icon(Icons.add),
            ),
      body: SafeArea(
        child: TabBarView(
          controller: _tabController,
          children: const [MaterialRequestsList(), DailyReportsList()],
        ),
      ),
    );
  }
}
