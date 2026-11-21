import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dyadespace/models/app_user.dart';
import 'package:dyadespace/models/site.dart';
import 'package:dyadespace/models/time_entry.dart';
import 'package:dyadespace/services/auto_clock_service.dart';
import 'package:dyadespace/services/location_service.dart';
import 'package:dyadespace/services/time_entry_service.dart';
import 'package:dyadespace/services/visit_tracking_service.dart';
import 'package:dyadespace/widgets/member_tile.dart';

/// Duplicate clock-in history (Nov 16, 2026): every history
/// entry on Alex's profile rendered TWICE — same site,
/// same times, same Auto/Verified pills — including 0-minute
/// entries (16:53–16:53). Root cause, from the real code: the
/// create path is read-then-write with no atomicity
/// (TimeEntryService.clockIn / clockInDay read the open
/// entries, then write a batch), and the auto check has three
/// overlapping triggers with no in-flight guard (Workmanager
/// tick, home-shell onResume, home-shell startup check). Two
/// overlapping calls both read "no open entry" and both
/// create a doc; a later clock-in closes both twins at once
/// (close-all), which is why the pairs show IDENTICAL
/// clock-out times. The fix: serialize creation in this
/// isolate (a mutex around read+write), guard the auto check
/// against re-entry, close ALL open entries on clock-out
/// (heals pre-fix twins), and dedupe identical rows
/// defensively in the streams so already-duplicated history
/// renders once.

const _me = AppUser(
  id: 'u1',
  name: 'Alex Morgan',
  email: 'alex@example.com',
  role: UserRole.admin,
);

const _site = Site(
  id: 's1',
  name: 'St Antoine',
  address: '3035 Saint-Antoine',
  lat: 45.0400,
  lng: -73.0000,
  radiusMeters: 100,
);

TimeEntry _entry({
  required String id,
  required DateTime clockInAt,
  DateTime? clockOutAt,
  String siteId = 's1',
  String siteName = 'St Antoine',
  bool auto = false,
}) =>
    TimeEntry(
      id: id,
      userId: 'u1',
      userName: 'Alex Morgan',
      siteId: siteId,
      siteName: siteName,
      date: '2026-11-16',
      clockInAt: clockInAt,
      clockOutAt: clockOutAt,
      auto: auto,
    );

/// A fix that only resolves when the test releases it, so two
/// concurrent clockIn calls are both in flight at once — the
/// exact overlap that used to double-create.
class _ControlledLocation extends LocationService {
  final Completer<PositionFix?> gate = Completer<PositionFix?>();

  @override
  Future<PositionFix?> currentFix() => gate.future;
}

/// Fake entries service for the auto-check guard test: its
/// clockIn waits 50 ms between the (fake) read and the create,
/// the way a real Firestore round-trip separates them — so
/// without the guard, two overlapping checks both create.
class _DelayedFakeEntries extends TimeEntryService {
  final List<TimeEntry> created = [];
  TimeEntry? openEntry;

  @override
  Future<TimeEntry?> openEntryFor(String uid) async => openEntry;

  @override
  Future<String> clockIn({
    required AppUser user,
    required Site site,
    bool skipLocation = false,
    PositionFix? fix,
    bool auto = false,
    PositionFix? closeFix,
  }) async {
    if (openEntry != null && openEntry!.siteId == site.id) {
      return openEntry!.id;
    }
    await Future.delayed(const Duration(milliseconds: 50));
    final entry = TimeEntry(
      id: 'e${created.length + 1}',
      userId: user.id,
      userName: user.name,
      siteId: site.id,
      siteName: site.name,
      date: '2026-11-16',
      clockInAt: DateTime.now(),
      auto: auto,
    );
    created.add(entry);
    openEntry = entry;
    return entry.id;
  }

  @override
  Future<void> addBreadcrumb(String entryId, PositionFix fix) async {}

  @override
  Future<void> clockOut(TimeEntry entry, {PositionFix? fix}) async {
    openEntry = null;
  }
}

class _NoopVisits extends VisitTrackingService {
  @override
  Future<void> evaluate({
    required String entryId,
    required PositionFix fix,
    required List<Site> sites,
  }) async {}
}

