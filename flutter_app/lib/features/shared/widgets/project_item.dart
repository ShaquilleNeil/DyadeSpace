import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../models/project.dart';
import '../../../theme/app_spacing.dart';

/// Expandable project card — collapsed shows just the name; expanded shows
/// the photo, address, and a "View Details" button that pushes the project
/// route.
class ProjectItem extends StatefulWidget {
  const ProjectItem({super.key, required this.project});

  final Project project;

  @override
  State<ProjectItem> createState() => _ProjectItemState();
}

class _ProjectItemState extends State<ProjectItem> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      project.name.isEmpty ? 'Unnamed Project' : project.name,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_circle_down_outlined),
                ],
              ),
            ),
          ),
          if (_expanded)
            SizedBox(
              width: double.infinity,
              height: 250,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (project.photoUrl?.isNotEmpty ?? false)
                    CachedNetworkImage(
                      imageUrl: project.photoUrl!,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => Container(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                      errorWidget: (context, url, error) =>
                          Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                    )
                  else
                    Container(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Location', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                          Text(
                            project.address?.isNotEmpty ?? false ? project.address! : 'N/A',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          FilledButton.tonalIcon(
                            onPressed: () => context.push('/project/${project.id}'),
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white.withValues(alpha: 0.15),
                              foregroundColor: Colors.white,
                            ),
                            icon: const Icon(Icons.arrow_forward, color: Colors.white),
                            label: const Text('View Details', style: TextStyle(color: Colors.white)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
