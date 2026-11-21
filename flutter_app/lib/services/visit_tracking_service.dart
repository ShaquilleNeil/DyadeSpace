import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/site.dart';
import 'location_service.dart';
import 'time_entry_service.dart';
import 'visit_decision.dart';

/// Runs the visit state machine on one location tick and
/// writes the result. Called from the two places that already
/// take a fix while clocked in — the foreground route-tracking
/// tick (every 5 minutes) and the auto-clock check (~15
/// minutes + every app resume) — so visits are evaluated on
/// the same cadence as the route trail, with no new timer and
/// no new permission.
///
/// The dwell candidate, the outside streak and the last-inside
/// time live in SharedPreferences, keyed by entry id: the two
/// tick paths run in different isolates (foreground service,
/// Workmanager) and share nothing in memory, but they share
/// the device's prefs. The visit docs themselves are the
/// source of truth for what happened; prefs only hold the
/// in-progress state, and a stale state for an entry that no
/// longer exists is dropped on the next tick.
///
/// The state for one entry is a single JSON blob under one
/// key — one setString per save, which is as atomic as
/// SharedPreferences allows (three separate keys could be
/// read mid-write by the other isolate and mix a new
/// candidate with an old streak). Legacy three-key state
/// written before this change is read once and migrated.
/// Stale blobs (no tick for over 24 hours) are purged when
/// any entry is evaluated.
///
/// A tick never throws: a failed read or write is skipped and
/// the next tick retries.
class VisitTrackingService {
  final TimeEntryService _entries;

  VisitTrackingService({TimeEntryService? entries})
      : _entries = entries ?? TimeEntryService();

  static String _stateKey(String entryId) => 'visit_state_$entryId';

  // Legacy keys (three separate writes, pre-Nov-21 fix).
  static String _candidateSiteKey(String entryId) =>
      'visit_candidate_site_$entryId';
  static String _candidateSinceKey(String entryId) =>
      'visit_candidate_since_$entryId';
  static String _outsideStreakKey(String entryId) =>
      'visit_outside_streak_$entryId';

  static const _staleAfter = Duration(hours: 24);

