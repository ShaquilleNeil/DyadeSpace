import 'package:cloud_firestore/cloud_firestore.dart';

/// A job site / building, e.g. "Maple Court" or "Harborview 1200".
class Site {
  /// Default clock-in fence radius (metres) for a site with no
  /// stored radius. Kept here (not in LocationService) so the
  /// model stays importable without the service.
  static const double defaultRadiusMeters = 100;

  final String id;
  final String name;
  final String address;

  /// Stored once by an admin/manager, from the site itself.
  /// Clock-ins are checked against this point (per-site radius,
  /// [effectiveRadiusMeters]). Null means no location set yet —
  /// clock-ins at the site are then recorded but cannot be
  /// verified.
  final double? lat;
  final double? lng;

  /// Clock-in fence radius in metres for this site. Null means
  /// "not set" — the site then uses the default
  /// ([effectiveRadiusMeters]). A site worker further than
  /// this from the site's coordinates cannot clock in (see
  /// LocationService.fenceCheck); clock-out is never blocked.
  /// Admins, managers and delivery drivers are never blocked
  /// by the fence — they clock in for the day instead, and
  /// the visit log records where they were.
  final double? radiusMeters;

  /// The fence radius that applies to this site: the stored
  /// value, or the 100 m default when none was saved.
  double get effectiveRadiusMeters => radiusMeters ?? defaultRadiusMeters;

  const Site({
    required this.id,
    required this.name,
    this.address = '',
    this.lat,
    this.lng,
    this.radiusMeters,
  });

  bool get hasLocation => lat != null && lng != null;

  factory Site.fromFirestore(DocumentSnapshot doc) {
    return Site.fromMap(doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory Site.fromMap(String id, Map<String, dynamic> map) {
    return Site(
      id: id,
      name: map['name'] as String? ?? '',
      address: map['address'] as String? ?? '',
      lat: (map['lat'] as num?)?.toDouble(),
      lng: (map['lng'] as num?)?.toDouble(),
      radiusMeters: (map['radiusMeters'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'address': address,
      'lat': lat,
      'lng': lng,
      'radiusMeters': radiusMeters,
    };
  }
}
