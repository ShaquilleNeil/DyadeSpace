import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/site.dart';
import 'location_service.dart';
import 'time_entry_service.dart';
import 'visit_tracking_service.dart';

/// Live route trail while clocked in (Atto-style): one GPS
/// point every 5 minutes into the open entry's `breadcrumbs`
/// subcollection, drawn as a trail on the entry's map screen.
/// Sampling stops the moment the entry closes — never tracked
/// off the clock.
///
/// How it runs: a foreground service (Android notification
/// "Recording your work route" + the location service type;
/// iOS uses the system location indicator + background mode),
/// with a 5-minute repeat timer. The service is started on
/// every clock-in (manual button + home-shell listener, which
/// also covers auto clock-ins that fired while the app was
/// closed) and stopped on clock-out. It is idempotent:
/// starting it for the entry it already tracks is a no-op.
///
/// HONEST LIMITS:
/// - The 5-minute points come from the foreground service's
///   timer while the app process is alive. If Android kills
///   the service (rare for a location foreground service, but
///   possible under extreme memory pressure), the trail has a
///   gap until the app is opened again; the ~15-minute
///   background auto-clock check still drops a point per tick
///   while clocked in, so the trail degrades to 15-minute
///   spacing instead of stopping.
/// - Points are best-effort: a tick with no GPS fix (indoors,
///   services off) is skipped, never faked.
/// - The background-isolate Firebase write needs the auth
///   session restored there; if it is not (first run after a
///   reinstall, for example), that tick is skipped and the
///   next one retries. Phone verification is still owed.
class RouteTrackingService {
  static const _entryIdKey = 'route_tracking_entry_id';

  /// 5 minutes, in milliseconds (ForegroundTaskEventAction
  /// takes a millisecond interval).
  static const breadcrumbIntervalMs = 5 * 60 * 1000;

  static String? _runningEntryId;

  /// Start (or keep) tracking for [entryId]. No-op on web,
  /// and a no-op when already tracking this entry.
  static Future<void> ensureRunning({
    required String entryId,
    required String notificationTitle,
    required String notificationText,
  }) async {
    if (kIsWeb) return;
    if (_runningEntryId == entryId &&
        await FlutterForegroundTask.isRunningService) {
      return;
    }
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
      _runningEntryId = null;
    }
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'dyadespace_tracking',
        channelName: 'Work route',
        channelDescription: 'Recording your location while you are clocked in.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(
          breadcrumbIntervalMs,
        ),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowAutoRestart: true,
      ),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_entryIdKey, entryId);
    final result = await FlutterForegroundTask.startService(
      serviceTypes: const [ForegroundServiceTypes.location],
      notificationTitle: notificationTitle,
      notificationText: notificationText,
      callback: _routeTrackingCallback,
    );
    if (result is ServiceRequestSuccess) {
      _runningEntryId = entryId;
    }
  }

  /// Stop tracking. No-op on web and when nothing runs.
  static Future<void> stop() async {
    if (kIsWeb) return;
    if (_runningEntryId == null &&
        !await FlutterForegroundTask.isRunningService) {
      return;
    }
    await FlutterForegroundTask.stopService();
    _runningEntryId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_entryIdKey);
  }
}

/// Foreground-service entry point (background isolate).
/// Registers the task handler; the handler does the work.
@pragma('vm:entry-point')
void _routeTrackingCallback() {
  // Register plugins in this background isolate before the
  // handler runs — the main isolate's registrant does not carry
  // over. flutter_foreground_task also calls this inside
  // setTaskHandler; calling it here first is the same thing,
  // idempotent, and keeps the ticks working even if the plugin's
  // own call ever moves.
  DartPluginRegistrant.ensureInitialized();
  FlutterForegroundTask.setTaskHandler(_RouteTrackingTaskHandler());
}

class _RouteTrackingTaskHandler extends TaskHandler {
  final _location = LocationService();

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      if (Firebase.apps.isEmpty) {
        // No options: the native google-services.json /
        // GoogleService-Info.plist bundled on the Mac supplies
        // them. Deliberately NOT DefaultFirebaseOptions — that
        // file is Mac-generated, and importing it here would pull
        // it into the widget-test import graph.
        await Firebase.initializeApp();
      }
    } catch (_) {
      // No Firebase in this isolate: ticks below fail soft
      // (each tick catches and skips) and the next app open
      // restarts the service properly.
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Fire-and-forget: a tick must never throw into the
    // service loop.
    _recordPoint();
  }

  Future<void> _recordPoint() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final entryId = prefs.getString(RouteTrackingService._entryIdKey);
      if (entryId == null) return;
      final entries = TimeEntryService();
      final doc = await FirebaseFirestore.instance
          .collection('timeEntries')
          .doc(entryId)
          .get();
      final data = doc.data();
      // Entry gone or closed (clock-out, auto-close, or the
      // 10-minute auto delete): stop the service — nothing
      // more to record. But first reconcile its visit: the
      // visit engine's closed-entry branch is only reached
      // when evaluate() runs against a closed entry, and this
      // tick is the one that observes the close — so evaluate
      // here (it ends the open visit at the clock-out time and
      // drops the in-progress state) instead of returning
      // early and leaving the visit open forever. With no fix
      // the visit is closed directly at the clock-out time.
      if (data == null || data['clockOutAt'] != null) {
        if (data != null && data['clockOutAt'] != null) {
          try {
            final closeAt = (data['clockOutAt'] as Timestamp).toDate();
            final fix = await _location.currentFix();
            if (fix != null) {
              final siteSnap = await FirebaseFirestore.instance
                  .collection('sites')
                  .get();
              final sites = siteSnap.docs.map(Site.fromFirestore).toList();
              await VisitTrackingService(entries: entries).evaluate(
                entryId: entryId,
                fix: fix,
                sites: sites,
              );
            } else {
              await entries.closeOpenVisitForEntry(entryId, closeAt);
              await VisitTrackingService(entries: entries)
                  .clearStateForEntry(entryId);
            }
          } catch (_) {
            // The visit stays open; the next app-open tick
            // reconciles it (the entry is closed, so the
            // auto-clock check's evaluate reaches the same
            // closed-entry branch).
          }
        }
        await FlutterForegroundTask.stopService();
        return;
      }
      final fix = await _location.currentFix();
      if (fix == null) return;
      await entries.addBreadcrumb(entryId, fix);
      // Same tick, same fix: evaluate the visit log (arrival /
      // departure per site) for this entry. Sites are read
      // fresh — the list is small and the tick is 5 minutes.
      try {
        final siteSnap =
            await FirebaseFirestore.instance.collection('sites').get();
        final sites = siteSnap.docs.map(Site.fromFirestore).toList();
        await VisitTrackingService(entries: entries).evaluate(
          entryId: entryId,
          fix: fix,
          sites: sites,
        );
      } catch (_) {
        // The breadcrumb already landed; the visit evaluation
        // retries on the next tick.
      }
    } catch (_) {
      // Skip this tick; the next one retries.
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}
