import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// A loading placeholder card with a hand-rolled shimmer:
/// a diagonal white gradient sweeps left to right over a
/// raised surface. No extra package.
class SkeletonCard extends StatefulWidget {
  final double height;

  const SkeletonCard({super.key, this.height = 92});

  @override
  State<SkeletonCard> createState() => _SkeletonCardState();
}

class _SkeletonCardState extends State<SkeletonCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 400.0;
        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: widget.height,
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: tokens.border),
            ),
            child: Stack(
              children: [
                AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    const sweepWidth = 140.0;
                    final left =
                        -sweepWidth + _controller.value * (width + sweepWidth * 2);
                    return Positioned(
                      left: left,
                      top: 0,
                      bottom: 0,
                      width: sweepWidth,
                      child: Transform(
                        transform: Matrix4.skewX(-0.35),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                tokens.textPrimary.withValues(alpha: 0),
                                tokens.textPrimary.withValues(alpha: 0.05),
                                tokens.textPrimary.withValues(alpha: 0),
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// A vertical stack of skeleton cards for a loading list.
/// Scrollable on purpose: a fixed column of N cards is taller
/// than a short viewport (6 x 92px + spacing = 612px) and used
/// to overflow the body by 80px. The scroll view sizes to its
/// parent and never reports an overflow; the cards are
/// placeholders, so scrolling them is harmless.
class SkeletonList extends StatelessWidget {
  final int count;

  const SkeletonList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          children: [
            for (var i = 0; i < count; i++) ...[
              if (i > 0) const SizedBox(height: 12),
              const SkeletonCard(),
            ],
          ],
        ),
      ),
    );
  }
}
