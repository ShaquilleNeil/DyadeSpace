import '../models/site.dart';
import '../models/time_entry.dart';
import 'location_service.dart';

/// What the auto clock-in should do on this check (pure —
/// unit-tested in test/auto_clock_decision_test.dart). No
/// Firebase, no platform channels: only the fix, the sites,
/// and the open entry.
enum AutoClockAction {
  /// Nothing changes (no fix, no site with coordinates, or
  /// already in the right state).
  none,

  /// Clock in at [site] (arrival, not clocked in yet).
  clockIn,

  /// Clock out of the open entry (left every site's radius).
  clockOut,

  /// Close the open entry and open a new one at [site]
  /// (arrived at a different site while clocked in).
  switchSite,
}

/// Pure auto clock-in decision: given one GPS fix, the sites,
/// the worker's open entry (if any), and the streaks the
/// caller carried from the previous check, what should happen?
/// - No fix, or no site with stored coordinates: nothing — the
///   check cannot decide, and an open entry is left alone.
///   Streaks are carried unchanged (a missing fix is neither
///   an arrival nor a departure).
/// - Not clocked in + fix inside a site's radius: clock in
///   there ONLY on the second consecutive check inside the
///   same fence ([insideStreak] >= 1, i.e. the previous check
///   already saw the worker inside). The first inside check
///   only starts the dwell (returns [AutoClockAction.none]
///   with insideStreak 1): a drive-by used to survive as
///   ~15 minutes of phantom work because the 15-minute tick
///   defeated the server's 10-minute drive-by delete. A fix
///   inside a different site restarts the dwell for that site.
/// - Not clocked in + fix outside every radius: nothing (auto
///   clock-in never creates an unverified entry on its own).
/// - Clocked in at the site the fix is inside: nothing.
/// - Clocked in + fix inside a DIFFERENT site's radius: switch.
/// - Clocked in + fix outside every radius: clock out ONLY
///   after a second consecutive outside check
///   ([outsideStreak] >= 1). The first outside check only
///   records the streak: one drifted indoor fix used to clock
///   a worker out mid-shift and a later tick clocked them back
///   in, splitting the day. This mirrors visit_decision.dart,
///   which requires 2 consecutive outside checks to close a
///   visit.
/// - Clocked in on a DAY entry (no site — siteId is empty):
///   nothing, ever. A day entry means the worker moves
///   between sites; leaving every fence is normal, not a
///   clock-out, and arriving at a site is a visit, not a
///   switch. The entry ends when the worker clocks out or at
///   the 23:59 auto-close.
///
/// The returned streaks are the state the caller must persist
/// for the next check (AutoClockService keeps them in
/// SharedPreferences, per worker): [outsideStreak] counts
/// consecutive outside checks while clocked in, [insideStreak]
/// consecutive inside checks at [insideSiteId] while not
/// clocked in. An action resets both to 0.
({AutoClockAction action, Site? site, int outsideStreak, int insideStreak,
    String? insideSiteId}) decideAutoClock({
  required PositionFix? fix,
  required List<Site> sites,
  required TimeEntry? openEntry,
  int outsideStreak = 0,
  int insideStreak = 0,
  String? insideSiteId,
}) {
  const none = (action: AutoClockAction.none, site: null, outsideStreak: 0,
      insideStreak: 0, insideSiteId: null);
  if (fix == null) {
    return (
      action: AutoClockAction.none,
      site: null,
      outsideStreak: outsideStreak,
      insideStreak: insideStreak,
      insideSiteId: insideSiteId,
    );
  }
  final location = LocationService();
  final nearest = location.nearestSite(fix, sites);
  if (nearest == null) {
    return (
      action: AutoClockAction.none,
      site: null,
      outsideStreak: outsideStreak,
      insideStreak: insideStreak,
      insideSiteId: insideSiteId,
    );
  }
  if (openEntry == null) {
    if (!nearest.withinRadius) {
      return none;
    }
    // Dwell: still inside the same fence on a second check.
    if (insideSiteId == nearest.site.id && insideStreak >= 1) {
      return (
        action: AutoClockAction.clockIn,
        site: nearest.site,
        outsideStreak: 0,
        insideStreak: 0,
        insideSiteId: null,
      );
    }
    return (
      action: AutoClockAction.none,
      site: null,
      outsideStreak: 0,
      insideStreak: insideSiteId == nearest.site.id ? insideStreak + 1 : 1,
      insideSiteId: nearest.site.id,
    );
  }
  if (openEntry.siteId.isEmpty) {
    return none;
  }
  if (nearest.withinRadius && nearest.site.id == openEntry.siteId) {
    return none;
  }
  if (nearest.withinRadius) {
    return (
      action: AutoClockAction.switchSite,
      site: nearest.site,
      outsideStreak: 0,
      insideStreak: 0,
      insideSiteId: null,
    );
  }
  // Outside every radius while clocked in at a site: debounce.
  if (outsideStreak >= 1) {
    return (
      action: AutoClockAction.clockOut,
      site: null,
      outsideStreak: 0,
      insideStreak: 0,
      insideSiteId: null,
    );
  }
  return (
    action: AutoClockAction.none,
    site: null,
    outsideStreak: outsideStreak + 1,
    insideStreak: 0,
    insideSiteId: null,
  );
}
