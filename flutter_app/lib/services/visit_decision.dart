import '../models/site.dart';
import '../models/site_visit.dart';
import 'location_service.dart';

/// A worker has been inside a site's fence since [since]
/// without a visit opening yet — the dwell clock. Held in
/// SharedPreferences by the tracking engine (see
/// VisitTrackingService), never in Firestore: a drive-by
/// must leave no trace, so no doc is written until the visit
/// is confirmed.
class VisitCandidate {
  final String siteId;
  final DateTime since;
  const VisitCandidate({required this.siteId, required this.since});
}

enum VisitAction {
  /// Nothing changes (no fix, no fence, dwell not met yet).
  none,

  /// Open a visit for [confirmSiteId] with arrival
  /// [confirmArrivedAt] (the first-inside time, not now).
  confirmVisit,

  /// Close the open visit (the worker has been outside its
  /// fence for [outsideChecksToClose] consecutive checks).
  closeVisit,
}

/// The pure visit state machine (unit-tested in
/// test/site_visit_decision_test.dart). No Firebase, no
/// platform channels: only the fix, the sites, the open visit,
/// the dwell candidate and the outside streak.
///
/// - No fix: nothing changes — a missing fix is not leaving.
/// - Inside a site's fence: the dwell clock runs. A visit
///   opens only after [dwell] continuous minutes inside that
///   fence, so a drive-by (in and out within minutes) never
///   logs. The arrival time is the FIRST inside check, so the
///   visit's times are right even though the write happens
///   10 minutes later.
/// - Inside a DIFFERENT site while a visit is open: the open
///   visit's outside streak grows AND the new site's dwell
///   clock starts — the arrival is not lost while the old
///   visit waits out its debounce.
/// - Outside the open visit's fence: the streak grows; the
///   visit closes after [outsideChecksToClose] consecutive
///   outside checks, so one GPS flicker indoors never ends a
///   visit. Back inside resets the streak and drops any
///   other-site candidate.
/// - Overlapping fences: the site whose centre is nearest
///   wins (LocationService.nearestSite), so the visit belongs
///   to one site only.
class VisitDecision {
  final VisitAction action;

  /// The dwell candidate after this check (null = none).
  final VisitCandidate? candidate;

  /// Consecutive outside checks against the open visit.
  final int outsideStreak;

  /// Set when [action] is [VisitAction.confirmVisit].
  final String? confirmSiteId;
  final DateTime? confirmArrivedAt;

  const VisitDecision({
    required this.action,
    required this.candidate,
    required this.outsideStreak,
    this.confirmSiteId,
    this.confirmArrivedAt,
  });
}

/// Minutes inside one fence before a visit counts.
const Duration visitDwell = Duration(minutes: 10);

/// Consecutive checks outside the open visit's fence before
/// it closes (GPS drift indoors).
const int outsideChecksToClose = 2;

VisitDecision decideVisit({
  required PositionFix? fix,
  required List<Site> sites,
  required SiteVisit? openVisit,
  required VisitCandidate? candidate,
  required int outsideStreak,
  required DateTime now,
}) {
  const none = VisitAction.none;
  if (fix == null) {
    return VisitDecision(
      action: none,
      candidate: candidate,
      outsideStreak: outsideStreak,
    );
  }
  final location = LocationService();
  final nearest = location.nearestSite(fix, sites);
  final inside = nearest != null && nearest.withinRadius ? nearest.site : null;

  // Still inside the open visit's site: the visit continues,
  // the streak resets, any other-site candidate is stale.
  if (openVisit != null && inside != null && inside.id == openVisit.siteId) {
    return const VisitDecision(
      action: none,
      candidate: null,
      outsideStreak: 0,
    );
  }

  if (openVisit != null) {
    // Outside the open visit's fence (another site, or none):
    // the streak grows, and a new site's dwell clock starts
    // in parallel so its arrival is not lost.
    final streak = outsideStreak + 1;
    final nextCandidate = inside == null
        ? null
        : (candidate != null && candidate.siteId == inside.id
            ? candidate
            : VisitCandidate(siteId: inside.id, since: now));
    if (streak >= outsideChecksToClose) {
      return VisitDecision(
        action: VisitAction.closeVisit,
        candidate: nextCandidate,
        outsideStreak: 0,
      );
    }
    return VisitDecision(
      action: none,
      candidate: nextCandidate,
      outsideStreak: streak,
    );
  }

  // No open visit: run the dwell clock for the site the
  // worker is inside (if any).
  if (inside == null) {
    return const VisitDecision(
      action: none,
      candidate: null,
      outsideStreak: 0,
    );
  }
  if (candidate == null || candidate.siteId != inside.id) {
    return VisitDecision(
      action: none,
      candidate: VisitCandidate(siteId: inside.id, since: now),
      outsideStreak: 0,
    );
  }
  if (now.difference(candidate.since) >= visitDwell) {
    return VisitDecision(
      action: VisitAction.confirmVisit,
      candidate: null,
      outsideStreak: 0,
      confirmSiteId: inside.id,
      confirmArrivedAt: candidate.since,
    );
  }
  return VisitDecision(
    action: none,
    candidate: candidate,
    outsideStreak: 0,
  );
}
