import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// Progress bar for a delivery run: a thin track with a green
/// fill. The fill measures completion, so it is green at every
/// percentage — green while the run is in progress and green
/// once every stop is done. Used wherever a run is shown: the
/// Run progress screen, By person, and the driver's own run
/// screen. Also reused as the thin task-progress bar on cards
/// and the stage-progress bar on roadmap cards.
class RunProgressBar extends StatelessWidget {
  final int completed;
  final int total;
  final double height;

  /// Fill colour override — when null, green (completion).
  final Color? fillColor;

  const RunProgressBar({
    super.key,
    required this.completed,
    required this.total,
    this.height = 6,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final fraction =
        total == 0 ? 0.0 : (completed / total).clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: Container(
        height: height,
        color: tokens.border,
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction,
          child: Container(
            color: fillColor ?? tokens.statusDone,
          ),
        ),
      ),
    );
  }
}
