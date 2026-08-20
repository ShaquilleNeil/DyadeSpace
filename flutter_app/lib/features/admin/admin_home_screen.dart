import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/projects_providers.dart';
import '../shared/widgets/notification_bell.dart';
import '../shared/widgets/project_form.dart';
import '../shared/widgets/project_item.dart';
import '../shared/widgets/search_field.dart';

/// Admin sees and creates every project — staffing (who's on it, their
/// role) is managed from the Staff tab instead of here.
class AdminHomeScreen extends ConsumerStatefulWidget {
  const AdminHomeScreen({super.key});

  @override
  ConsumerState<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends ConsumerState<AdminHomeScreen> {
  String _query = '';

  void _openAddProjectSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => ProjectForm(
        onSave: (name, description, address, photo) async {
          await ref.read(projectControllerProvider).createProject(
                name: name,
                description: description,
                address: address,
                photoFile: photo,
              );
          if (sheetContext.mounted) Navigator.of(sheetContext).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(visibleProjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Projects'),
        automaticallyImplyLeading: false,
        actions: const [NotificationBell()],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openAddProjectSheet,
        child: const Icon(Icons.add),
      ),
      body: SafeArea(
        child: Column(
          children: [
            SearchField(onChanged: (value) => setState(() => _query = value)),
            Expanded(
              child: projectsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('Error: $e')),
                data: (projects) {
                  final displayed = _query.trim().isEmpty
                      ? projects
                      : projects
                          .where((p) => p.name.toLowerCase().contains(_query.toLowerCase()))
                          .toList();

                  if (displayed.isEmpty) {
                    return const Center(child: Text('No projects found'));
                  }

                  return ListView.builder(
                    itemCount: displayed.length,
                    itemBuilder: (context, index) => ProjectItem(project: displayed[index]),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
