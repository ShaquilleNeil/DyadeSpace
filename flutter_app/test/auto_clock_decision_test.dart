import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/models/time_entry.dart';
import 'package:dyadespace/services/auto_clock_decision.dart';
import 'package:dyadespace/services/location_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for decideAutoClock (Part 2) — the pure arrival /
/// departure decision. No Firebase, no device.
void main() {
  // Fix ~11 m from siteA, ~1.1 km from siteB.
  const fixAtA = PositionFix(lat: 45.0000, lng: -73.0000);
  // Fix ~11 m from siteB.
  const fixAtB = PositionFix(lat: 45.0101, lng: -73.0000);
  // Fix ~4.4 km north of siteA — outside every radius.
  const fixFar = PositionFix(lat: 45.0400, lng: -73.0000);

  const siteA = Site(id: 'a', name: 'Site A', lat: 45.0001, lng: -73.0000);
  const siteB = Site(id: 'b', name: 'Site B', lat: 45.0100, lng: -73.0000);
  const siteNoCoords = Site(id: 'c', name: 'No GPS site');
  final sites = [siteA, siteB, siteNoCoords];

  TimeEntry openAt(String siteId, String siteName) => TimeEntry(
        id: 'entry-1',
        userId: 'worker-1',
        userName: 'Worker',
        siteId: siteId,
        siteName: siteName,
        date: '2026-11-15',
        clockInAt: DateTime(2026, 11, 15, 7, 0),
      );

  test('no fix: nothing happens, open entry left alone', () {
    final d = decideAutoClock(
        fix: null, sites: sites, openEntry: openAt('a', 'Site A'));
    expect(d.action, AutoClockAction.none);
    expect(d.site, isNull);
  });

  test('not clocked in + inside a radius on the FIRST check: dwell, no clock-in yet', () {
    final d = decideAutoClock(fix: fixAtA, sites: sites, openEntry: null);
    expect(d.action, AutoClockAction.none);
    expect(d.site, isNull);
    // The dwell is recorded for the next check.
    expect(d.insideStreak, 1);
    expect(d.insideSiteId, 'a');
  });

  test('not clocked in + inside a radius on the SECOND check: clock in there', () {
    final d = decideAutoClock(
        fix: fixAtA,
        sites: sites,
        openEntry: null,
        insideStreak: 1,
        insideSiteId: 'a');
    expect(d.action, AutoClockAction.clockIn);
    expect(d.site!.id, 'a');
  });

  test('not clocked in + inside a different site restarts the dwell', () {
    final d = decideAutoClock(
        fix: fixAtB,
        sites: sites,
        openEntry: null,
        insideStreak: 1,
        insideSiteId: 'a');
    expect(d.action, AutoClockAction.none);
    expect(d.insideStreak, 1);
    expect(d.insideSiteId, 'b');
  });

  test('not clocked in + outside every radius: nothing', () {
    final d = decideAutoClock(fix: fixFar, sites: sites, openEntry: null);
    expect(d.action, AutoClockAction.none);
  });

  test('clocked in at A + still inside A: nothing', () {
    final d = decideAutoClock(
        fix: fixAtA, sites: sites, openEntry: openAt('a', 'Site A'));
    expect(d.action, AutoClockAction.none);
  });

  test('clocked in at A + inside B: switch to B', () {
    final d = decideAutoClock(
        fix: fixAtB, sites: sites, openEntry: openAt('a', 'Site A'));
    expect(d.action, AutoClockAction.switchSite);
    expect(d.site!.id, 'b');
  });

  test('clocked in + outside every radius on the FIRST check: debounce, still clocked in', () {
    final d = decideAutoClock(
        fix: fixFar, sites: sites, openEntry: openAt('a', 'Site A'));
    expect(d.action, AutoClockAction.none);
    expect(d.outsideStreak, 1);
  });

  test('clocked in + outside every radius on the SECOND check: clock out', () {
    final d = decideAutoClock(
        fix: fixFar,
        sites: sites,
        openEntry: openAt('a', 'Site A'),
        outsideStreak: 1);
    expect(d.action, AutoClockAction.clockOut);
  });

  test('clocked in + one outside fix then back inside: streak resets, no clock-out', () {
    final first = decideAutoClock(
        fix: fixFar, sites: sites, openEntry: openAt('a', 'Site A'));
    expect(first.outsideStreak, 1);
    final back = decideAutoClock(
        fix: fixAtA,
        sites: sites,
        openEntry: openAt('a', 'Site A'),
        outsideStreak: first.outsideStreak);
    expect(back.action, AutoClockAction.none);
    expect(back.outsideStreak, 0);
  });

  test('no site with coordinates: nothing', () {
    final d =
        decideAutoClock(fix: fixAtA, sites: [siteNoCoords], openEntry: null);
    expect(d.action, AutoClockAction.none);
    final d2 = decideAutoClock(
        fix: fixAtA, sites: [], openEntry: openAt('a', 'Site A'));
    expect(d2.action, AutoClockAction.none);
  });

  test('day entry (no site) + inside a site: nothing — visits take over', () {
    final d =
        decideAutoClock(fix: fixAtA, sites: sites, openEntry: openAt('', ''));
    expect(d.action, AutoClockAction.none);
    expect(d.site, isNull);
  });

  test('day entry (no site) + inside another site: no switch', () {
    final d =
        decideAutoClock(fix: fixAtB, sites: sites, openEntry: openAt('', ''));
    expect(d.action, AutoClockAction.none);
  });

  test('day entry (no site) + outside every radius: no clock-out', () {
    final d =
        decideAutoClock(fix: fixFar, sites: sites, openEntry: openAt('', ''));
    expect(d.action, AutoClockAction.none);
  });
}
