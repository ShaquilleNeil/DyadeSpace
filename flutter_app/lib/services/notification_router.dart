import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../models/chat.dart';
import '../models/delivery_run.dart';
import '../models/notification_item.dart';
import '../models/task_item.dart';
import '../models/time_entry.dart';
import '../screens/chat_screen.dart';
import '../screens/clock_location_screen.dart';
import '../screens/manager/material_requests_screen.dart';
import '../screens/manager/reports_screen.dart';
import '../screens/manager/runs_progress_screen.dart';
import '../screens/task_screen.dart';
import '../screens/web/web_run_screen.dart';
import '../screens/web/web_shared.dart';

// The root navigator key lives in its own file so app.dart can
// use it without importing this router (which pulls in
// phone-only screens).
export '../root_navigator.dart';

/// One place that turns a notification into a screen. Both
/// entry points share it, so a tap behaves the same whether
/// the notification was tapped in the bell inbox or in the
/// system tray (FCM push):
/// - clock-in/out (and still-clocked-in) -> the clock location
///   map for that entry.
/// - chat message -> the conversation.
/// - day report -> the Reports screen.
/// - material request -> the requests screen.
/// - task id -> the task (read-only unless the viewer can act).
/// - run / stop id -> the run progress screen, read-only.
/// - nothing resolvable -> nothing (the caller already marked
///   the notification read). A doc that is gone, or a read
///   that fails, opens nothing and never throws.
///
/// On the web control center the caller passes [onWebSection]:
/// material-request notifications navigate to the web Requests
/// section instead of the phone requests screen, and run
/// notifications open the web run screen for the fetched run
/// (the web has no runs list section). The other destinations
/// are the same screens the phone uses — ChatScreen,
/// ClockLocationScreen and TaskScreen all render on web.
Future<void> openNotification(
  NavigatorState navigator,
  AppNotification n,
  AppUser me, {
  void Function(ControlCenterSection section)? onWebSection,
}) async {
  // Clock-in/out first: the entry id is the destination, and
  // the map needs the full entry (date, times, verified flag).
  // A still-clocked-in reminder routes the same way (the map
  // shows the open entry, clock-out side).
  if ((n.type == 'clockIn' ||
          n.type == 'clockOut' ||
          n.type == 'stillClockedIn') &&
      n.timeEntryId != null &&
      n.timeEntryId!.isNotEmpty) {
    TimeEntry? entry;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('timeEntries')
          .doc(n.timeEntryId!)
          .get();
      if (doc.exists) entry = TimeEntry.fromFirestore(doc);
    } on FirebaseException {
      entry = null;
    }
    final resolved = entry;
    if (resolved != null) {
      navigator.push(MaterialPageRoute(
        builder: (_) => ClockLocationScreen(
          entry: resolved,
          isClockOut: n.type != 'clockIn',
        ),
      ));
    }
    return;
  }

  if (n.type == 'chatMessage' &&
      n.conversationId != null &&
      n.conversationId!.isNotEmpty) {
    DocumentSnapshot<Map<String, dynamic>>? doc;
    try {
      doc = await FirebaseFirestore.instance
          .collection('conversations')
          .doc(n.conversationId!)
          .get();
    } on FirebaseException {
      doc = null;
    }
    if (doc != null && doc.exists) {
      navigator.push(MaterialPageRoute(
        builder: (_) => ChatScreen(
          conversationId: n.conversationId!,
          conversation: Conversation.fromFirestore(doc!),
        ),
      ));
    }
    return;
  }

  // A day-report notification names the report; the Reports
  // screen is the destination (on web, the control center's
  // Reports section).
  if (n.reportId != null && n.reportId!.isNotEmpty) {
    final webSection = onWebSection;
    if (webSection != null) {
      webSection(ControlCenterSection.reports);
      return;
    }
    navigator.push(MaterialPageRoute(
      builder: (_) => const ReportsScreen(),
    ));
    return;
  }

  // A material notification names the request; the requests
  // screen is the destination even when the request was linked
  // to a task (the task id there is incidental). On web that
  // is the control center's Requests section.
  if (n.materialRequestId != null && n.materialRequestId!.isNotEmpty) {
    final webSection = onWebSection;
    if (webSection != null) {
      webSection(ControlCenterSection.requests);
      return;
    }
    navigator.push(MaterialPageRoute(
      builder: (_) => const MaterialRequestsScreen(),
    ));
    return;
  }

  if (n.taskId != null && n.taskId!.isNotEmpty) {
    TaskItem? task;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('tasks')
          .doc(n.taskId!)
          .get();
      if (doc.exists) task = TaskItem.fromFirestore(doc);
    } on FirebaseException {
      task = null;
    }
    final resolvedTask = task;
    if (resolvedTask != null) {
      navigator.push(MaterialPageRoute(
        builder: (_) => TaskScreen(
          task: resolvedTask,
          readOnly: !taskEditableBy(resolvedTask, me),
        ),
      ));
    }
    return;
  }

  if ((n.runId != null && n.runId!.isNotEmpty) ||
      (n.stopId != null && n.stopId!.isNotEmpty)) {
    // On web there is no runs list section: open the run
    // itself on the web run screen.
    if (onWebSection != null) {
      DeliveryRun? run;
      try {
        if (n.runId != null && n.runId!.isNotEmpty) {
          final doc = await FirebaseFirestore.instance
              .collection('runs')
              .doc(n.runId!)
              .get();
          if (doc.exists) run = DeliveryRun.fromFirestore(doc);
        } else if (n.stopId != null && n.stopId!.isNotEmpty) {
          final snap = await FirebaseFirestore.instance
              .collection('runs')
              .limit(50)
              .get();
          for (final d in snap.docs) {
            final candidate = DeliveryRun.fromFirestore(d);
            if (candidate.orderedStops
                .any((st) => st.id == n.stopId)) {
              run = candidate;
              break;
            }
          }
        }
      } on FirebaseException {
        run = null;
      }
      final resolved = run;
      if (resolved != null) {
        navigator.push(MaterialPageRoute(
          builder: (_) => WebRunScreen(run: resolved),
        ));
      }
      return;
    }
    navigator.push(MaterialPageRoute(
      builder: (_) => const RunsProgressScreen(readOnly: true),
    ));
    return;
  }
}

/// Routes an FCM push tap. The push `data` carries the same id
/// fields the notification doc carries (the functions stringify
/// them), so the doc routing above applies unchanged.
Future<void> openPushData(
  NavigatorState navigator,
  Map<String, dynamic> data,
  AppUser me,
) async {
  final n = AppNotification(
    id: '',
    userId: me.id,
    title: '',
    body: '',
    type: data['type'] as String? ?? '',
    taskId: data['taskId'] as String?,
    runId: data['runId'] as String?,
    stopId: data['stopId'] as String?,
    conversationId: data['conversationId'] as String?,
    reportId: data['reportId'] as String?,
    materialRequestId: data['materialRequestId'] as String?,
    timeEntryId: data['timeEntryId'] as String?,
    createdAt: DateTime.now(),
  );
  await openNotification(navigator, n, me);
}
