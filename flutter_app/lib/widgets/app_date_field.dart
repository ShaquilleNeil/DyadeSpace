import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../utils/date_format.dart';

/// A read-only date field that looks like a normal outlined
/// field. Tapping anywhere opens the date picker; when a value
/// is set and [onClear] is provided, a small clear button sits
/// next to the calendar icon.
///
/// The [TextEditingController] is created once in [initState]
/// and disposed in [dispose] — it used to be created fresh
/// inside [build] on every rebuild and never disposed, leaking
/// a controller (and its listener) per rebuild.
class AppDateField extends StatefulWidget {
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onPick;
  final VoidCallback? onClear;
  final DateTime? firstDate;
  final DateTime? lastDate;

  const AppDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onPick,
    this.onClear,
    this.firstDate,
    this.lastDate,
  });

  @override
  State<AppDateField> createState() => _AppDateFieldState();
}

class _AppDateFieldState extends State<AppDateField> {
  late final TextEditingController _controller;
  String _locale = 'en';

  @override
  void initState() {
    super.initState();
    // Text is filled in didChangeDependencies, where reading
    // the locale is allowed (initState cannot depend on
    // inherited widgets).
    _controller = TextEditingController();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Also re-runs when the locale changes, so the displayed
    // date follows a language switch.
    _locale = Localizations.localeOf(context).languageCode;
    _syncText();
  }

  @override
  void didUpdateWidget(AppDateField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) _syncText();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncText() {
    final text = widget.value == null
        ? ''
        : formatDisplayDate(widget.value!, _locale);
    if (_controller.text != text) _controller.text = text;
  }

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: widget.value ?? DateTime.now(),
      firstDate: widget.firstDate ?? DateTime(2025),
      lastDate: widget.lastDate ?? DateTime(2100),
    );
    if (picked != null) widget.onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    // Read-only with onTap: the field itself opens the picker,
    // and the clear (x) button in the suffix stays tappable.
    // (The old AbsorbPointer wrapper swallowed the clear tap.)
    return TextField(
      readOnly: true,
      controller: _controller,
      onTap: _pick,
      decoration: InputDecoration(
        labelText: widget.label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.inputRadius),
        ),
        suffixIcon: widget.value != null && widget.onClear != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: widget.onClear,
                  ),
                  const Icon(Icons.calendar_today_outlined, size: 20),
                  const SizedBox(width: 12),
                ],
              )
            : const Icon(Icons.calendar_today_outlined, size: 20),
      ),
    );
  }
}
