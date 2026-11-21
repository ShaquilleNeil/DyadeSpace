import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the clock-in fence (Part 1): per-site radius
/// + block outside it. Pure Dart (distanceBetween is haversine
/// math, no platform channel), so no Firebase or device needed.
/// 1 degree of latitude ≈ 111,320 m here, so 0.00054 ≈ 60 m,
/// 0.00036 ≈ 40 m, 0.00108 ≈ 120 m.
void main() {
  final location = LocationService();

  // Fix ~11 m from siteNear.
  const fix = PositionFix(lat: 45.0000, lng: -73.0000);
  // ~60 m north of the fix.
  const fix60 = PositionFix(lat: 45.00054, lng: -73.0000);
  // ~120 m north of the fix.
  const fix120 = PositionFix(lat: 45.00108, lng: -73.0000);

  const siteDefault = Site(
    id: 'default',
    name: 'Default radius site',
    lat: 45.0000,
    lng: -73.0000,
  );
  const siteSmall = Site(
    id: 'small',
    name: 'Small radius site',
    lat: 45.0000,
    lng: -73.0000,
    radiusMeters: 50,
  );
  const siteLarge = Site(
    id: 'large',
    name: 'Large radius site',
    lat: 45.0000,
    lng: -73.0000,
    radiusMeters: 200,
  );

  test('default radius is 100 m when no radius is stored', () {
    expect(siteDefault.effectiveRadiusMeters, 100);
    expect(Site.defaultRadiusMeters, 100);
    expect(siteSmall.effectiveRadiusMeters, 50);
    expect(siteLarge.effectiveRadiusMeters, 200);
  });

  test('nearestSite uses the site\'s own radius', () {
    // 60 m away: inside the 100 m default and the 200 m site,
    // outside the 50 m site.
    expect(location.nearestSite(fix60, [siteDefault])!.withinRadius,
        isTrue);
    expect(location.nearestSite(fix60, [siteSmall])!.withinRadius,
        isFalse);
    expect(location.nearestSite(fix60, [siteLarge])!.withinRadius,
        isTrue);
    // 120 m away: outside the 100 m default, inside 200 m.
    expect(location.nearestSite(fix120, [siteDefault])!.withinRadius,
        isFalse);
    expect(location.nearestSite(fix120, [siteLarge])!.withinRadius,
        isTrue);
  });

  test('verifyFix uses the site\'s own radius', () {
    expect(location.verifyFix(fix60, siteDefault).verified, isTrue);
    final small = location.verifyFix(fix60, siteSmall);
    expect(small.verified, isFalse);
    expect(small.flagReason, 'outside-radius');
    expect(location.verifyFix(fix120, siteLarge).verified, isTrue);
  });

  test('fenceCheck blocks only a fix outside the radius', () {
    final blocked = location.nearestSite(fix120, [siteDefault])!;
    final check = LocationService.fenceCheck(fix120, blocked);
    expect(check.blocked, isTrue);
    expect(check.distanceMeters, greaterThan(100));
    expect(check.radiusMeters, 100);
  });

  test('fenceCheck allows a fix inside the radius', () {
    final inside = location.nearestSite(fix, [siteDefault])!;
    expect(LocationService.fenceCheck(fix, inside).blocked, isFalse);
    final insideSmall =
        location.nearestSite(fix, [siteSmall])!;
    expect(LocationService.fenceCheck(fix, insideSmall).blocked,
        isFalse);
  });

  test('fenceCheck never blocks without a fix', () {
    final nearest = location.nearestSite(fix, [siteDefault])!;
    expect(LocationService.fenceCheck(null, nearest).blocked, isFalse);
  });

  test('fenceCheck never blocks when no site has coordinates', () {
    expect(LocationService.fenceCheck(fix, null).blocked, isFalse);
  });

  test('fenceCheck never blocks a "Not now" tap (no fix, no nearest)',
      () {
    expect(LocationService.fenceCheck(null, null).blocked, isFalse);
  });
}
