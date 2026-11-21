import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';

/// The app's full-width primary action button.
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool loading;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.loading = false,
  });

  VoidCallback? get _effectiveOnPressed {
    if (loading || onPressed == null) return null;
    return () {
      HapticFeedback.lightImpact();
      onPressed!();
    };
  }

  Widget _label() {
    if (loading) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              color: AppTokens.onAccent,
              strokeWidth: 2,
            ),
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      );
    }
    return Text(label);
  }

  @override
  Widget build(BuildContext context) {
    final style = FilledButton.styleFrom(
      backgroundColor: AppTokens.accent,
      foregroundColor: AppTokens.onAccent,
      minimumSize: const Size(double.infinity, 52),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTokens.buttonRadius),
      ),
      textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
    );
    if (icon != null && !loading) {
      return FilledButton.icon(
        onPressed: _effectiveOnPressed,
        style: style,
        icon: Icon(icon),
        label: Text(label),
      );
    }
    return FilledButton(
      onPressed: _effectiveOnPressed,
      style: style,
      child: _label(),
    );
  }
}
