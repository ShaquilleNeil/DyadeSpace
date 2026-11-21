import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';
import '../models/breadcrumb.dart';
import '../models/site.dart';
import '../models/site_visit.dart';
import '../models/time_entry.dart';
import '../utils/week_hours.dart';
import 'location_service.dart';

/// Collapse exact-duplicate rows to one (same worker, site,
/// clock-in, clock-out and auto flag at FULL precision,
/// keeping the first). Defensive only: clockIn / clockInDay
/// serialize creation now (see the create mutex below), so new
/// duplicates should not be created — but history written
/// before the fix (Nov 16, 2026: every entry appeared twice)
/// renders once instead of twice, and week totals stop
/// double-counting it. Full millisecond precision on purpose:
/// minute precision collapsed genuinely distinct entries
/// (two short entries in the same minute read identically in
/// the UI but are different work); only rows with identical
/// timestamps to the millisecond are twins of one tap.
List<TimeEntry> dedupeTimeEntries(List<TimeEntry> entries) {
  final seen = <String>{};
  final out = <TimeEntry>[];
  for (final e in entries) {
    final clockOut =
        e.clockOutAt == null ? 'open' : '${e.clockOutAt!.millisecondsSinceEpoch}';
    final key = '${e.userId}|${e.siteId}|'
        '${e.clockInAt.millisecondsSinceEpoch}|'
        '$clockOut|${e.auto}';
    if (seen.add(key)) out.add(e);
  }
  return out;
}

/// All Firestore access for clock-in / hours entries.
///
/// Queries stay simple on purpose (spec): filtering and
/// sorting are done in Dart, so no composite indexes are
/// needed at this crew size. The rules enforce the rest:
/// a worker may only create/close their OWN entries, and only
/// close an entry that is still open; admins/managers may
/// read and correct any entry.
class TimeEntryService {
  // The default database is resolved lazily (not in the
  // constructor) so a test subclass can override clockIn /
  // clockOut without ever touching FirebaseFirestore.instance,
  // which throws when Firebase is not initialized.
  final FirebaseFirestore? _dbOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  final LocationService _location;

  TimeEntryService({FirebaseFirestore? db, LocationService? location})
      : _dbOverride = db,
        _location = location ?? LocationService();

  CollectionReference<Map<String, dynamic>> get _entries =>
      _db.collection('timeEntries');

  /// Serializes entry creation in this isolate. clockIn /
  /// clockInDay are read-then-write (read the open entries,
  /// then write a batch) — and the button tap, the auto check
  /// (startup + resume + background tick in the main isolate)
  /// and the site switch can all run them at once. Two
  /// overlapping calls both read "no open entry" and both
  /// create a doc — that is how Nov 16's history ended up
  /// with every entry twice. A plain Future-chain mutex: Dart
  /// is single-threaded per isolate, so this is correct here.
  /// (The Workmanager background isolate has its own copy of
  /// this lock, so a tick overlapping a tap is still possible
  /// in theory — vanishingly rare, and the defensive dedupe
  /// above renders it once.) Only the read+write is locked;
  /// the GPS fix is taken before the lock.
  static Future<void> _createMutex = Future.value();

  Future<T> _withCreateLock<T>(Future<T> Function() action) async {
    final previous = _createMutex;
    final completer = Completer<void>();
    _createMutex = completer.future;
    await previous;
    try {
      return await action();
    } finally {
      completer.complete();
    }
  }

