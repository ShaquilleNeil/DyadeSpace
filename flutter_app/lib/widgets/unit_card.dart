import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/unit.dart';
import '../providers/locale_provider.dart';
import '../theme/app_tokens.dart';
import 'run_progress_bar.dart';

/// One unit (apartment) of a site, per the units concept: name
/// and completion % at the top, thin green progress bar, "x of y
/// tasks done" plus a blocked count when any task is blocked.
/// Tap opens the unit's tasks. Admin controls (rename /
/// delete) only when [isManager] is true — the delete
/// confirmation lives in the site view, like the stage delete.
/// The nested icon buttons win the gesture arena over the card
/// tap, so renaming or deleting never opens the unit by
/// accident.
class UnitCard extends ConsumerWidget {
  final Unit unit;
  final int done;
  final int total;
  final int blockedCount;
  final bool isManager;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  const UnitCard({
    super.key,
    required this.unit,
    required this.done,
    required this.total,
    required this.blockedCount,
    required this.isManager,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final pct = total == 0 ? 0 : ((done / total) * 100).round();

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(AppTokens.cardRadius),
          border: Border.all(color: tokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.apartment_outlined,
                    size: 18, color: tokens.textTertiary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    unit.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$pct%',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    fontFeatures: const [
                      FontFeature.tabularFigures(),
                    ],
                    // The % measures completion, so it is green
                    // at every percentage — same rule as the
                    // stage card.
                    color: tokens.statusDone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 11),
            RunProgressBar(
              completed: done,
              total: total,
              height: 4,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textSecondary,
                      ),
                      children: [
                        TextSpan(
                          text: s.tasksDone(done, total),
                          style: TextStyle(
                            color: tokens.statusDone,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (blockedCount > 0)
                          TextSpan(
                            text: ' · $blockedCount ${s.blocked}',
                            style: TextStyle(
                              color: tokens.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                if (isManager) ...[
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onRename();
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.edit_outlined,
                          size: 18, color: tokens.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      onDelete();
                    },
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(Icons.delete_outline,
                          size: 18, color: tokens.danger),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
