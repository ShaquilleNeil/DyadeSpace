import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/site.dart';
import '../providers/locale_provider.dart';
import '../theme/app_tokens.dart';

/// Group header (board, Today, My Day): a chevron (when
/// collapsible), a coloured dot derived from the site id, the
/// site name with an optional task count, and the address muted
/// below. The colour is derived from the site id, so a site
/// keeps its colour on every screen.
///
/// On the board the header is interactive: the chevron collapses
/// / expands the group's tasks, and tapping the site name opens
/// that site's own board. Pass neither callback and the header is
/// just a label.
class SiteHeader extends ConsumerWidget {
  final Site? site;
  final int? count;
  final bool collapsed;
  final VoidCallback? onToggleCollapse;
  final VoidCallback? onOpenSite;

  const SiteHeader({
    super.key,
    required this.site,
    this.count,
    this.collapsed = false,
    this.onToggleCollapse,
    this.onOpenSite,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final color = AppTokens.siteTagColorFor(site?.id ?? 'unknown');
    final name = site?.name ?? 'Unknown site';
    final address = site?.address ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (onToggleCollapse != null)
            GestureDetector(
              onTap: onToggleCollapse,
              child: Padding(
                padding: const EdgeInsets.only(right: 2),
                child: AnimatedRotation(
                  turns: collapsed ? 0.0 : 0.25,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: tokens.textTertiary,
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onOpenSite,
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    if (count != null)
                      Text(
                        s.tasksCount(count!),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: tokens.textTertiary,
                        ),
                      ),
                  ],
                ),
                if (address.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      address,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: tokens.textTertiary,
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
