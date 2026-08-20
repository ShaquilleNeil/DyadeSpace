import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/material_requests_providers.dart';
import '../../../providers/projects_providers.dart';
import 'material_request_card.dart';

/// Role-scoped material request feed — the provider itself decides what's
/// visible (own submissions for a worker, project-scoped for a manager,
/// everything for admin); this just renders whatever it returns.
class MaterialRequestsList extends ConsumerWidget {
  const MaterialRequestsList({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final requestsAsync = ref.watch(visibleMaterialRequestsProvider);

    return requestsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, st) => Center(child: Text('Error: $e')),
      data: (requests) {
        if (requests.isEmpty) {
          return const Center(child: Text('No material requests yet'));
        }
        final sorted = [...requests]
          ..sort((a, b) => (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));
        return ListView.builder(
          padding: const EdgeInsets.all(14),
          itemCount: sorted.length,
          itemBuilder: (context, index) {
            final request = sorted[index];
            final project = ref.watch(projectByIdProvider(request.projectId)).value;
            return MaterialRequestCard(request: request, projectName: project?.name);
          },
        );
      },
    );
  }
}
