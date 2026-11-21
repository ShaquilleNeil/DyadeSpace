import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_user.dart';
import '../models/site.dart';
import '../models/time_entry.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/location_provider.dart';
import '../providers/sites_provider.dart';
import '../providers/stages_provider.dart';
import '../providers/tasks_provider.dart';
import '../providers/time_entries_provider.dart';
import '../services/auto_clock_decision.dart';
import '../services/location_service.dart';
import '../services/route_tracking_service.dart';
import '../services/task_service.dart';
import '../theme/app_tokens.dart';

/// One-tap clock in / out button next to the Board / My Day
/// title in the shell AppBar (same tabs and roles as before:
/// Board for admin/manager, My Day for workers, Run for
/// delivery drivers). The old clock IconButton + ClockInCard
/// bottom sheet are gone — one tap now does the action, with
/// no site dropdown and no sheet:
/// - Label reads "Clock in" when not clocked in, "Clock out"
///   when clocked in, with a green dot and tint while clocked
///   in so the state reads at a glance. Compact, so the title,
///   bell and avatar still fit on a narrow phone.
/// - Tap "Clock in": Law 25 consent first (dialog before the
///   first clock-in ever, remembered per device), then ONE GPS
///   fix, then the nearest site with coordinates wins. Two
///   models, by role: a SITE WORKER clocks in at a site and
///   the fence applies — outside the nearest site's radius
///   the tap offers a pick-a-site dialog instead of a hard
///   block: the worker picks a site, clocks in there, and the
///   entry is flagged for review (the server verifies the fix
///   against the picked site's fence, so it lands flagged
///   'outside-radius'); cancelling the dialog clocks in
///   nothing. No fix, or no site with coordinates, falls back
///   to the site of the first task today (else the first site)
///   and is allowed, flagged for review instead of blocked. An
///   ADMIN, MANAGER or DELIVERY DRIVER clocks in for the DAY
///   instead: inside a site's radius the entry opens at that
///   site, outside every fence it opens as a day entry with no
///   site, and the visit log records where they actually were
///   — the fence never blocks them. The snackbar names the site
///   used, or says the day started. A successful clock-in starts
///   the route-tracking foreground service. No sites at all is
///   a clear message, not a silent no-op. When the fix could
///   not be taken, the snackbar says why (location services
///   off, or permission denied) — the clock-in still goes
///   ahead flagged.
/// - Tap "Clock out": closes the open entry — never blocked,
///   from anywhere — and stops route tracking.
/// - One-tap site switch: when the worker is clocked in at
///   site A and is now inside a DIFFERENT site B's fence, the
///   button reads "Switch to B" instead of "Clock out". The
///   candidate is computed from one fix when the button renders
///   with an open entry (and re-decided fresh at the tap, so a
///   move made while the app sat open still switches). Tapping
///   it closes A (with the fix as its clock-out location) and
///   opens B in one action, reusing the auto clock-in's switch
///   path — no confirmation dialog, and the snackbar names
///   both sites. No fix (or consent never given) means no
///   candidate: the button stays "Clock out" and the tap is a
///   plain clock-out, exactly as before. A switch is never
///   offered to a site the worker is not inside — and never
///   offered on a day entry (no site to switch from): a day
///   entry stays one entry while the worker moves, and the
///   visits show the moves instead.
/// - While the fix + write are in flight the button is
///   disabled with a spinner, so a double-tap cannot double
///   clock-in. The write contract is unchanged (the service
///   still writes clockInVerified=false, flagged=false, no
///   hours; the server verifies).
class ClockInButton extends ConsumerStatefulWidget {
  const ClockInButton({super.key});

  @override
  ConsumerState<ClockInButton> createState() => _ClockInButtonState();
}

class _ClockInButtonState extends ConsumerState<ClockInButton> {
  bool _busy = false;

  /// The site a one-tap switch would move to, from the last
  /// fix taken for the label ([_switchTargetForEntryId] is
  /// the open entry that fix belonged to). Null means no
  /// switch is offered — same site, outside every fence, no
  /// fix, or consent never given.
  Site? _switchTarget;
  String? _switchTargetForEntryId;

