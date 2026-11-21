import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/site.dart';
import 'auto_clock_background.dart';
import 'auto_clock_decision.dart';
import 'location_service.dart';
import 'time_entry_service.dart';
import 'visit_tracking_service.dart';

/// What the auto clock-in should do on this check — see
/// [AutoClockAction] / [decideAutoClock] in
/// auto_clock_decision.dart (pure, unit-tested there).

/// Auto clock-in / clock-out on arrival / departure (Atto-style,
/// opt-in). The worker turns it on in Settings after a Law 25
/// background-location consent and an "Always" location grant.
///
/// How it runs: a Workmanager periodic task (every ~15 minutes,
/// the Android/iOS minimum — detection is NEVER instant; see
/// [AutoClockBackground]) plus a check whenever the app is
/// foregrounded. Each check takes one fix, decides with
/// [decideAutoClock], and acts through [TimeEntryService] with
/// the same write contract as a manual tap (verified=false,
/// flagged=false, no hours; the server verifies), plus
/// `auto: true` on entries it creates. Clock-out records the
/// exit fix, so the map can show where the worker left. The
/// decision is debounced: clock-in needs a second consecutive
/// fix inside the same fence, clock-out a second consecutive
/// fix outside every fence (streaks in SharedPreferences) —
/// one drifted fix never clocks anyone in or out.
///
/// Nothing here runs on web: Workmanager and background
/// location are mobile-only, and the service no-ops on kIsWeb.
class AutoClockService {
  static const _enabledKey = 'auto_clock_in_enabled';
  static const _consentKey = 'auto_clock_in_consent_given';
  static const _uidKey = 'auto_clock_uid';

  // Dwell / debounce state for decideAutoClock (per worker):
  // consecutive inside checks at one site while not clocked
  // in, and consecutive outside checks while clocked in.
  // The checks run in the Workmanager isolate and in the main
  // isolate, so the streaks live in SharedPreferences, not
  // memory — a single fix never clocks anyone in or out.
  static String _outsideStreakKey(String uid) =>
      'auto_clock_outside_streak_$uid';
  static String _insideStreakKey(String uid) =>
      'auto_clock_inside_streak_$uid';
  static String _insideSiteKey(String uid) => 'auto_clock_inside_site_$uid';

  static Future<void> _saveStreaks(
    SharedPreferences prefs,
    String uid, {
    required int outsideStreak,
    required int insideStreak,
    required String? insideSiteId,
  }) async {
    if (outsideStreak == 0) {
      await prefs.remove(_outsideStreakKey(uid));
    } else {
      await prefs.setInt(_outsideStreakKey(uid), outsideStreak);
    }
    if (insideStreak == 0) {
      await prefs.remove(_insideStreakKey(uid));
      await prefs.remove(_insideSiteKey(uid));
    } else {
      await prefs.setInt(_insideStreakKey(uid), insideStreak);
      if (insideSiteId != null) {
        await prefs.setString(_insideSiteKey(uid), insideSiteId);
      }
    }
  }

  // The default database / auth are resolved lazily (not in
  // the constructor) so tests can pass fakes without ever
  // touching FirebaseFirestore.instance / FirebaseAuth.instance,
  // which throw when Firebase is not initialized — the same
  // pattern as TimeEntryService.
  final FirebaseFirestore? _dbOverride;
  final FirebaseAuth? _authOverride;

  FirebaseFirestore get _db => _dbOverride ?? FirebaseFirestore.instance;

  /// Null when Firebase is not initialized (tests): the
  /// caller falls back to the stored uid, which is how the
  /// background task works anyway.
  FirebaseAuth? get _authOrNull {
    try {
      return _authOverride ?? FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  final LocationService _location;
  final TimeEntryService _entries;
  final VisitTrackingService _visits;

  /// Same-isolate re-entry guard: the startup check, the
  /// resume check and the periodic tick can all fire in one
  /// burst, and each check awaits a GPS fix — without this,
  /// two overlapping checks both read "not clocked in" and
  /// both create an entry (Nov 16: every history entry
  /// twice). Cross-isolate overlap (Workmanager background
  /// isolate vs main) is stopped by the create mutex in
  /// TimeEntryService; this stops the same-isolate
  /// double-fire cheaply. Static (per isolate) on purpose.
  static bool _checkInFlight = false;

  AutoClockService({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
    LocationService? location,
    TimeEntryService? entries,
    VisitTrackingService? visits,
  })  : _dbOverride = db,
        _authOverride = auth,
        _location = location ?? LocationService(),
        _entries = entries ?? TimeEntryService(),
        _visits = visits ?? VisitTrackingService();

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey) ?? false;
  }

