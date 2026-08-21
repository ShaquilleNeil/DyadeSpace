import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/daily_report.dart';
import '../../models/material_request.dart';
import '../../models/project.dart';
import '../../providers/auth_providers.dart';
import '../../providers/daily_reports_providers.dart';
import '../../providers/firebase_providers.dart';
import '../../providers/material_requests_providers.dart';
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

  /// Resolves the projects the signed-in user can submit against via a
  /// plain one-time fetch (not the reactive [myMemberProjectsProvider]
  /// stream) — a form dropdown just needs a snapshot, not a live
  /// subscription, and a direct `.get()` sidesteps relying on a
  /// StreamProvider's `.future` resolving from a cold, unwatched state.
  Future<List<Project>?> _resolveMyProjects() async {
    final me = ref.read(currentEmployeeProvider).value;
    if (me == null) return const [];
    try {
      return await ref
          .read(firestoreServiceProvider)
          .fetchProjectsForMember(me.id)
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(friendlyErrorMessage(e, fallback: 'Could not load your projects. Please try again.')),
        ),
      );
      return null;
    }
  }

  Future<void> _openMaterialRequestForm() async {
    final projects = await _resolveMyProjects();
    if (!mounted || projects == null) return;
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

  Future<void> _openDailyReportForm() async {
    final projects = await _resolveMyProjects();
    if (!mounted || projects == null) return;
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
    final canSubmit = me != null;

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
              // See admin_tasks_screen.dart for why every tab FAB needs its own tag.
              heroTag: 'reportsFab',
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
