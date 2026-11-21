import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// One clock-in / clock-out pair for one worker — at one
/// site, or for the whole day when the worker moves between
/// sites (a day entry: `siteId` and `siteName` are empty, and
/// the day's moves are recorded as site visits in the
/// `siteVisits` subcollection instead).
///
/// GPS is captured at the tap (clock-in, clock-out) and — while
/// the entry is open — as a route trail in the `breadcrumbs`
/// subcollection (see Breadcrumb: one point every 5 minutes
/// from the foreground tracking service, only while clocked
/// in). `flagged` means the entry needs a manager's eye: the
/// GPS check failed at clock-in or clock-out (outside the site
/// radius, location unavailable, or no location set for the
/// site). A flagged entry is never blocked — the hours still
/// count; the flag is only a review marker.
///
/// `flagReason` is a code, mapped to a localized label by
/// AppStrings.flagReasonLabel: 'outside-radius',
/// 'clock-out-outside-radius', 'no-location', 'no-site-location'.
///
/// `auto` marks entries the auto clock-in created (arrival at
/// a site) instead of a manual tap — the history list shows an
/// "Auto" tag for them. An auto entry closed less than 10
/// minutes after it opened is deleted by the server
/// (verifyClockOut) so a drive-by never counts as work.
class TimeEntry {
  final String id;
  final String userId;

  /// Name at clock-in time (names change; the stored name is
  /// what the Hours screen and the CSV show).
  final String userName;

  final String siteId;
  final String siteName;

  /// Toronto (device-local) date of the clock-in, yyyy-MM-dd.
  /// String so week filtering is a plain range compare.
  final String date;

  final DateTime clockInAt;
  final double? clockInLat;
  final double? clockInLng;
  final bool clockInVerified;

  final DateTime? clockOutAt;
  final double? clockOutLat;
  final double? clockOutLng;
  final bool clockOutVerified;

  /// Hours between clock-in and clock-out, 2 decimals. Null
  /// while the entry is still open.
  final double? hours;

  final bool flagged;
  final String? flagReason;

  /// True when the auto clock-in created this entry.
  final bool auto;

  const TimeEntry({
    required this.id,
    required this.userId,
    required this.userName,
    required this.siteId,
    required this.siteName,
    required this.date,
    required this.clockInAt,
    this.clockInLat,
    this.clockInLng,
    this.clockInVerified = false,
    this.clockOutAt,
    this.clockOutLat,
    this.clockOutLng,
    this.clockOutVerified = false,
    this.hours,
    this.flagged = false,
    this.flagReason,
    this.auto = false,
  });

  bool get isOpen => clockOutAt == null;

  /// Hours so far for an open entry (live value, not stored).
  double get hoursSoFar {
    final end = clockOutAt ?? DateTime.now();
    final minutes = end.difference(clockInAt).inMinutes;
    if (minutes <= 0) return 0;
    return double.parse((minutes / 60).toStringAsFixed(2));
  }

  /// Hours to display: the server-computed value when it
  /// exists, otherwise the time between clock-in and
  /// clock-out (or now, while still clocked in). The server
  /// value wins when it arrives — the local value is only a
  /// stand-in for entries closed before the verify function
  /// ran (their `hours` field is null, so the Hours screen
  /// showed "—" and the totals stayed at zero).
  double get effectiveHours => hours ?? hoursSoFar;

  factory TimeEntry.fromFirestore(DocumentSnapshot doc) {
    return TimeEntry.fromMap(doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  /// Parses one doc, or null when it is malformed (see
  /// [fromMap]). List callers should use this and drop the
  /// nulls instead of letting one bad doc break the whole
  /// stream or render invented data.
  static TimeEntry? tryFromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return null;
    return tryFromMap(doc.id, data);
  }

  /// Parses a whole snapshot, skipping malformed docs with a
  /// logged warning instead of failing the list or inventing
  /// data for them. Use this for every list stream
  /// (`watchAllEntries`, `watchEntriesForUser`, …).
  static List<TimeEntry> parseDocs(Iterable<DocumentSnapshot> docs) {
    final out = <TimeEntry>[];
    for (final doc in docs) {
      final entry = tryFromFirestore(doc);
      if (entry != null) out.add(entry);
    }
    return out;
  }

  /// Like [fromMap], but returns null (with a logged warning)
  /// instead of throwing on a malformed doc.
  static TimeEntry? tryFromMap(String id, Map<String, dynamic> map) {
    try {
      return TimeEntry.fromMap(id, map);
    } on FormatException catch (e) {
      debugPrint('Skipping malformed time entry $id: $e');
      return null;
    }
  }

  /// Throws [FormatException] when `clockInAt` is missing or
  /// not a Timestamp. A clock-in time is the one field an
  /// entry cannot exist without, so a doc without it is
  /// malformed — it used to parse as "now", which rendered a
  /// fake clock-in time (and fake live hours) as if real.
  /// Callers that must not fail on one bad doc should use
  /// [tryFromMap]/[tryFromFirestore]/[parseDocs] instead.
  factory TimeEntry.fromMap(String id, Map<String, dynamic> map) {
    final clockInAt = map['clockInAt'];
    if (clockInAt is! Timestamp) {
      throw FormatException(
          'TimeEntry $id has no valid clockInAt (got $clockInAt)');
    }
    return TimeEntry(
      id: id,
      userId: map['userId'] as String? ?? '',
      userName: map['userName'] as String? ?? '',
      siteId: map['siteId'] as String? ?? '',
      siteName: map['siteName'] as String? ?? '',
      date: map['date'] as String? ?? '',
      clockInAt: clockInAt.toDate(),
      clockInLat: (map['clockInLat'] as num?)?.toDouble(),
      clockInLng: (map['clockInLng'] as num?)?.toDouble(),
      clockInVerified: map['clockInVerified'] as bool? ?? false,
      clockOutAt: map['clockOutAt'] is Timestamp
          ? (map['clockOutAt'] as Timestamp).toDate()
          : null,
      clockOutLat: (map['clockOutLat'] as num?)?.toDouble(),
      clockOutLng: (map['clockOutLng'] as num?)?.toDouble(),
      clockOutVerified: map['clockOutVerified'] as bool? ?? false,
      hours: (map['hours'] as num?)?.toDouble(),
      flagged: map['flagged'] as bool? ?? false,
      flagReason: map['flagReason'] as String?,
      auto: map['auto'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'siteId': siteId,
      'siteName': siteName,
      'date': date,
      'clockInAt': Timestamp.fromDate(clockInAt),
      'clockInLat': clockInLat,
      'clockInLng': clockInLng,
      'clockInVerified': clockInVerified,
      'clockOutAt': clockOutAt == null ? null : Timestamp.fromDate(clockOutAt!),
      'clockOutLat': clockOutLat,
      'clockOutLng': clockOutLng,
      'clockOutVerified': clockOutVerified,
      'hours': hours,
      'flagged': flagged,
      'flagReason': flagReason,
      'auto': auto,
    };
  }
}