  static Future<bool> isConsentGiven() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_consentKey) ?? false;
  }

  static Future<void> saveConsent(bool given) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentKey, given);
  }

  /// Turn auto clock-in on or off. On: remembers the uid (the
  /// background task runs without a signed-in widget tree) and
  /// registers the ~15-minute periodic check. Off: cancels it.
  /// Mobile only — a no-op on web.
  static Future<void> setEnabled(bool enabled, {String? uid}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (kIsWeb) return;
    if (enabled) {
      if (uid != null) await prefs.setString(_uidKey, uid);
      await registerAutoClockTask();
    } else {
      await cancelAutoClockTask();
    }
  }

  /// One check: fix → decide → act. Returns true when an entry
  /// was created, closed, or switched. Safe to call from the
  /// foreground and from the Workmanager background isolate
  /// (after Firebase.initializeApp there). Every failure path
  /// returns false instead of throwing, so a background tick
  /// never crashes the task.
  Future<bool> checkAndUpdate() async {
    if (kIsWeb) return false;
    // Re-entry guard (see _checkInFlight): a check already
    // running means this trigger is a duplicate of the same
    // burst — the running check acts on its own fix.
    if (_checkInFlight) return false;
    _checkInFlight = true;
    try {
      if (!await isEnabled()) return false;
      final prefs = await SharedPreferences.getInstance();
      final uid = _authOrNull?.currentUser?.uid ?? prefs.getString(_uidKey);
      if (uid == null) return false;
      final userDoc = await _db.collection('users').doc(uid).get();
      if (!userDoc.exists) return false;
      final user = AppUser.fromFirestore(userDoc);
      final fix = await _location.currentFix();
      if (fix == null) return false;
      final siteSnap = await _db.collection('sites').get();
      final sites = siteSnap.docs.map(Site.fromFirestore).toList();
      final open = await _entries.openEntryFor(uid);
      // Dwell / debounce: the decision needs the streaks from
      // the previous check, and the returned streaks are the
      // state for the next one (a first inside/outside fix only
      // records the streak — it never acts).
      final outsideStreak = prefs.getInt(_outsideStreakKey(uid)) ?? 0;
      final insideStreak = prefs.getInt(_insideStreakKey(uid)) ?? 0;
      final insideSiteId = prefs.getString(_insideSiteKey(uid));
      final decision = decideAutoClock(
        fix: fix,
        sites: sites,
        openEntry: open,
        outsideStreak: outsideStreak,
        insideStreak: insideStreak,
        insideSiteId: insideSiteId,
      );
      await _saveStreaks(
        prefs,
        uid,
        outsideStreak: decision.outsideStreak,
        insideStreak: decision.insideStreak,
        insideSiteId: decision.insideSiteId,
      );
      switch (decision.action) {
        case AutoClockAction.none:
          // Still clocked in? Drop a route point — the
          // background check is the trail's fallback when the
          // foreground service was stopped by the OS — and
          // evaluate the visit log for this fix.
          if (open != null) {
            await _entries.addBreadcrumb(open.id, fix);
            await _visits.evaluate(entryId: open.id, fix: fix, sites: sites);
          }
          return false;
        case AutoClockAction.clockIn:
          final entryId = await _entries.clockIn(
            user: user,
            site: decision.site!,
            fix: fix,
            auto: true,
          );
          await _entries.addBreadcrumb(entryId, fix);
          await _visits.evaluate(entryId: entryId, fix: fix, sites: sites);
          return true;
        case AutoClockAction.clockOut:
          // The service closes the entry's open visit too
          // (clockOut does it), and evaluate() reconciles the
          // now-closed entry — its closed-entry branch ends
          // any visit still open at the clock-out time (the
          // 23:59 auto-close path) and drops the in-progress
          // visit state.
          await _entries.clockOut(open!, fix: fix);
          await _visits.evaluate(entryId: open.id, fix: fix, sites: sites);
          return true;
        case AutoClockAction.switchSite:
          final entryId = await _entries.clockIn(
            user: user,
            site: decision.site!,
            fix: fix,
            auto: true,
            closeFix: fix,
          );
          await _entries.addBreadcrumb(entryId, fix);
          await _visits.evaluate(entryId: entryId, fix: fix, sites: sites);
          return true;
      }
    } catch (_) {
      return false;
    } finally {
      _checkInFlight = false;
    }
  }
}
