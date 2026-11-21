import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';

/// Small uppercase section heading (e.g. "TEAM", "PENDING").
class SectionLabel extends StatelessWidget {
  final String label;

  const SectionLabel(this.label, {super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.8,
        color: tokens.textTertiary,
      ),
    );
  }
}
