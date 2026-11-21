import 'dart:convert';

import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/models/site_visit.dart';
import 'package:dyadespace/models/time_entry.dart';
import 'package:dyadespace/services/location_service.dart';
import 'package:dyadespace/services/time_entry_service.dart';
import 'package:dyadespace/services/visit_tracking_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Visit tracking service (Nov 21, 2026 audit fixes): a visit
/// closes at the LAST fix inside its fence (not the tick that
/// closes it), and a closed entry's visit is reconciled by
/// evaluate() instead of reading "Here now" forever. Fake
/// entries service — no Firestore, no device.
void main() {
  const fixAtA = PositionFix(lat: 45.0000, lng: -73.0000);
  const fixFar = PositionFix(lat: 45.0400, lng: -73.0000);
  const siteA = Site(id: 'a', name: 'Site A', lat: 45.0001, lng: -73.0000);
  const siteB = Site(id: 'b', name: 'Site B', lat: 45.0100, lng: -73.0000);
  const sites = [siteA, siteB];

  TimeEntry openEntry() => TimeEntry(
        id: 'e1',
        userId: 'u1',
        userName: 'Worker',
        siteId: 'a',
        siteName: 'Site A',
        date: '2026-11-16',
        clockInAt: DateTime.now().subtract(const Duration(hours: 2)),
      );

  group('visit close time', () {
    test('visit closes at the last-inside fix, not the closing tick',
        () async {
      SharedPreferences.setMockInitialValues({});
      final entries = _FakeEntries()
        ..entry = openEntry()
        ..openVisit = SiteVisit(
          id: 'v1',
          siteId: 'a',
          siteName: 'Site A',
          arrivedAt: DateTime.now().subtract(const Duration(minutes: 30)),
        );
      final service = VisitTrackingService(entries: entries);
      final beforeInside = DateTime.now();
      // Inside the open visit's fence: records last-inside.
      await service.evaluate(entryId: 'e1', fix: fixAtA, sites: sites);
      expect(entries.closed, isEmpty);
      final closeTickStart = DateTime.now();
      // First outside check: streak only, visit stays open.
      await service.evaluate(entryId: 'e1', fix: fixFar, sites: sites);
      expect(entries.closed, isEmpty);
      // Second consecutive outside check: the visit closes —
      // at the last-inside time, not now.
      await service.evaluate(entryId: 'e1', fix: fixFar, sites: sites);
      expect(entries.closed.length, 1);
      final leftAt = entries.closed.first.leftAt;
      expect(leftAt.millisecondsSinceEpoch,
          greaterThanOrEqualTo(beforeInside.millisecondsSinceEpoch));
      expect(leftAt.isBefore(closeTickStart), isTrue);
    });

    test('evaluate on a closed entry ends its visit at the clock-out time',
        () async {
      SharedPreferences.setMockInitialValues({});
      final clockOutAt = DateTime.now().subtract(const Duration(minutes: 5));
      final entries = _FakeEntries()
        ..entry = TimeEntry(
          id: 'e1',
          userId: 'u1',
          userName: 'Worker',
          siteId: 'a',
          siteName: 'Site A',
          date: '2026-11-16',
          clockInAt: DateTime.now().subtract(const Duration(hours: 2)),
          clockOutAt: clockOutAt,
        )
        ..openVisit = SiteVisit(
          id: 'v1',
          siteId: 'a',
          siteName: 'Site A',
          arrivedAt: DateTime.now().subtract(const Duration(minutes: 30)),
        );
      final service = VisitTrackingService(entries: entries);
      await service.evaluate(entryId: 'e1', fix: fixAtA, sites: sites);
      expect(entries.closed.length, 1);
      expect(entries.closed.first.leftAt, clockOutAt);
      // The in-progress state is dropped.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('visit_state_e1'), isNull);
    });

    test('a dwell met in a previous tick confirms the visit on this tick',
        () async {
      final since =
          DateTime.now().subtract(const Duration(minutes: 11));
      SharedPreferences.setMockInitialValues({
        'visit_state_e1': jsonEncode({
          'siteId': 'a',
          'sinceMs': since.millisecondsSinceEpoch,
          'streak': 0,
          'updatedMs': since.millisecondsSinceEpoch,
        }),
      });
      final entries = _FakeEntries()..entry = openEntry();
      final service = VisitTrackingService(entries: entries);
      await service.evaluate(entryId: 'e1', fix: fixAtA, sites: sites);
      expect(entries.created.length, 1);
      // Millisecond precision: the candidate time round-trips
      // through SharedPreferences as epoch milliseconds.
      expect(entries.created.first.arrivedAt.millisecondsSinceEpoch,
          since.millisecondsSinceEpoch);
    });
  });
}

class _FakeEntries extends TimeEntryService {
  TimeEntry? entry;
  SiteVisit? openVisit;
  final List<({SiteVisit visit, DateTime leftAt})> closed = [];
  final List<SiteVisit> created = [];

  @override
  Future<TimeEntry?> entryById(String entryId) async => entry;

  @override
  Future<SiteVisit?> openVisitFor(String entryId) async => openVisit;

  @override
  Future<String> createVisit({
    required String entryId,
    required String siteId,
    required String siteName,
    required DateTime arrivedAt,
  }) async {
    final visit = SiteVisit(
      id: 'v${created.length + 1}',
      siteId: siteId,
      siteName: siteName,
      arrivedAt: arrivedAt,
    );
    created.add(visit);
    openVisit = visit;
    return visit.id;
  }

  @override
  Future<void> closeVisit(
      String entryId, SiteVisit visit, DateTime leftAt) async {
    closed.add((visit: visit, leftAt: leftAt));
    if (openVisit?.id == visit.id) openVisit = null;
  }

  @override
  Future<void> closeOpenVisitForEntry(String entryId, DateTime at) async {
    final visit = openVisit;
    if (visit != null) await closeVisit(entryId, visit, at);
  }
}
