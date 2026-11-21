import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_strings.dart';
import '../../models/site.dart';
import '../../models/stage.dart';
import '../../providers/locale_provider.dart';
import '../../providers/sites_provider.dart';
import '../../providers/stages_provider.dart';
import '../../theme/app_tokens.dart';
import '../../widgets/site_editor.dart';
import 'site_tasks_screen.dart';

/// Sites management (admin/manager): the job-site / building
/// list behind every task. Add, rename, re-address, or delete a
/// site. A site that still has tasks cannot be deleted (the
/// button explains why) - tasks would be orphaned otherwise.
/// Sites stay reference data with no service class, so - like
/// sites_provider - this screen talks to Firestore directly.
class SitesScreen extends ConsumerWidget {
  const SitesScreen({super.key});

  /// The lines under a site's name: its address (when there is
  /// one), then its current roadmap stage — name + % (Done
  /// tasks only, same derivation as the roadmap cards) with a
  /// status-coloured dot — or "No roadmap" when the site has no
  /// stages. Null when there is nothing to show (no address,
  /// and the roadmap state is still loading).
  Widget? _siteSubtitle(AppColors tokens, AppStrings s,
      StageIndex? stageIndex, Site site) {
    final lines = <Widget>[];
    if (site.address.isNotEmpty) {
      lines.add(Text(
        site.address,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ));
    }
    if (stageIndex != null) {
      final current = stageIndex.currentStageForSite(site.id);
      if (current == null) {
        lines.add(Text(
          s.noRoadmap,
          style: TextStyle(
            fontSize: 12,
            fontStyle: FontStyle.italic,
            color: tokens.textTertiary,
          ),
        ));
      } else {
        final progress = stageIndex.progressOf(current);
        final pct = progress.total == 0
            ? 0
            : ((progress.done / progress.total) * 100).round();
        final status = stageIndex.statusOf(current);
        lines.add(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: stageStatusColor(status, tokens),
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${current.name} · $pct%',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: tokens.textSecondary,
                ),
              ),
            ),
          ],
        ));
      }
    }
    if (lines.isEmpty) return null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lines,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final sitesAsync = ref.watch(sitesProvider);
    // The roadmap state for every site, or null while the
    // stages/tasks streams are still loading — the list shows
    // no roadmap line until it arrives rather than flashing a
    // wrong "No roadmap".
    final stageIndex = ref.watch(stageIndexProvider);
    return Scaffold(
      appBar: AppBar(title: Text(s.sites)),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text(s.addSite),
        onPressed: () => showSiteEditor(context, ref, null),
      ),
      body: sitesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (sites) => sites.isEmpty
            ? Center(child: Text(s.noSites))
            : ListView(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                children: [
                  for (final site in sites)
                    Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        // The site's own Monday group colour — the
                        // same colour the site's group carries on
                        // the board.
                        leading: CircleAvatar(
                          backgroundColor: AppTokens.siteTagColorFor(site.id)
                              .withValues(alpha: 0.18),
                          child: Icon(Icons.apartment_outlined,
                              size: 20,
                              color:
                                  AppTokens.siteTagColorFor(site.id)),
                        ),
                        title: Text(site.name),
                        // Address on the first line (when there
                        // is one), then the site's current
                        // roadmap stage — name + % — or "No
                        // roadmap" when the site has no stages.
                        // Tapping still opens the site's tasks.
                        subtitle: _siteSubtitle(
                            tokens, s, stageIndex, site),
                        // Monday-style: tap a site to see its
                        // tasks, like opening a group on a Monday
                        // board. Renaming stays on the pencil.
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                              builder: (_) =>
                                  SiteTasksScreen(site: site)),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              tooltip: s.editSite,
                              onPressed: () =>
                                  showSiteEditor(context, ref, site),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline),
                              tooltip: s.delete,
                              onPressed: () =>
                                  deleteSite(context, ref, site),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