  /// Guards so the label refresh runs once per open entry
  /// (and never overlaps itself) instead of on every build.
  bool _refreshing = false;
  bool _refreshScheduled = false;

  /// Law 25 location consent, decided once per device and
  /// remembered: null = never asked, true = allowed (take the
  /// GPS fix at clock-in), false = "Not now" (clock in without
  /// a fix — the server marks the entry unverified/flagged).
  /// Either answer is a choice: the dialog never shows again
  /// after one is made.
  static const _consentKey = 'location_consent_given';

  /// Asks for location consent before the FIRST clock-in ever.
  /// Returns true when a GPS fix may be taken, false when the
  /// clock-in must go ahead without one. Returns null when the
  /// dialog was dismissed without choosing — nothing is saved
  /// and the question comes back next time.
  Future<bool?> _locationConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getBool(_consentKey);
    if (saved != null) return saved;
    if (!mounted) return null;
    final s = ref.read(stringsProvider);
    final allowed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.locationConsentTitle),
        content: Text(s.locationConsentBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.consentNotNow),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s.consentAllow),
          ),
        ],
      ),
    );
    if (allowed == null) return null;
    await prefs.setBool(_consentKey, allowed);
    return allowed;
  }

  /// Site of my first task today, else the first site — the
  /// fallback when a site worker has no fix or no site has
  /// coordinates to pick the nearest from.
  Site _fallbackSite(List<Site> sites) {
    final mine = ref.read(myTasksProvider).valueOrNull ?? [];
    final stageIndex = ref.read(stageIndexProvider);
    final today = TaskService.tasksForToday(mine, DateTime.now(), stageIndex);
    if (today.isNotEmpty) {
      final first = ref.read(siteByIdProvider)[today.first.siteId];
      if (first != null) return first;
    }
    return sites.first;
  }

  /// The day model is for admins, managers and delivery
  /// drivers only: they move between sites, so they clock in
  /// once for the day and the visit log records where they
  /// were. Site workers clock in at a site, with the fence
  /// block exactly as before.
  bool _usesDayModel(AppUser me) =>
      me.isAdminOrManager || me.role == UserRole.delivery;

  /// Pick-a-site fallback for a fence-blocked site worker:
  /// lists every site; the tap returns the picked site, a
  /// dismiss/cancel returns null (nothing is clocked in).
  /// The dialog states plainly that the entry will be flagged
  /// for review — the server flags it, since the fix is
  /// outside the picked site's fence.
  Future<Site?> _pickSiteOutsideFence({
    required List<Site> sites,
    required Site nearestSite,
    required int distanceMeters,
    required int radiusMeters,
  }) async {
    final s = ref.read(stringsProvider);
    return showDialog<Site>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.clockInPickSiteTitle),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.clockInPickSiteBody(
                  nearestSite.name, distanceMeters, radiusMeters)),
              const SizedBox(height: 12),
              for (final site in sites)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(site.name),
                  onTap: () => Navigator.of(ctx).pop(site),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.cancel),
          ),
        ],
      ),
    );
  }

  Future<void> _clockIn(AppUser me) async {
    final s = ref.read(stringsProvider);
    final consent = await _locationConsent();
    if (consent == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final siteById = ref.read(siteByIdProvider);
      final sites = siteById.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (sites.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.clockInNoSites)),
        );
        return;
      }
      // One GPS fix for the whole tap: it picks the site and
      // is passed to the service, which stores it — no second
      // fix inside the service.
      final location = ref.read(locationServiceProvider);
      final fix = consent ? await location.currentFix() : null;
      final nearest = consent ? location.nearestSite(fix, sites) : null;
      final dayModel = _usesDayModel(me);
      // Why the fix is missing, when it is: location services
      // off, or permission denied. The clock-in still goes
      // ahead flagged (below) — this note rides on the
      // success snackbar so the worker knows it was not
      // verified and why.
      String? locationNote;
      if (consent && fix == null) {
        try {
          final servicesOn = await Geolocator.isLocationServiceEnabled();
          final permission = await Geolocator.checkPermission();
          if (!servicesOn) {
            locationNote = s.locationServicesOff;
          } else if (permission == LocationPermission.denied ||
              permission == LocationPermission.deniedForever) {
            locationNote = s.locationPermissionDenied;
          } else {
            locationNote = s.locationUnavailable;
          }
        } catch (_) {
          locationNote = s.locationUnavailable;
        }
      }
      // Site workers: the fence applies — a fix outside the
      // nearest site's radius offers the pick-a-site dialog
      // instead of a hard block (the picked entry is flagged
      // for review). Cancelling clocks in nothing. No fix /
      // no site with coordinates is never blocked (allowed,
      // flagged for review — see fenceCheck). The day model
      // never blocks: outside every fence the entry opens
      // with no site.
      Site? pickedSite;
      if (!dayModel) {
        final fence = LocationService.fenceCheck(fix, nearest);
        if (fence.blocked) {
          if (!mounted) return;
          pickedSite = await _pickSiteOutsideFence(
            sites: sites,
            nearestSite: nearest!.site,
            distanceMeters: fence.distanceMeters!.round(),
            radiusMeters: fence.radiusMeters!.round(),
          );
          if (pickedSite == null || !mounted) return;
        }
      }
      final insideSite =
          nearest != null && nearest.withinRadius ? nearest.site : null;
      // Day model: inside a fence the entry opens at that
      // site; outside every fence (or with no fix / no site
      // with coordinates) it opens as a day entry with no
      // site. Site workers: inside a fence the entry opens at
      // that site, otherwise at the picked site (fence-blocked
      // fallback, flagged for review) or the fallback site
      // (the fence already allowed the tap).
      final site = dayModel
          ? insideSite
          : (pickedSite ?? insideSite ?? _fallbackSite(sites));
      final entryId = site == null
          ? await ref.read(timeEntryServiceProvider).clockInDay(
                user: me,
                skipLocation: !consent,
                fix: fix,
              )
          : await ref.read(timeEntryServiceProvider).clockIn(
                user: me,
                site: site,
                skipLocation: !consent,
                fix: fix,
              );
      // Route trail: one point every 5 minutes while clocked
      // in, from the foreground service (stops at clock-out).
      await RouteTrackingService.ensureRunning(
        entryId: entryId,
        notificationTitle: s.trackingNotificationTitle,
        notificationText: s.trackingNotificationText,
      );
      if (!mounted) return;
      // _clockIn only runs when nothing is open (the button
      // calls _onClockedInTap while clocked in), so there is
      // no "switched" case here — the old switched branch was
      // dead and is gone; a switch goes through _switchSite.
      var message = site == null
          ? s.clockedInForDay
          : pickedSite != null
              ? s.clockInPickedSiteFlagged(site.name)
              : s.clockedInAt(site.name);
      if (locationNote != null) message = '$message $locationNote';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.clockInFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clockOut(TimeEntry entry) async {
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      await ref.read(timeEntryServiceProvider).clockOut(entry);
      await RouteTrackingService.stop();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.clockOut)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.clockOutFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Works out whether a switch is on offer for [open], from
  /// one fresh fix — the same pure decision the auto clock-in
  /// uses (see decideAutoClock). Only runs when location
  /// consent was already given: without it no fix is ever
  /// taken, and the tap stays a plain clock-out. A day entry
  /// (no site) never offers a switch: it stays one entry
  /// while the worker moves, and the visits show the moves.
  Future<void> _onClockedInTap(AppUser me, TimeEntry open) async {
    final prefs = await SharedPreferences.getInstance();
    if (open.siteId.isNotEmpty && prefs.getBool(_consentKey) == true) {
      final sites = ref.read(siteByIdProvider).values.toList();
      if (sites.isNotEmpty) {
        final fix = await ref.read(locationServiceProvider).currentFix();
        final decision = decideAutoClock(
          fix: fix,
          sites: sites,
          openEntry: open,
        );
        if (decision.action == AutoClockAction.switchSite &&
            decision.site != null &&
            fix != null) {
          await _switchSite(me, open, decision.site!, fix);
          return;
        }
      }
    }
    await _clockOut(open);
  }

  /// One-tap switch: close [open] and open a new entry at
  /// [target], with [fix] as both the new entry's coordinates
  /// and the closed entry's clock-out location — the auto
  /// clock-in's switch path, but manual (no `auto` flag, so
  /// the history shows no Auto tag). No confirmation dialog;
  /// the snackbar names both sites, so a mistaken tap is
  /// visible at once.
  Future<void> _switchSite(
      AppUser me, TimeEntry open, Site target, PositionFix fix) async {
    final s = ref.read(stringsProvider);
    setState(() => _busy = true);
    try {
      final entryId = await ref.read(timeEntryServiceProvider).clockIn(
            user: me,
            site: target,
            fix: fix,
            closeFix: fix,
          );
      await RouteTrackingService.ensureRunning(
        entryId: entryId,
        notificationTitle: s.trackingNotificationTitle,
        notificationText: s.trackingNotificationText,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.clockInSwitched(open.siteName, target.name)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.clockInFailed('$e'))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Recomputes the switch candidate for [open] from one fix,
  /// for the label. Runs once per open entry (guarded by
  /// [_switchTargetForEntryId]); the tap re-decides fresh, so
  /// a stale label can never cause a wrong switch. The entry
  /// id is stamped even when there is no switch (or no
  /// consent) so the refresh is not re-scheduled on every
  /// build — a new open entry stamps a new id and refreshes
  /// again. A stale result (the entry changed mid-flight) is
  /// discarded. A day entry (no site) never has a switch
  /// candidate.
  Future<void> _refreshSwitchTarget(TimeEntry open) async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      Site? target;
      if (open.siteId.isNotEmpty && prefs.getBool(_consentKey) == true) {
        final fix = await ref.read(locationServiceProvider).currentFix();
        if (!mounted) return;
        final current = ref.read(openTimeEntryProvider).valueOrNull;
        if (current == null || current.id != open.id) return;
        final sites = ref.read(siteByIdProvider).values.toList();
        if (sites.isNotEmpty) {
          final decision = decideAutoClock(
            fix: fix,
            sites: sites,
            openEntry: current,
          );
          if (decision.action == AutoClockAction.switchSite) {
            target = decision.site;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _switchTarget = target;
        _switchTargetForEntryId = open.id;
      });
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    if (me == null) {
      return const SizedBox.shrink();
    }
    final open = ref.watch(openTimeEntryProvider).valueOrNull;
    final clockedIn = open != null;
    // The switch candidate is computed from one fix when the
    // button first renders with this open entry (post-frame,
    // once per entry id — never in the build itself, and never
    // re-scheduled once stamped). The tap re-decides fresh.
    if (clockedIn && _switchTargetForEntryId != open.id && !_refreshScheduled) {
      _refreshScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refreshScheduled = false;
        _refreshSwitchTarget(open);
      });
    }
    final switchTarget =
        clockedIn && _switchTargetForEntryId == open.id ? _switchTarget : null;
    final label = switchTarget != null
        ? s.switchToSite(switchTarget.name)
        : clockedIn
            ? s.clockOut
            : s.clockIn;
    final color = clockedIn ? tokens.statusDone : AppTokens.accent;
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TextButton(
        onPressed: _busy
            ? null
            : () {
                HapticFeedback.lightImpact();
                final current = open;
                if (current != null) {
                  _onClockedInTap(me, current);
                } else {
                  _clockIn(me);
                }
              },
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        ),
        child: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (clockedIn)
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: tokens.statusDone,
                        shape: BoxShape.circle,
                      ),
                    ),
                  if (clockedIn) const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
