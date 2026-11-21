import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/models/site_visit.dart';
import 'package:dyadespace/services/location_service.dart';
import 'package:dyadespace/services/visit_decision.dart';
import 'package:flutter_test/flutter_test.dart';

/// Unit tests for the visit dwell state machine: a visit only
/// counts after 10 continuous minutes inside one fence, and
/// closes after 2 consecutive checks outside it. Pure Dart
/// (distanceBetween is haversine math), no Firebase, no device.
/// 1 degree of latitude ≈ 111,320 m here, so 0.00054 ≈ 60 m.
void main() {
  // Fix ~11 m from siteA, ~1.1 km from siteB.
  const fixAtA = PositionFix(lat: 45.0000, lng: -73.0000);
  // Fix ~11 m from siteB.
  const fixAtB = PositionFix(lat: 45.0101, lng: -73.0000);
  // Fix outside every radius (~4.4 km north of siteA).
  const fixFar = PositionFix(lat: 45.0400, lng: -73.0000);

  const siteA = Site(id: 'a', name: 'Site A', lat: 45.0001, lng: -73.0000);
  const siteB = Site(id: 'b', name: 'Site B', lat: 45.0100, lng: -73.0000);
  const sites = [siteA, siteB];

  final t0 = DateTime(2026, 11, 16, 9, 0);

  SiteVisit openVisitAt(String siteId, String siteName, DateTime since) =>
      SiteVisit(
        id: 'v1',
        siteId: siteId,
        siteName: siteName,
        arrivedAt: since,
      );

  VisitDecision decide({
    PositionFix? fix,
    SiteVisit? openVisit,
    VisitCandidate? candidate,
    int streak = 0,
    required DateTime now,
  }) =>
      decideVisit(
        fix: fix,
        sites: sites,
        openVisit: openVisit,
        candidate: candidate,
        outsideStreak: streak,
        now: now,
      );

  test('no fix: nothing changes, candidate and streak kept', () {
    final candidate = VisitCandidate(siteId: 'a', since: t0);
    final d = decide(fix: null, candidate: candidate, streak: 1, now: t0);
    expect(d.action, VisitAction.none);
    expect(d.candidate, candidate);
    expect(d.outsideStreak, 1);
  });

  test('first check inside a site starts the dwell clock', () {
    final d = decide(fix: fixAtA, now: t0);
    expect(d.action, VisitAction.none);
    expect(d.candidate!.siteId, 'a');
    expect(d.candidate!.since, t0);
  });

  test('inside for 5 minutes: still dwelling, candidate kept', () {
    final candidate = VisitCandidate(siteId: 'a', since: t0);
    final d = decide(
        fix: fixAtA,
        candidate: candidate,
        now: t0.add(const Duration(minutes: 5)));
    expect(d.action, VisitAction.none);
    expect(d.candidate, candidate);
  });

  test('inside for 10 minutes: visit opens, arrival is the first-inside time',
      () {
    final candidate = VisitCandidate(siteId: 'a', since: t0);
    final d = decide(
        fix: fixAtA,
        candidate: candidate,
        now: t0.add(const Duration(minutes: 10)));
    expect(d.action, VisitAction.confirmVisit);
    expect(d.confirmSiteId, 'a');
    expect(d.confirmArrivedAt, t0);
    expect(d.candidate, isNull);
  });

  test('drive-by: inside once, then outside — no visit, candidate cleared', () {
    final candidate = VisitCandidate(siteId: 'a', since: t0);
    final d = decide(
        fix: fixFar,
        candidate: candidate,
        now: t0.add(const Duration(minutes: 5)));
    expect(d.action, VisitAction.none);
    expect(d.candidate, isNull);
  });

  test('leaving before 10 minutes and coming back restarts the dwell clock',
      () {
    // Inside at t0: dwell starts.
    final first = decide(fix: fixAtA, now: t0);
    expect(first.candidate!.since, t0);
    // Outside at t0+9: the candidate is cleared, no visit.
    final out = decide(
        fix: fixFar,
        candidate: first.candidate,
        now: t0.add(const Duration(minutes: 9)));
    expect(out.action, VisitAction.none);
    expect(out.candidate, isNull);
    // Back inside at t0+12: a FRESH dwell clock starts.
    final back = t0.add(const Duration(minutes: 12));
    final second = decide(fix: fixAtA, candidate: out.candidate, now: back);
    expect(second.candidate!.since, back);
    // 10 minutes after the RETURN the visit opens with the
    // return time, not the first time.
    final d2 = decide(
        fix: fixAtA,
        candidate: second.candidate,
        now: back.add(const Duration(minutes: 10)));
    expect(d2.action, VisitAction.confirmVisit);
    expect(d2.confirmArrivedAt, back);
  });

  test('open visit + still inside: nothing, streak reset', () {
    final d = decide(
      fix: fixAtA,
      openVisit: openVisitAt('a', 'Site A', t0),
      candidate: VisitCandidate(siteId: 'b', since: t0),
      streak: 1,
      now: t0.add(const Duration(minutes: 30)),
    );
    expect(d.action, VisitAction.none);
    expect(d.candidate, isNull);
    expect(d.outsideStreak, 0);
  });

  test('open visit + one check outside: still open (GPS flicker tolerated)',
      () {
    final d = decide(
      fix: fixFar,
      openVisit: openVisitAt('a', 'Site A', t0),
      now: t0.add(const Duration(minutes: 30)),
    );
    expect(d.action, VisitAction.none);
    expect(d.outsideStreak, 1);
  });

  test('open visit + two consecutive checks outside: visit closes', () {
    final d = decide(
      fix: fixFar,
      openVisit: openVisitAt('a', 'Site A', t0),
      streak: 1,
      now: t0.add(const Duration(minutes: 35)),
    );
    expect(d.action, VisitAction.closeVisit);
    expect(d.outsideStreak, 0);
  });

  test('open visit + one check inside another site: streak grows, dwell starts',
      () {
    final d = decide(
      fix: fixAtB,
      openVisit: openVisitAt('a', 'Site A', t0),
      now: t0.add(const Duration(minutes: 30)),
    );
    expect(d.action, VisitAction.none);
    expect(d.outsideStreak, 1);
    expect(d.candidate!.siteId, 'b');
    expect(d.candidate!.since, t0.add(const Duration(minutes: 30)));
  });

  test(
      'open visit + two checks inside another site: old visit closes, new dwell kept',
      () {
    final sinceB = t0.add(const Duration(minutes: 30));
    final d = decide(
      fix: fixAtB,
      openVisit: openVisitAt('a', 'Site A', t0),
      candidate: VisitCandidate(siteId: 'b', since: sinceB),
      streak: 1,
      now: t0.add(const Duration(minutes: 35)),
    );
    expect(d.action, VisitAction.closeVisit);
    expect(d.candidate!.siteId, 'b');
    expect(d.candidate!.since, sinceB);
  });

  test('overlapping fences: the nearer centre wins', () {
    // Two sites ~11 m apart, fix between them but closer to A.
    const siteNear = Site(id: 'n', name: 'Near', lat: 45.0001, lng: -73.0000);
    const siteFar = Site(id: 'f', name: 'Far', lat: 45.0002, lng: -73.0000);
    const fix = PositionFix(lat: 45.00005, lng: -73.0000);
    final d = decideVisit(
      fix: fix,
      sites: [siteNear, siteFar],
      openVisit: null,
      candidate: null,
      outsideStreak: 0,
      now: t0,
    );
    expect(d.candidate!.siteId, 'n');
  });

  test('no site with coordinates: nothing happens', () {
    const noCoords = Site(id: 'c', name: 'No GPS site');
    final d = decideVisit(
      fix: fixAtA,
      sites: [noCoords],
      openVisit: null,
      candidate: null,
      outsideStreak: 0,
      now: t0,
    );
    expect(d.action, VisitAction.none);
    expect(d.candidate, isNull);
  });
}
