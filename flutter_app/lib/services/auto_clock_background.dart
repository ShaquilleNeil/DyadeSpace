import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:workmanager/workmanager.dart';

import 'auto_clock_service.dart';

/// Background half of auto clock-in (Atto-style arrival /
/// departure detection). Runs on mobile only — Workmanager has
/// no web implementation, and this file is never called on web.
///
/// HONEST LIMITS (read before promising anything to the crew):
/// - The check runs about every 15 minutes — that is the
///   minimum periodic interval Android WorkManager and iOS
///   BGTaskScheduler allow. Arrival/departure detection is
///   NEVER instant: a worker can be on site up to ~15 minutes
///   before the auto clock-in fires, and the same leaving.
///   The app also checks on every foreground/resume, so the
///   delay is worst when the phone sits untouched.
/// - iOS scheduling is fully OS-controlled: the system may
///   delay or skip runs to save battery, especially if the app
///   is rarely opened. The iOS project needs the "Background
///   fetch" + "Background processing" capabilities (Mac step).
/// - The task needs the Firebase session restored in the
///   background isolate (Firebase Auth restores it from disk)
///   and network access; without either, the tick silently
///   does nothing and the next tick retries.
const _autoClockTaskName = 'auto-clock-check';
const _autoClockUniqueName = 'dyadespace-auto-clock';

/// Registers the ~15-minute periodic auto-clock check.
/// Called when the worker turns auto clock-in on.
Future<void> registerAutoClockTask() async {
  if (kIsWeb) return;
  await Workmanager().registerPeriodicTask(
    _autoClockUniqueName,
    _autoClockTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
  );
}

/// Cancels the periodic check. Called when auto clock-in is
/// turned off. Does not close an open entry.
Future<void> cancelAutoClockTask() async {
  if (kIsWeb) return;
  await Workmanager().cancelByUniqueName(_autoClockUniqueName);
}

/// Workmanager entry point: runs in a background isolate.
/// Firebase must be initialized here — the main isolate's
/// instance does not carry over. Must be a top-level function
/// and kept alive by the entry-point pragma (release
/// tree-shaking would otherwise drop it).
@pragma('vm:entry-point')
void autoClockCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // FIRST: register plugins in this background isolate. The
    // main isolate's registrant does not carry over, and
    // workmanager does not register them itself (its
    // executeTask only ensures the binding; its native worker
    // creates a bare FlutterEngine). Without this, every plugin
    // call here — SharedPreferences in checkAndUpdate, Geolocator,
    // Firestore — throws "has not been registered" and the tick
    // silently does nothing. Idempotent; safe to call again.
    DartPluginRegistrant.ensureInitialized();
    try {
      if (Firebase.apps.isEmpty) {
        // No options: the native google-services.json /
        // GoogleService-Info.plist bundled on the Mac supplies
        // them. Deliberately NOT DefaultFirebaseOptions — that
        // file is Mac-generated, and importing it here would pull
        // it into the widget-test import graph.
        await Firebase.initializeApp();
      }
      if (task == _autoClockTaskName) {
        await AutoClockService().checkAndUpdate();
      }
      return true;
    } catch (_) {
      return false;
    }
  });
}