class _FixedLocation extends LocationService {
  final PositionFix fix;
  _FixedLocation(this.fix);

  @override
  Future<PositionFix?> currentFix() async => fix;
}

void main() {
  group('dedupeTimeEntries', () {
    test('exact duplicates (different ids) render once', () {
      final a = _entry(
        id: 'a',
        clockInAt: DateTime(2026, 11, 16, 14, 11),
        clockOutAt: DateTime(2026, 11, 16, 14, 41),
        auto: true,
      );
      final b = _entry(
        id: 'b',
        clockInAt: DateTime(2026, 11, 16, 14, 11),
        clockOutAt: DateTime(2026, 11, 16, 14, 41),
        auto: true,
      );
      final out = dedupeTimeEntries([a, b]);
      expect(out.length, 1);
      expect(out.first.id, 'a');
    });

    test('same minute, different clock-out minute stays twice', () {
      final a = _entry(
        id: 'a',
        clockInAt: DateTime(2026, 11, 16, 14, 11),
        clockOutAt: DateTime(2026, 11, 16, 14, 41),
      );
      final b = _entry(
        id: 'b',
        clockInAt: DateTime(2026, 11, 16, 14, 11),
        clockOutAt: DateTime(2026, 11, 16, 14, 43),
      );
      expect(dedupeTimeEntries([a, b]).length, 2);
    });

    test('same minute, different seconds stay separate (full precision)', () {
      final a = _entry(
        id: 'a',
        clockInAt: DateTime(2026, 11, 16, 14, 11, 5),
        clockOutAt: DateTime(2026, 11, 16, 14, 41),
      );
      final b = _entry(
        id: 'b',
        clockInAt: DateTime(2026, 11, 16, 14, 11, 35),
        clockOutAt: DateTime(2026, 11, 16, 14, 41),
      );
      expect(dedupeTimeEntries([a, b]).length, 2);
    });

    test('open twins (no clock-out yet) collapse to one', () {
      final a = _entry(id: 'a', clockInAt: DateTime(2026, 11, 16, 9, 0));
      final b = _entry(id: 'b', clockInAt: DateTime(2026, 11, 16, 9, 0));
      expect(dedupeTimeEntries([a, b]).length, 1);
    });

    test('different sites stay separate', () {
      final a = _entry(
        id: 'a',
        clockInAt: DateTime(2026, 11, 16, 14, 11),
        clockOutAt: DateTime(2026, 11, 16, 14, 41),
      );
      final b = _entry(
        id: 'b',
        clockInAt: DateTime(2026, 11, 16, 14, 11),
        clockOutAt: DateTime(2026, 11, 16, 14, 41),
        siteId: 's2',
        siteName: 'Maple Court',
      );
      expect(dedupeTimeEntries([a, b]).length, 2);
    });

    test('0-minute twins collapse to one', () {
      final a = _entry(
        id: 'a',
        clockInAt: DateTime(2026, 11, 16, 16, 53),
        clockOutAt: DateTime(2026, 11, 16, 16, 53),
        auto: true,
      );
      final b = _entry(
        id: 'b',
        clockInAt: DateTime(2026, 11, 16, 16, 53),
        clockOutAt: DateTime(2026, 11, 16, 16, 53),
        auto: true,
      );
      expect(dedupeTimeEntries([a, b]).length, 1);
    });
  });

  group('concurrent clockIn (real service, fake Firestore)', () {
    test('two concurrent clockIn calls create one entry', () async {
      final fake = FakeFirebaseFirestore();
      final location = _ControlledLocation();
      final service =
          TimeEntryService(db: fake, location: location);
      final first = service.clockIn(user: _me, site: _site);
      final second = service.clockIn(user: _me, site: _site);
      location.gate.complete(const PositionFix(lat: 45.6, lng: -73.6));
      final ids = await Future.wait([first, second]);
      expect(ids[0], ids[1]);
      final snap = await fake.collection('timeEntries').get();
      expect(snap.docs.length, 1);
    });

    test('two concurrent clockInDay calls create one entry', () async {
      final fake = FakeFirebaseFirestore();
      final location = _ControlledLocation();
      final service =
          TimeEntryService(db: fake, location: location);
      final first = service.clockInDay(user: _me);
      final second = service.clockInDay(user: _me);
      location.gate.complete(const PositionFix(lat: 45.6, lng: -73.6));
      final ids = await Future.wait([first, second]);
      expect(ids[0], ids[1]);
      final snap = await fake.collection('timeEntries').get();
      expect(snap.docs.length, 1);
    });

    test('clockOut closes every open entry (pre-fix twins)', () async {
      final fake = FakeFirebaseFirestore();
      final service = TimeEntryService(db: fake);
      final col = fake.collection('timeEntries');
      final a = await col.add(
        _entry(
          id: 'ignored',
          clockInAt: DateTime(2026, 11, 16, 14, 11),
        ).toMap()
          ..['userId'] = 'u1',
      );
      final b = await col.add(
        _entry(
          id: 'ignored',
          clockInAt: DateTime(2026, 11, 16, 14, 11),
        ).toMap()
          ..['userId'] = 'u1',
      );
      final entryA = TimeEntry.fromFirestore(await a.get());
      await service.clockOut(entryA);
      final afterA = await a.get();
      final afterB = await b.get();
      expect(afterA.data()?['clockOutAt'], isNotNull);
      expect(afterB.data()?['clockOutAt'], isNotNull);
      expect(
        (afterA.data()?['clockOutAt'] as Timestamp).toDate(),
        (afterB.data()?['clockOutAt'] as Timestamp).toDate(),
      );
    });

    test('clockOut takes a GPS fix and stores it (manual clock-out is verifiable)', () async {
      final fake = FakeFirebaseFirestore();
      final service = TimeEntryService(
        db: fake,
        location: _FixedLocation(const PositionFix(lat: 45.05, lng: -73.01)),
      );
      final col = fake.collection('timeEntries');
      final doc = await col.add(
        _entry(
          id: 'ignored',
          clockInAt: DateTime(2026, 11, 16, 14, 11),
        ).toMap()
          ..['userId'] = 'u1',
      );
      final entry = TimeEntry.fromFirestore(await doc.get());
      await service.clockOut(entry);
      final after = await doc.get();
      expect(after.data()?['clockOutAt'], isNotNull);
      expect(after.data()?['clockOutLat'], 45.05);
      expect(after.data()?['clockOutLng'], -73.01);
    });

    test('two concurrent clockOut calls close once; the second is a no-op', () async {
      final fake = FakeFirebaseFirestore();
      final service = TimeEntryService(
        db: fake,
        location: _FixedLocation(const PositionFix(lat: 45.05, lng: -73.01)),
      );
      final col = fake.collection('timeEntries');
      final doc = await col.add(
        _entry(
          id: 'ignored',
          clockInAt: DateTime(2026, 11, 16, 14, 11),
        ).toMap()
          ..['userId'] = 'u1',
      );
      final entry = TimeEntry.fromFirestore(await doc.get());
      // Both complete without throwing (no "clock out failed"
      // from a batch touching an already-closed entry).
      await Future.wait([service.clockOut(entry), service.clockOut(entry)]);
      final after = await doc.get();
      expect(after.data()?['clockOutAt'], isNotNull);
    });

    test('clockOut of an already-closed entry is a no-op', () async {
      final fake = FakeFirebaseFirestore();
      final service = TimeEntryService(
        db: fake,
        location: _FixedLocation(const PositionFix(lat: 45.05, lng: -73.01)),
      );
      final col = fake.collection('timeEntries');
      final doc = await col.add(
        _entry(
          id: 'ignored',
          clockInAt: DateTime(2026, 11, 16, 14, 11),
          clockOutAt: DateTime(2026, 11, 16, 15, 0),
        ).toMap()
          ..['userId'] = 'u1',
      );
      final entry = TimeEntry.fromFirestore(await doc.get());
      await service.clockOut(entry);
      final after = await doc.get();
      expect(
        (after.data()?['clockOutAt'] as Timestamp).toDate(),
        DateTime(2026, 11, 16, 15, 0),
      );
    });

    test('clockIn writes queuedAt (offline queue proof for the rules)', () async {
      final fake = FakeFirebaseFirestore();
      final location = _ControlledLocation();
      final service = TimeEntryService(db: fake, location: location);
      final future = service.clockIn(user: _me, site: _site);
      location.gate.complete(const PositionFix(lat: 45.6, lng: -73.6));
      final id = await future;
      final snap = await fake.collection('timeEntries').doc(id).get();
      final data = snap.data()!;
      expect(data['queuedAt'], isNotNull);
      expect(
        (data['queuedAt'] as Timestamp).toDate(),
        (data['clockInAt'] as Timestamp).toDate(),
      );
    });

    test('two concurrent createVisit calls create one open visit', () async {
      final fake = FakeFirebaseFirestore();
      final service = TimeEntryService(db: fake);
      final col = fake.collection('timeEntries');
      final doc = await col.add(
        _entry(
          id: 'ignored',
          clockInAt: DateTime(2026, 11, 16, 9, 0),
        ).toMap()
          ..['userId'] = 'u1',
      );
      final entryId = doc.id;
      final ids = await Future.wait([
        service.createVisit(
          entryId: entryId,
          siteId: 's1',
          siteName: 'St Antoine',
          arrivedAt: DateTime(2026, 11, 16, 9, 0),
        ),
        service.createVisit(
          entryId: entryId,
          siteId: 's1',
          siteName: 'St Antoine',
          arrivedAt: DateTime(2026, 11, 16, 9, 0),
        ),
      ]);
      expect(ids[0], ids[1]);
      final visits =
          await col.doc(entryId).collection('siteVisits').get();
      expect(visits.docs.length, 1);
    });

    test('the history stream dedupes twin docs', () async {
      final fake = FakeFirebaseFirestore();
      final service = TimeEntryService(db: fake);
      final col = fake.collection('timeEntries');
      for (var i = 0; i < 2; i++) {
        await col.add({
          'userId': 'u1',
          'userName': 'Alex Morgan',
          'siteId': 's1',
          'siteName': 'St Antoine',
          'date': '2026-11-16',
          'clockInAt': Timestamp.fromDate(DateTime(2026, 11, 16, 14, 11)),
          'clockOutAt': Timestamp.fromDate(DateTime(2026, 11, 16, 14, 41)),
          'clockInVerified': false,
          'flagged': false,
          'auto': true,
        });
      }
      final list = await service.watchEntriesForUser('u1').first;
      expect(list.length, 1);
    });
  });

  group('auto clock-in guard', () {
    test('two concurrent checks create one entry', () async {
      SharedPreferences.setMockInitialValues({
        'auto_clock_in_enabled': true,
        'auto_clock_uid': 'u1',
      });
      final fake = FakeFirebaseFirestore();
      await fake.collection('users').doc('u1').set({
        'name': 'Alex Morgan',
        'email': 'alex@example.com',
        'role': 'admin',
        'active': true,
      });
      await fake.collection('sites').doc('s1').set({
        'name': 'St Antoine',
        'address': '3035 Saint-Antoine',
        'lat': 45.0400,
        'lng': -73.0000,
        'radiusMeters': 100,
      });
      final entries = _DelayedFakeEntries();
      final service = AutoClockService(
        db: fake,
        location: _FixedLocation(
          const PositionFix(lat: 45.6, lng: -73.6),
        ),
        entries: entries,
        visits: _NoopVisits(),
      );
      // Dwell: the first check only records being inside the
      // fence — no entry yet.
      expect(await service.checkAndUpdate(), isFalse);
      expect(entries.created, isEmpty);
      // The second check (dwell met) clocks in — and two
      // concurrent checks still create only one entry.
      final results = await Future.wait([
        service.checkAndUpdate(),
        service.checkAndUpdate(),
      ]);
      expect(entries.created.length, 1);
      expect(results, [true, false]);
    });
  });

  group('profile photo fallback', () {
    testWidgets('a photo URL that fails to load shows initials',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: RoleAvatar(
              name: 'Alex Morgan',
              role: UserRole.admin,
              size: 64,
              photoUrl: 'https://invalid.example/photo.jpg',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('SN'), findsOneWidget);
    });
  });
}