  /// The in-progress visit state for one entry.
  ({
    VisitCandidate? candidate,
    int outsideStreak,
    DateTime? lastInside,
    DateTime? updatedAt,
  }) _readState(SharedPreferences prefs, String entryId) {
    final raw = prefs.getString(_stateKey(entryId));
    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        final siteId = map['siteId'] as String?;
        final sinceMs = map['sinceMs'] as int?;
        final candidate = siteId != null && sinceMs != null
            ? VisitCandidate(
                siteId: siteId,
                since: DateTime.fromMillisecondsSinceEpoch(sinceMs),
              )
            : null;
        final lastMs = map['lastInsideMs'] as int?;
        final updatedMs = map['updatedMs'] as int?;
        return (
          candidate: candidate,
          outsideStreak: (map['streak'] as int?) ?? 0,
          lastInside: lastMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(lastMs),
          updatedAt: updatedMs == null
              ? null
              : DateTime.fromMillisecondsSinceEpoch(updatedMs),
        );
      } catch (_) {
        // Corrupt blob: fall through to the legacy keys.
      }
    }
    // Legacy three-key state (or nothing).
    final candidateSiteId = prefs.getString(_candidateSiteKey(entryId));
    final candidateSinceMs = prefs.getInt(_candidateSinceKey(entryId));
    final candidate = candidateSiteId != null && candidateSinceMs != null
        ? VisitCandidate(
            siteId: candidateSiteId,
            since: DateTime.fromMillisecondsSinceEpoch(candidateSinceMs),
          )
        : null;
    return (
      candidate: candidate,
      outsideStreak: prefs.getInt(_outsideStreakKey(entryId)) ?? 0,
      lastInside: null,
      updatedAt: candidate?.since,
    );
  }

  Future<void> _saveState(
    SharedPreferences prefs,
    String entryId,
    VisitDecision decision,
    DateTime? lastInside,
  ) async {
    final candidate = decision.candidate;
    final map = <String, dynamic>{
      'streak': decision.outsideStreak,
      'updatedMs': DateTime.now().millisecondsSinceEpoch,
      if (candidate != null) 'siteId': candidate.siteId,
      if (candidate != null)
        'sinceMs': candidate.since.millisecondsSinceEpoch,
      if (lastInside != null)
        'lastInsideMs': lastInside.millisecondsSinceEpoch,
    };
    await prefs.setString(_stateKey(entryId), jsonEncode(map));
    // Drop any legacy keys for this entry (migration).
    await prefs.remove(_candidateSiteKey(entryId));
    await prefs.remove(_candidateSinceKey(entryId));
    await prefs.remove(_outsideStreakKey(entryId));
  }

  Future<void> _clearState(SharedPreferences prefs, String entryId) async {
    await prefs.remove(_stateKey(entryId));
    await prefs.remove(_candidateSiteKey(entryId));
    await prefs.remove(_candidateSinceKey(entryId));
    await prefs.remove(_outsideStreakKey(entryId));
  }

  /// Drop this entry's in-progress visit state (used when the
  /// entry closed without an evaluate tick reaching it, e.g.
  /// the route service's closed-entry fallback).
  Future<void> clearStateForEntry(String entryId) async {
    final prefs = await SharedPreferences.getInstance();
    await _clearState(prefs, entryId);
  }

  /// Purge in-progress state for other entries whose last
  /// activity is over 24 hours old — a visit state that was
  /// never cleaned up (the entry closed, the service stopped,
  /// the app was killed mid-day) must not linger in prefs
  /// forever. The blob's own updated time is the age signal;
  /// a state with no timestamp at all is dropped too.
  Future<void> _purgeStaleStates(
      SharedPreferences prefs, String currentEntryId) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final cutoffMs = nowMs - _staleAfter.inMilliseconds;
    for (final key in prefs.getKeys().toList()) {
      String? entryId;
      if (key.startsWith('visit_state_')) {
        entryId = key.substring('visit_state_'.length);
      } else if (key.startsWith('visit_candidate_site_')) {
        entryId = key.substring('visit_candidate_site_'.length);
      } else {
        continue;
      }
      if (entryId == currentEntryId || entryId.isEmpty) continue;
      final state = _readState(prefs, entryId);
      final lastMs = state.updatedAt?.millisecondsSinceEpoch ??
          state.lastInside?.millisecondsSinceEpoch ??
          state.candidate?.since.millisecondsSinceEpoch;
      if (lastMs == null || lastMs < cutoffMs) {
        await _clearState(prefs, entryId);
      }
    }
  }

  /// One evaluation for [entryId] at [fix]: reconcile a
  /// closed entry (23:59 auto-close), then run the dwell
  /// state machine and write any visit it opens or closes.
  /// [sites] is the crew's site list, read by the caller.
  /// No-op when the entry does not exist or is already closed
  /// with no open visit. Never throws.
  Future<void> evaluate({
    required String entryId,
    required PositionFix fix,
    required List<Site> sites,
  }) async {
    try {
      final now = DateTime.now();
      final entry = await _entries.entryById(entryId);
      final prefs = await SharedPreferences.getInstance();
      await _purgeStaleStates(prefs, entryId);
      if (entry == null) {
        await _clearState(prefs, entryId);
        return;
      }
      // The entry closed without the client seeing it (the
      // 23:59 server auto-close): end its visit at the
      // clock-out time and drop the in-progress state.
      if (entry.clockOutAt != null) {
        await _entries.closeOpenVisitForEntry(entryId, entry.clockOutAt!);
        await _clearState(prefs, entryId);
        return;
      }
      final openVisit = await _entries.openVisitFor(entryId);
      final state = _readState(prefs, entryId);
      final candidate = state.candidate;
      final streak = state.outsideStreak;
      var lastInside = state.lastInside;

      // The departure time is the LAST fix inside the open
      // visit's fence, not the tick that closes it: the visit
      // only closes after 2 consecutive outside checks, so
      // closing at `now` would overstate every visit by up to
      // a tick on the departure end (and the arrival is already
      // the first-inside time, not the confirm tick).
      final insideSite = _siteInside(fix, sites);
      if (openVisit != null &&
          insideSite != null &&
          insideSite.id == openVisit.siteId) {
        lastInside = now;
      }

      var decision = decideVisit(
        fix: fix,
        sites: sites,
        openVisit: openVisit,
        candidate: candidate,
        outsideStreak: streak,
        now: now,
      );
      if (decision.action == VisitAction.closeVisit && openVisit != null) {
        final leftAt = lastInside != null &&
                lastInside.isAfter(openVisit.arrivedAt) &&
                !lastInside.isAfter(now)
            ? lastInside
            : now;
        await _entries.closeVisit(entryId, openVisit, leftAt);
        // Closing frees the slot: if the new site's dwell is
        // already met (it started while the old visit waited
        // out its debounce), confirm it in the same tick.
        decision = decideVisit(
          fix: fix,
          sites: sites,
          openVisit: null,
          candidate: decision.candidate,
          outsideStreak: 0,
          now: now,
        );
      }
      if (decision.action == VisitAction.confirmVisit &&
          decision.confirmSiteId != null &&
          decision.confirmArrivedAt != null) {
        final site = sites.firstWhere(
          (s) => s.id == decision.confirmSiteId,
          orElse: () => Site(id: decision.confirmSiteId!, name: ''),
        );
        await _entries.createVisit(
          entryId: entryId,
          siteId: site.id,
          siteName: site.name,
          arrivedAt: decision.confirmArrivedAt!,
        );
        // The confirming fix is inside the new visit's fence.
        lastInside = now;
      }
      await _saveState(prefs, entryId, decision, lastInside);
    } catch (_) {
      // Skip this tick; the next one retries.
    }
  }

  /// The site whose fence [fix] is inside, if any.
  Site? _siteInside(PositionFix fix, List<Site> sites) {
    final nearest = LocationService().nearestSite(fix, sites);
    return nearest != null && nearest.withinRadius ? nearest.site : null;
  }
}
