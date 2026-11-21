import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_strings.dart';
import '../models/time_entry.dart';
import '../theme/app_tokens.dart';
import '../utils/hours_format.dart';
import '../utils/week_hours.dart';

/// Week-hours header for the profile Clock-in tab: the
/// current week's total ("This week: 24 h 30 min") and the
/// week range, Monday–Sunday. The total counts closed
/// entries' hours plus an open entry's live time so far, so
/// it moves through the day: while any entry in the week is
/// still open, a 60-second timer rebuilds the header so the
/// live minutes keep up without waiting for the next stream
/// event.
class WeekHoursHeader extends StatefulWidget {
  final List<TimeEntry> entries;
  final AppStrings strings;

  const WeekHoursHeader({
    super.key,
    required this.entries,
    required this.strings,
  });

  @override
  State<WeekHoursHeader> createState() => _WeekHoursHeaderState();
}

class _WeekHoursHeaderState extends State<WeekHoursHeader> {
  Timer? _timer;

  bool get _hasOpenInWeek {
    final weekStart = weekStartFor(DateTime.now());
    return entriesInWeek(widget.entries, weekStart).any((e) => e.isOpen);
  }

  @override
  void initState() {
    super.initState();
    _maybeStartTimer();
  }

  @override
  void didUpdateWidget(WeekHoursHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    _maybeStartTimer();
  }

  void _maybeStartTimer() {
    if (_hasOpenInWeek && _timer == null) {
      _timer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!_hasOpenInWeek && _timer != null) {
      _timer!.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = widget.strings;
    final weekStart = weekStartFor(DateTime.now());
    final weekEnd = weekEndFor(weekStart);
    final total = weekTotalIncludingLive(widget.entries, weekStart);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(AppTokens.cardRadius),
        border: Border.all(color: tokens.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.thisWeekHours(formatHoursMinutes(total)),
                  style: Theme.of(context).textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  s.hoursWeekLabel(
                    DateFormat('MMM d').format(weekStart),
                    DateFormat('MMM d, yyyy').format(weekEnd),
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    color: tokens.textSecondary,
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
