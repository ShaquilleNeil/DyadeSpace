import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../l10n/app_strings.dart';
import '../models/client_share.dart';
import '../models/stage.dart';
import '../models/task_item.dart';
import '../providers/locale_provider.dart';
import '../services/client_share_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/photo_viewer.dart';
import 'web/web_shared.dart';

/// The public client view: what a client sees when they open
/// a share link (`/client/<token>`). Read-only, no app, no
/// login, no actions — site name, roadmap stages with status,
/// tasks with status, and recently completed work with photos.
///
/// No auth is needed to reach this screen (app.dart routes
/// `/client/<token>` before the sign-in gate, like `/privacy`),
/// and the screen never reads Firestore directly: the payload
/// comes from the `getClientShare` callable, which validates
/// the token server-side. An invalid or revoked token shows
/// the "link not valid" state, never a permission error wall.
class ClientShareScreen extends ConsumerStatefulWidget {
  final String token;
  const ClientShareScreen({super.key, required this.token});

  @override
  ConsumerState<ClientShareScreen> createState() => _ClientShareScreenState();
}

class _ClientShareScreenState extends ConsumerState<ClientShareScreen> {
  ClientSiteProgress? _progress;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final progress = await ref
          .read(clientShareServiceProvider)
          .fetchPublicProgress(widget.token);
      if (!mounted) return;
      setState(() => _progress = progress);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(title: Text(s.clientShareTitle)),
      body: progress == null
          ? Center(
              child: _failed
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        s.clientShareInvalid,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: tokens.textSecondary),
                      ),
                    )
                  : const CircularProgressIndicator(),
            )
          : ListView(
              padding: webContentPadding(MediaQuery.sizeOf(context).width),
              children: [
                Text(
                  progress.siteName,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800),
                ),
                if (progress.siteAddress.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    progress.siteAddress,
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                ],
                const SizedBox(height: 18),
                WebSectionHeader(title: s.roadmap),
                const SizedBox(height: 10),
                if (progress.stages.isEmpty)
                  Text(s.noRoadmap,
                      style: TextStyle(color: tokens.textSecondary))
                else
                  for (final stage in progress.stages) ...[
                    _stageCard(context, s, tokens, stage),
                    const SizedBox(height: 10),
                  ],
                const SizedBox(height: 18),
                WebSectionHeader(title: s.clientShareRecentWork),
                const SizedBox(height: 10),
                if (progress.recentlyCompleted.isEmpty)
                  Text(s.clientShareNoProgress,
                      style: TextStyle(color: tokens.textSecondary))
                else
                  for (final task in progress.recentlyCompleted) ...[
                    _taskCard(context, s, tokens, task),
                    const SizedBox(height: 10),
                  ],
                const SizedBox(height: 18),
                WebSectionHeader(title: s.tasks),
                const SizedBox(height: 10),
                if (progress.tasks.isEmpty)
                  Text(s.clientShareNoProgress,
                      style: TextStyle(color: tokens.textSecondary))
                else
                  for (final task in progress.tasks) ...[
                    _taskCard(context, s, tokens, task),
                    const SizedBox(height: 10),
                  ],
                const SizedBox(height: 24),
                Text(
                  s.clientShareFooter,
                  style: TextStyle(
                      fontSize: 12, color: tokens.textTertiary),
                ),
              ],
            ),
    );
  }

  Widget _stageCard(BuildContext context, AppStrings s, AppColors tokens,
      ClientStageProgress stage) {
    final status = StageStatus.values.firstWhere(
      (v) => v.name == stage.status,
      orElse: () => StageStatus.ready,
    );
    final pct = stage.total == 0
        ? 0
        : (stage.done / stage.total * 100).round();
    return WebCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: stageStatusColor(status, tokens),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  stage.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              WebPill(
                label: s.stageStatusLabel(status),
                color: stageStatusColor(status, tokens),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: stage.total == 0 ? 0 : stage.done / stage.total,
              minHeight: 6,
              backgroundColor: tokens.surfaceRaised,
              valueColor: AlwaysStoppedAnimation<Color>(
                  stageStatusColor(status, tokens)),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${stage.done}/${stage.total} · $pct%',
            style: TextStyle(fontSize: 12, color: tokens.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _taskCard(BuildContext context, AppStrings s, AppColors tokens,
      ClientTaskProgress task) {
    final status = TaskStatus.values.firstWhere(
      (v) => v.name == task.status,
      orElse: () => TaskStatus.todo,
    );
    return WebCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  task.title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              webTaskStatusPill(s, tokens, status),
            ],
          ),
          if (task.unitName != null && task.unitName!.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              task.unitName!,
              style: TextStyle(fontSize: 12, color: tokens.textSecondary),
            ),
          ],
          if (task.finishedAt != null) ...[
            const SizedBox(height: 2),
            Text(
              DateFormat('EEE, MMM d').format(task.finishedAt!),
              style: TextStyle(fontSize: 12, color: tokens.textTertiary),
            ),
          ],
          if (task.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: task.photoUrls.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final url = task.photoUrls[index];
                  return GestureDetector(
                    onTap: () => showPhotoViewer(
                      context,
                      items: task.photoUrls
                          .map((u) => PhotoViewerItem(
                              url: u, label: task.title))
                          .toList(),
                      initialIndex: index,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        url,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          width: 72,
                          height: 72,
                          color: tokens.surfaceRaised,
                          child: Icon(Icons.broken_image_outlined,
                              color: tokens.textTertiary),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