  /// Every entry, newest clock-in first. Managers only (the
  /// Hours screen); the rules deny it to anyone else. Capped
  /// at 500, newest first — a single-field orderBy needs no
  /// composite index, and the Hours screen only ever shows one
  /// week at a time. The cap is applied AFTER dedupe (the
  /// query fetches 1000 so duplicate rows cannot crowd real
  /// entries out of the page).
  Stream<List<TimeEntry>> watchAllEntries() {
    return _entries
        .orderBy('clockInAt', descending: true)
        .limit(1000)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(TimeEntry.fromFirestore).toList();
      list.sort((a, b) => b.clockInAt.compareTo(a.clockInAt));
      return dedupeTimeEntries(list).take(500).toList();
    });
  }

  /// One worker's entries, newest first. Sorted in Dart on
  /// purpose — a where(userId) + orderBy would need a
  /// composite index.
  Stream<List<TimeEntry>> watchEntriesForUser(String uid) {
    return _entries.where('userId', isEqualTo: uid).snapshots().map((snap) {
      final list = snap.docs.map(TimeEntry.fromFirestore).toList();
      list.sort((a, b) => b.clockInAt.compareTo(a.clockInAt));
      return dedupeTimeEntries(list);
    });
  }

  /// The worker's open entry, if any. Filtered in Dart: the
  /// open check (clockOutAt == null) rides on the user query
  /// above, so no extra index is needed.
  Stream<TimeEntry?> watchOpenEntry(String uid) {
    return watchEntriesForUser(uid).map((list) {
      final open = list.where((e) => e.isOpen).toList();
      return open.isEmpty ? null : open.first;
    });
  }

  /// One entry by id (the visit engine reads it to check the
  /// entry is still open). Null when the doc does not exist.
  Future<TimeEntry?> entryById(String entryId) async {
    final doc = await _entries.doc(entryId).get();
    if (!doc.exists) return null;
    return TimeEntry.fromFirestore(doc);
  }

  /// One-shot version of [watchOpenEntry] for the auto clock-in
  /// (which runs in a background isolate, without a stream).
  Future<TimeEntry?> openEntryFor(String uid) async {
    final open = await _openEntries(uid);
    return open.isEmpty ? null : open.first;
  }

  Future<List<TimeEntry>> _openEntries(String uid) async {
    final snap = await _entries.where('userId', isEqualTo: uid).get();
    return snap.docs
        .map(TimeEntry.fromFirestore)
        .where((e) => e.isOpen)
        .toList();
  }

  /// Toronto date of the instant (see week_hours.dart): the
  /// stored entry `date` is the Toronto calendar date of the
  /// clock-in, matching the server's 23:59 auto-close.
  static String _dateOf(DateTime at) => torontoDateStr(at);

  /// Clock in for the DAY, with no site: the worker is
  /// outside every site's fence (or there is no fix at all),
  /// so no site is claimed. The day entry's hours run from
  /// this tap to clock-out; where the worker actually was is
  /// recorded as site visits (see SiteVisit), not as a site
  /// on the entry. One active clock-in at a time, like
  /// [clockIn]: an open entry at another site is closed now
  /// (its open visit, if any, is closed too). The server
  /// flags the entry 'no-site-location' — a day entry has no
  /// fence to verify against; the visits are its proof.
  /// [skipLocation] skips the fix entirely (the Law 25 "Not
  /// now" choice); [fix] is the fix the caller already took,
  /// stored as the entry's coordinates.
  Future<String> clockInDay({
    required AppUser user,
    bool skipLocation = false,
    PositionFix? fix,
    bool auto = false,
    PositionFix? closeFix,
  }) async {
    final now = DateTime.now();
    final takenFix =
        skipLocation ? null : (fix ?? await _location.currentFix());
    return _withCreateLock(() async {
      final open = await _openEntries(user.id);
      for (final old in open) {
        // Already on a day entry (a concurrent call just
        // created it): nothing to do, return it instead of
        // opening a second day.
        if (old.siteId.isEmpty) return old.id;
      }
      final batch = _db.batch();
      _closeOldEntries(batch, open, now, closeFix);
      final ref = _entries.doc();
      final entry = TimeEntry(
        id: ref.id,
        userId: user.id,
        userName: user.name,
        siteId: '',
        siteName: '',
        date: _dateOf(now),
        clockInAt: now,
        clockInLat: takenFix?.lat,
        clockInLng: takenFix?.lng,
        clockInVerified: false,
        flagged: false,
        auto: auto,
      );
      // No 'hours' key at clock-in: the server function writes it
      // when the entry closes. `queuedAt` is the client time of
      // the tap: the rules accept a create whose clockInAt is
      // older than 10 minutes when it was queued offline and
      // syncs later (clockInAt within 2 minutes of queuedAt,
      // queuedAt within 24 hours of the server time) — without
      // it an offline clock-in that regains signal after 10
      // minutes is rejected and the entry vanishes.
      final data = entry.toMap()
        ..remove('hours')
        ..['queuedAt'] = Timestamp.fromDate(now);
      batch.set(ref, data);
      await batch.commit();
      await _closeOpenVisits(open.map((e) => e.id).toList(), now);
      return ref.id;
    });
  }

  /// Close every open entry in [open] at [now] inside [batch]
  /// (the clock-out location comes from [closeFix] when the
  /// caller has one — a site switch). Shared by [clockIn]
  /// and [clockInDay]; the visits those entries hold are
  /// closed separately by [_closeOpenVisits] after the batch
  /// commits.
  void _closeOldEntries(
    WriteBatch batch,
    List<TimeEntry> open,
    DateTime now,
    PositionFix? closeFix,
  ) {
    for (final old in open) {
      batch.update(_entries.doc(old.id), {
        'clockOutAt': Timestamp.fromDate(now),
        if (closeFix != null) 'clockOutLat': closeFix.lat,
        if (closeFix != null) 'clockOutLng': closeFix.lng,
      });
    }
  }

  /// Close the open visit (if any) on each of [entryIds] at
  /// [at] — the entry itself was just closed (clock-out,
  /// switch, or the 23:59 auto-close observed later), so its
  /// visit ends there too. Best-effort: a visit failure must
  /// never fail the clock-in/out that triggered it.
  Future<void> _closeOpenVisits(List<String> entryIds, DateTime at) async {
    for (final entryId in entryIds) {
      try {
        final visit = await openVisitFor(entryId);
        if (visit != null) await closeVisit(entryId, visit, at);
      } catch (_) {
        // The entry is already closed; the visit is retried by
        // the tracking engine's reconciliation on its next tick.
      }
    }
  }

  /// Close the open visit on [entryId] at [at] (used when the
  /// tracking engine observes an already-closed entry — the
  /// 23:59 server auto-close — and must end its visit there).
  Future<void> closeOpenVisitForEntry(String entryId, DateTime at) async {
    await _closeOpenVisits([entryId], at);
  }

  /// Clock in at [site]. One active clock-in at a time:
  /// - already clocked in at this site: nothing changes, the
  ///   open entry's id is returned.
  /// - clocked in at another site: that entry is closed now
  ///   (clockOutAt only — the server fills in the rest) and a
  ///   new entry opens here.
  /// The GPS fix is taken once, at the tap, for the new entry's
  /// coordinates only ([skipLocation] skips it entirely — the
  /// Law 25 "Not now" choice — and the entry is created with
  /// no coordinates). The caller may pass the [fix] it already
  /// took (to pick the site, for example) so only one fix is
  /// taken per tap; without it a fresh fix is taken here.
  /// [auto] marks entries the auto clock-in created (arrival
  /// at a site) — the history list shows an "Auto" tag, and
  /// the server deletes the entry if it closes less than 10
  /// minutes after opening. [closeFix] is the fix recorded as
  /// the clock-out location of any entry this clock-in closes
  /// (a site switch): without it the closed entry has no
  /// clock-out coordinates and the server flags it.
  /// Hours / verified / flagged are computed SERVER-side now:
  /// the client writes clockInVerified=false, flagged=false
  /// and NO hours field, and never computes them. Display-only
  /// values (e.g. TimeEntry.hoursSoFar, computed locally from
  /// the stored timestamps) are unaffected.
  Future<String> clockIn({
    required AppUser user,
    required Site site,
    bool skipLocation = false,
    PositionFix? fix,
    bool auto = false,
    PositionFix? closeFix,
  }) async {
    final now = DateTime.now();
    final takenFix =
        skipLocation ? null : (fix ?? await _location.currentFix());
    return _withCreateLock(() async {
      final open = await _openEntries(user.id);
      for (final old in open) {
        if (old.siteId == site.id) return old.id;
      }
      final batch = _db.batch();
      _closeOldEntries(batch, open, now, closeFix);
      final ref = _entries.doc();
      final entry = TimeEntry(
        id: ref.id,
        userId: user.id,
        userName: user.name,
        siteId: site.id,
        siteName: site.name,
        date: _dateOf(now),
        clockInAt: now,
        clockInLat: takenFix?.lat,
        clockInLng: takenFix?.lng,
        clockInVerified: false,
        flagged: false,
        auto: auto,
      );
      // No 'hours' key at clock-in: the server function writes it
      // when the entry closes. `queuedAt` is the client time of
      // the tap — see clockInDay: without it an offline
      // clock-in that regains signal after 10 minutes is
      // rejected by the rules and the entry vanishes.
      final data = entry.toMap()
        ..remove('hours')
        ..['queuedAt'] = Timestamp.fromDate(now);
      batch.set(ref, data);
      await batch.commit();
      await _closeOpenVisits(open.map((e) => e.id).toList(), now);
      return ref.id;
    });
  }

  /// Clock out of [entry]. The client changes clockOutAt and
  /// the clock-out coordinates; hours / verified / flagged are
  /// computed server-side from the stored timestamps and
  /// coordinates. A manual clock-out takes a GPS fix here
  /// (unless the caller already passed one, e.g. the auto
  /// clock-out) and stores it, exactly like clock-in does:
  /// without it the server re-verifies from null clock-out
  /// coordinates and flags every normal day 'no-location'.
  /// A missing fix (GPS off / denied) never blocks the
  /// clock-out — the entry closes without coordinates and the
  /// server flags it, as before. The entry's open visit, if
  /// any, closes at the same moment.
  ///
  /// Runs under the same [_withCreateLock] as clock-in: a
  /// concurrent auto clock-out / site switch used to make the
  /// batch touch an already-closed entry, the rules rejected
  /// the whole batch, and the user saw "clock out failed"
  /// although the entry was closed. Inside the lock the open
  /// entries are re-read, so only still-open entries are
  /// touched, and an already-closed entry is a no-op.
  ///
  /// Closes EVERY open entry for this worker, not just the one
  /// passed in: twins created before the create lock existed
  /// would otherwise linger open after a clock-out, and "one
  /// active clock-in at a time" is the invariant. The passed
  /// entry gets the clock-out fix; the others just get the
  /// same clock-out time. Already closed (a stale entry
  /// object, or a double-tap on clock-out) is a no-op, not an
  /// error.
  Future<void> clockOut(TimeEntry entry, {PositionFix? fix}) async {
    final now = DateTime.now();
    // The fix is taken before the lock (like clockIn): only
    // the read+write is locked, and a slow GPS fix must not
    // hold it.
    final takenFix = fix ?? await _location.currentFix();
    return _withCreateLock(() async {
      final open = await _openEntries(entry.userId);
      if (open.isEmpty) return;
      final batch = _db.batch();
      for (final e in open) {
        batch.update(_entries.doc(e.id), {
          'clockOutAt': Timestamp.fromDate(now),
          if (takenFix != null && e.id == entry.id)
            'clockOutLat': takenFix.lat,
          if (takenFix != null && e.id == entry.id)
            'clockOutLng': takenFix.lng,
        });
      }
      await batch.commit();
      await _closeOpenVisits(open.map((e) => e.id).toList(), now);
    });
  }

  /// One route-trail point for an open entry. Written by the
  /// foreground tracking service (every 5 minutes while clocked
  /// in) and by the background auto-clock check (every ~15
  /// minutes, as a fallback). Never written off the clock —
  /// the callers check the entry is still open first.
  Future<void> addBreadcrumb(String entryId, PositionFix fix) async {
    await _entries.doc(entryId).collection('breadcrumbs').add({
      'lat': fix.lat,
      'lng': fix.lng,
      'at': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// An entry's route trail, oldest first (the map draws it in
  /// order). No composite index: single-field orderBy on `at`.
  Stream<List<Breadcrumb>> watchBreadcrumbs(String entryId) {
    return _entries
        .doc(entryId)
        .collection('breadcrumbs')
        .orderBy('at')
        .snapshots()
        .map((snap) => snap.docs.map(Breadcrumb.fromFirestore).toList());
  }

  /// An entry's site visits, oldest arrival first. A visit is
  /// only written once confirmed (10 minutes inside the fence),
  /// so a day with no visits is a day the worker never stayed
  /// anywhere long enough to count — not missing data.
  Stream<List<SiteVisit>> watchVisits(String entryId) {
    return _entries
        .doc(entryId)
        .collection('siteVisits')
        .orderBy('arrivedAt')
        .snapshots()
        .map((snap) => snap.docs.map(SiteVisit.fromFirestore).toList());
  }

  /// The entry's open visit, if the worker is still at a site.
  /// At most one: the tracking engine never opens a second
  /// while one is open.
  Future<SiteVisit?> openVisitFor(String entryId) async {
    final snap = await _entries
        .doc(entryId)
        .collection('siteVisits')
        .where('leftAt', isEqualTo: null)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return SiteVisit.fromFirestore(snap.docs.first);
  }

  /// Write a confirmed visit: the worker has been inside the
  /// fence for 10 continuous minutes, so [arrivedAt] is the
  /// first-inside time, not now. `leftAt` stays null until
  /// the visit closes.
  ///
  /// Guarded by a transaction keyed on "no open visit exists"
  /// for this entry: the 5-minute foreground tick and the
  /// 15-minute Workmanager tick run in different isolates and
  /// could both confirm a visit at once, leaving two open
  /// visits — and openVisitFor's limit(1) would then never
  /// close the second one. The key is the visit's own
  /// identity: the doc id is derived from the entry, the site
  /// and the first-inside time (which both isolates read from
  /// the same SharedPreferences candidate, so a duplicate
  /// confirm computes the same id). The transaction reads
  /// that doc — this SDK's Transaction only reads single
  /// documents, not queries — and creates it only when it
  /// does not exist yet, returning the existing id otherwise.
  /// A genuinely different visit (another site, or a return
  /// with a new first-inside time) gets a different id and is
  /// created normally.
  Future<String> createVisit({
    required String entryId,
    required String siteId,
    required String siteName,
    required DateTime arrivedAt,
  }) async {
    final ref = _entries
        .doc(entryId)
        .collection('siteVisits')
        .doc('v_${siteId}_${arrivedAt.millisecondsSinceEpoch}');
    return _db.runTransaction<String>((tx) async {
      final existing = await tx.get(ref);
      if (existing.exists) return existing.id;
      tx.set(ref, {
        'siteId': siteId,
        'siteName': siteName,
        'arrivedAt': Timestamp.fromDate(arrivedAt),
        'leftAt': null,
        'durationMinutes': null,
      });
      return ref.id;
    });
  }

  /// Close [visit] at [leftAt]: the only update a visit ever
  /// gets (the rules enforce it). Duration is whole minutes
  /// between arrival and departure.
  Future<void> closeVisit(
      String entryId, SiteVisit visit, DateTime leftAt) async {
    final minutes = leftAt.difference(visit.arrivedAt).inMinutes;
    await _entries.doc(entryId).collection('siteVisits').doc(visit.id).update({
      'leftAt': Timestamp.fromDate(leftAt),
      'durationMinutes': minutes < 0 ? 0 : minutes,
    });
  }

  /// The fields an hours edit can change, as stored for the
  /// audit trail: site, date and times (Timestamps, like the
  /// entry itself).
  static Map<String, dynamic> _auditedFields({
    required String siteId,
    required String siteName,
    required String date,
    required DateTime clockInAt,
    required DateTime? clockOutAt,
  }) {
    return {
      'siteId': siteId,
      'siteName': siteName,
      'date': date,
      'clockInAt': Timestamp.fromDate(clockInAt),
      'clockOutAt': clockOutAt == null ? null : Timestamp.fromDate(clockOutAt),
    };
  }

  /// Manager correction: new clock-in / clock-out times and
  /// site for an entry. [site] is null for a day entry (no
  /// site): the editor offers an explicit "No site" choice,
  /// so editing a day entry — or an entry whose site was
  /// deleted — never silently re-sites it to the first site
  /// in the list. A null clock-out keeps the entry open (a
  /// forgotten clock-out the manager fills in later). The
  /// date follows the clock-in day (Toronto). Hours / verified
  /// / flagged are computed server-side, so the client writes
  /// times + site only — never hours.
  ///
  /// The edit is also written to the top-level `hoursAudit`
  /// collection (append-only: audit docs are never updated or
  /// deleted) with the editor's uid, the server timestamp, and
  /// the entry's fields before and after the edit. Entry update
  /// + audit write commit in one batch, so an edit never lands
  /// without its trail.
  Future<void> updateEntry(
    TimeEntry entry, {
    required DateTime clockInAt,
    required DateTime? clockOutAt,
    required Site? site,
    required String editedBy,
  }) async {
    final before = _auditedFields(
      siteId: entry.siteId,
      siteName: entry.siteName,
      date: entry.date,
      clockInAt: entry.clockInAt,
      clockOutAt: entry.clockOutAt,
    );
    final after = _auditedFields(
      siteId: site?.id ?? '',
      siteName: site?.name ?? '',
      date: _dateOf(clockInAt),
      clockInAt: clockInAt,
      clockOutAt: clockOutAt,
    );
    final batch = _db.batch();
    batch.update(_entries.doc(entry.id), {
      'siteId': site?.id ?? '',
      'siteName': site?.name ?? '',
      'date': _dateOf(clockInAt),
      'clockInAt': Timestamp.fromDate(clockInAt),
      'clockOutAt': clockOutAt == null ? null : Timestamp.fromDate(clockOutAt),
    });
    batch.set(_db.collection('hoursAudit').doc(), {
      'entryId': entry.id,
      'editedBy': editedBy,
      'editedAt': FieldValue.serverTimestamp(),
      'before': before,
      'after': after,
    });
    await batch.commit();
  }
}
