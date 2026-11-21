import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// One point on a clock-in's work route: the worker's GPS
/// position while clocked in. Lives in the
/// `timeEntries/{entryId}/breadcrumbs` subcollection.
///
/// Sampling: one point every 5 minutes from the foreground
/// tracking service while the entry is open (plus one per
/// ~15-minute background check as a fallback). Sampling stops
/// the moment the entry closes — never tracked off the clock.
/// Points are write-only history: never updated, never deleted
/// except with the whole entry (the server deletes short auto
/// entries and their breadcrumbs together).
class Breadcrumb {
  final String id;
  final double lat;
  final double lng;
  final DateTime at;

  const Breadcrumb({
    required this.id,
    required this.lat,
    required this.lng,
    required this.at,
  });

  factory Breadcrumb.fromFirestore(DocumentSnapshot doc) {
    return Breadcrumb.fromMap(
        doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  /// Parses one doc, or null when it is malformed (see
  /// [fromMap]). List callers should use this and drop the
  /// nulls instead of letting one bad doc break the whole
  /// stream or render invented data.
  static Breadcrumb? tryFromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>?;
    if (data == null) return null;
    return tryFromMap(doc.id, data);
  }

  /// Parses a whole snapshot, skipping malformed docs with a
  /// logged warning instead of failing the list or inventing
  /// data for them. Use this for the route-trail stream
  /// (`watchBreadcrumbs`).
  static List<Breadcrumb> parseDocs(Iterable<DocumentSnapshot> docs) {
    final out = <Breadcrumb>[];
    for (final doc in docs) {
      final point = tryFromFirestore(doc);
      if (point != null) out.add(point);
    }
    return out;
  }

  /// Like [fromMap], but returns null (with a logged warning)
  /// instead of throwing on a malformed doc.
  static Breadcrumb? tryFromMap(String id, Map<String, dynamic> map) {
    try {
      return Breadcrumb.fromMap(id, map);
    } on FormatException catch (e) {
      debugPrint('Skipping malformed breadcrumb $id: $e');
      return null;
    }
  }

  /// Throws [FormatException] when `lat`, `lng` or `at` is
  /// missing or the wrong type. A route point without a real
  /// position or time is not a point at all — it used to parse
  /// as 0,0 ("Null Island") and "now", which rendered a fake
  /// position/time as if the worker had been there. Callers
  /// that must not fail on one bad doc should use
  /// [tryFromMap]/[tryFromFirestore]/[parseDocs] instead.
  factory Breadcrumb.fromMap(String id, Map<String, dynamic> map) {
    final lat = map['lat'];
    final lng = map['lng'];
    final at = map['at'];
    if (lat is! num || lng is! num || at is! Timestamp) {
      throw FormatException(
          'Breadcrumb $id has no valid lat/lng/at '
          '(lat=$lat, lng=$lng, at=$at)');
    }
    return Breadcrumb(
      id: id,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      at: at.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'lat': lat,
      'lng': lng,
      'at': Timestamp.fromDate(at),
    };
  }
}
