import 'package:cloud_firestore/cloud_firestore.dart';

/// One visit to a site during a clocked-in day: the worker
/// arrived at the site and (once they left) left it. Lives in
/// the `timeEntries/{entryId}/siteVisits` subcollection.
///
/// A visit is only written once it is CONFIRMED: the worker
/// was inside the site's fence for 10 continuous minutes
/// (see VisitDecision / VisitTrackingService). A drive-by —
/// inside for less than 10 minutes — never creates a doc, so
/// there is nothing to clean up. `leftAt` is null while the
/// worker is still there ("Here now"); `durationMinutes` is
/// written when the visit closes. Visits are immutable once
/// closed: the client only ever creates one and writes
/// `leftAt` + `durationMinutes` on the close — the rules
/// enforce that, same pattern as time entries.
class SiteVisit {
  final String id;
  final String siteId;
  final String siteName;
  final DateTime arrivedAt;
  final DateTime? leftAt;

  /// Whole minutes between arrival and departure, written at
  /// close. Null while the visit is still open.
  final int? durationMinutes;

  const SiteVisit({
    required this.id,
    required this.siteId,
    required this.siteName,
    required this.arrivedAt,
    this.leftAt,
    this.durationMinutes,
  });

  bool get isOpen => leftAt == null;

  /// Minutes so far for an open visit (live value, not stored).
  int get minutesSoFar {
    final end = leftAt ?? DateTime.now();
    final minutes = end.difference(arrivedAt).inMinutes;
    return minutes < 0 ? 0 : minutes;
  }

  /// Duration to display: the stored value when the visit is
  /// closed, otherwise the live time since arrival.
  int get effectiveMinutes => durationMinutes ?? minutesSoFar;

  factory SiteVisit.fromFirestore(DocumentSnapshot doc) {
    return SiteVisit.fromMap(doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory SiteVisit.fromMap(String id, Map<String, dynamic> map) {
    return SiteVisit(
      id: id,
      siteId: map['siteId'] as String? ?? '',
      siteName: map['siteName'] as String? ?? '',
      arrivedAt: map['arrivedAt'] is Timestamp
          ? (map['arrivedAt'] as Timestamp).toDate()
          : DateTime.now(),
      leftAt: map['leftAt'] is Timestamp
          ? (map['leftAt'] as Timestamp).toDate()
          : null,
      durationMinutes: (map['durationMinutes'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'siteId': siteId,
      'siteName': siteName,
      'arrivedAt': Timestamp.fromDate(arrivedAt),
      'leftAt': leftAt == null ? null : Timestamp.fromDate(leftAt!),
      'durationMinutes': durationMinutes,
    };
  }
}
