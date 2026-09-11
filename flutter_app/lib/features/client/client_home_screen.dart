import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/projects_providers.dart';
import '../shared/widgets/notification_bell.dart';
import '../shared/widgets/project_item.dart';
import '../shared/widgets/search_field.dart';
import '../../utils/friendly_error.dart';

/// A client's read-only view of the project(s) they've been added to —
/// admin assigns projects via the Staff screen's Clients filter.
class ClientHomeScreen extends ConsumerStatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  ConsumerState<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends ConsumerState<ClientHomeScreen> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final projectsAsync = ref.watch(visibleProjectsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Projects'),
        automaticallyImplyLeading: false,
        actions: const [NotificationBell()],
      ),
      body: SafeArea(
        child: Column(
          children: [
            SearchField(onChanged: (value) => setState(() => _query = value)),
            Expanded(
              child: projectsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text(friendlyErrorMessage(e))),
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
