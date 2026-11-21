import 'package:geolocator/geolocator.dart';

import '../models/site.dart';

/// One GPS fix, captured at a single tap. Null when the fix
/// could not be taken (services off, permission denied, or the
/// fix timed out) — the caller clocks in anyway and flags the
/// entry instead of blocking the worker.
class PositionFix {
  final double lat;
  final double lng;
  const PositionFix({required this.lat, required this.lng});
}

/// GPS for clock-in / clock-out and for storing a site's
/// location. Every method takes ONE fix and returns: no
/// streams, no background tracking, no position history —
/// except the opt-in auto clock-in (AutoClockService) and the
/// while-clocked-in route trail (RouteTrackingService), which
/// are separate services with their own consent.
///
/// Each site has its own fence radius ([Site.radiusMeters],
/// 100 m by default). Indoor GPS is unreliable (10–30 m
/// outdoors, worse inside a building). The fence BLOCKS a
/// site worker's manual clock-in (the worker must move
/// inside the fence) — but never blocks a clock-out, and
/// never blocks when there is no fix or no site with stored
/// coordinates: those entries are allowed and flagged for a
/// manager's review instead. Admins, managers and delivery
/// drivers clock in for the DAY instead (see
/// TimeEntryService.clockInDay): the fence never blocks
/// them, and the visit log records where they actually were.
class LocationService {
  /// Default fence radius (metres) — see [Site.defaultRadiusMeters].
  static const double defaultSiteRadiusMeters = Site.defaultRadiusMeters;

  /// One fix, or null when it cannot be taken. Asks for
  /// permission on first use; a denial returns null instead
  /// of throwing, so the caller can clock in flagged.
  Future<PositionFix?> currentFix() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return null;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      return PositionFix(lat: pos.latitude, lng: pos.longitude);
    } catch (_) {
      return null;
    }
  }

  /// The site nearest to [fix], with its distance in metres — or
  /// null when there is no fix or no site has stored coordinates.
  /// Sites without coordinates are ignored. The nearest site wins
  /// even outside its radius: [withinRadius] is false then, and
  /// the clock-in button blocks the tap for a site worker (see
  /// [fenceCheck]); admins, managers and delivery drivers
  /// instead start a day entry with no site.
  ({Site site, double distanceMeters, bool withinRadius})? nearestSite(
      PositionFix? fix, Iterable<Site> sites) {
    if (fix == null) return null;
    Site? nearest;
    var nearestDistance = double.infinity;
    for (final site in sites) {
      if (!site.hasLocation) continue;
      final distance = Geolocator.distanceBetween(
        fix.lat,
        fix.lng,
        site.lat!,
        site.lng!,
      );
      if (distance < nearestDistance) {
        nearestDistance = distance;
        nearest = site;
      }
    }
    if (nearest == null) return null;
    return (
      site: nearest,
      distanceMeters: nearestDistance,
      withinRadius: nearestDistance <= nearest.effectiveRadiusMeters,
    );
  }

  /// Pure fence decision for a site worker's manual clock-in
  /// tap (unit-tested in test/clock_in_fence_test.dart).
  /// Blocked ONLY when a fix exists AND the nearest site has
  /// coordinates AND the fix is outside that site's radius.
  /// Every fallback — no fix, no site with coordinates,
  /// consent "Not now" — is never blocked: the entry is
  /// allowed and flagged for review instead. Clock-out is
  /// never blocked (not this function's job). Admins,
  /// managers and delivery drivers never call this: they
  /// clock in for the day, fence or no fence.
  static ({
    bool blocked,
    double? distanceMeters,
    double? radiusMeters,
  }) fenceCheck(
    PositionFix? fix,
    ({Site site, double distanceMeters, bool withinRadius})? nearest,
  ) {
    if (fix == null || nearest == null || nearest.withinRadius) {
      return (
        blocked: false,
        distanceMeters: nearest?.distanceMeters,
        radiusMeters: nearest?.site.effectiveRadiusMeters,
      );
    }
    return (
      blocked: true,
      distanceMeters: nearest.distanceMeters,
      radiusMeters: nearest.site.effectiveRadiusMeters,
    );
  }

  /// Checks [fix] against a site's stored coordinates, using
  /// that site's own radius (100 m default).
  /// Returns a (verified, flagReason) pair — flagReason is a
  /// code for AppStrings.flagReasonLabel, null when verified.
  ({bool verified, String? flagReason}) verifyFix(
      PositionFix? fix, Site? site) {
    if (fix == null) {
      return (verified: false, flagReason: 'no-location');
    }
    if (site == null || !site.hasLocation) {
      return (verified: false, flagReason: 'no-site-location');
    }
    final distance = Geolocator.distanceBetween(
      fix.lat,
      fix.lng,
      site.lat!,
      site.lng!,
    );
    if (distance <= site.effectiveRadiusMeters) {
      return (verified: true, flagReason: null);
    }
    return (verified: false, flagReason: 'outside-radius');
  }
}
