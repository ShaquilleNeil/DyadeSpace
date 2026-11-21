import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for LocationService.nearestSite — the site picker
/// behind the one-tap clock-in button. Pure Dart (distanceBetween
/// is haversine math, no platform channel), so no Firebase or
/// device is needed.
void main() {
  final location = LocationService();

  // Fix near Harborview 1200: ~11 m away, ~1.1 km from Maple Court.
  const fix = PositionFix(lat: 45.0000, lng: -73.0000);
  const siteNear = Site(
    id: 'harborview-1200',
    name: 'Harborview 1200',
    lat: 45.0001,
    lng: -73.0000,
  );
  const siteFar = Site(
    id: 'maple-court',
    name: 'Maple Court',
    lat: 45.0100,
    lng: -73.0000,
  );
  const siteNoCoords = Site(id: 'no-gps', name: 'No GPS site');

  test('nearest site within radius wins, regardless of list order', () {
    final result =
        location.nearestSite(fix, [siteFar, siteNoCoords, siteNear]);
    expect(result, isNotNull);
    expect(result!.site.id, 'harborview-1200');
    expect(result.withinRadius, isTrue);
    expect(result.distanceMeters, greaterThan(0));
    expect(result.distanceMeters, lessThan(100));
  });

  test('none in radius returns the nearest anyway, flagged by distance',
      () {
    // Fix ~3.3 km north of Maple Court, ~4.4 km north of Harborview.
    const farFix = PositionFix(lat: 45.0400, lng: -73.0000);
    final result =
        location.nearestSite(farFix, [siteNear, siteFar, siteNoCoords]);
    expect(result, isNotNull);
    expect(result!.site.id, 'maple-court');
    expect(result.withinRadius, isFalse);
    expect(result.distanceMeters, greaterThan(100));
  });

  test('sites without coordinates are ignored', () {
    expect(location.nearestSite(fix, [siteNoCoords]), isNull);
    expect(location.nearestSite(fix, []), isNull);
  });

  test('no fix returns null', () {
    expect(location.nearestSite(null, [siteNear, siteFar]), isNull);
  });
}
