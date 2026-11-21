import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/app_strings.dart';
import '../models/site_visit.dart';
import '../theme/app_tokens.dart';
import '../utils/hours_format.dart';

/// One entry's site visits, in arrival order: site, arrival
/// and departure times, and the duration. The open visit —
/// the worker is still there — reads "since HH:mm · Here
/// now". When the entry is already closed but a visit is
/// still open (the 23:59 server auto-close ended the day
/// before the phone saw it), the visit's departure shows the
/// entry's clock-out time instead of "Here now".
class SiteVisitsList extends StatelessWidget {
  final List<SiteVisit> visits;

  /// The entry's clock-out time, for the open-visit fallback
  /// above. Null while the entry is still open.
  final DateTime? entryClockOutAt;
  final AppStrings strings;

  const SiteVisitsList({
    super.key,
    required this.visits,
    required this.entryClockOutAt,
    required this.strings,
  });

  String _timeOf(DateTime at) => DateFormat('HH:mm').format(at);

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final v in visits) ...[
          Builder(
            builder: (context) {
              // The visit's end: its own departure, or the
              // entry's clock-out when the 23:59 auto-close
              // ended the day before the phone saw it. Only
              // a visit on a still-open entry is "here now"
              // and keeps counting.
              final end = v.leftAt ?? entryClockOutAt;
              final hereNow = v.isOpen && end == null;
              final minutes = hereNow
                  ? v.minutesSoFar
                  : (end ?? v.arrivedAt).difference(v.arrivedAt).inMinutes;
              return Padding(
                padding: const EdgeInsets.only(left: 8, top: 4, bottom: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 16,
                      color: tokens.textTertiary,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        v.siteName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      hereNow
                          ? '${s.clockedInSince(_timeOf(v.arrivedAt))} · ${s.hereNow}'
                          : '${_timeOf(v.arrivedAt)} – ${_timeOf(end ?? v.arrivedAt)} · ${formatHoursMinutes(minutes / 60)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    );
  }
}
