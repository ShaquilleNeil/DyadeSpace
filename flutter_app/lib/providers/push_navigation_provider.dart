import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_router.dart';
import 'auth_provider.dart';

/// Wires FCM push taps to screens. Watched once by the app
/// root (DyadeSpaceApp) — subscribes when a user is signed in,
/// so the routing has a viewer (for task read-only rules).
/// Handles both the backgrounded case (onMessageOpenedApp)
/// and the terminated case (getInitialMessage, checked once,
/// on the next frame so the root navigator is attached).
/// A terminated-app tap that arrives before sign-in is stashed
/// in [_pendingInitialMessage] and routed as soon as a user is
/// signed in, instead of being dropped. Listeners attach once
/// per app lifetime; the current user is read fresh at tap
/// time, never captured at subscribe time.
bool _listenersAttached = false;
bool _initialMessageHandled = false;

/// A terminated-app push tap waiting for sign-in: the push
/// data to route once a viewer exists.
Map<String, dynamic>? _pendingInitialMessage;

final pushNavigationProvider = Provider<void>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  // A tap stashed while signed out routes now that a viewer
  // exists — on the next frame, so the navigator is attached.
  if (me != null && _pendingInitialMessage != null) {
    final data = _pendingInitialMessage;
    _pendingInitialMessage = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = rootNavigatorKey.currentState;
      if (navigator == null) return;
      unawaited(openPushData(navigator, data!, me));
    });
  }
  if (me == null) return;
  if (_listenersAttached) return;
  _listenersAttached = true;

  FirebaseMessaging.onMessageOpenedApp.listen((message) {
    final viewer = ref.read(currentUserProvider).valueOrNull;
    final navigator = rootNavigatorKey.currentState;
    if (viewer == null || navigator == null) return;
    unawaited(openPushData(navigator, message.data, viewer));
  });

  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(_handleInitialMessage(ref));
  });
});

Future<void> _handleInitialMessage(Ref ref) async {
  if (_initialMessageHandled) return;
  _initialMessageHandled = true;
  final message = await FirebaseMessaging.instance.getInitialMessage();
  if (message == null) return;
  final viewer = ref.read(currentUserProvider).valueOrNull;
  final navigator = rootNavigatorKey.currentState;
  if (viewer == null || navigator == null) {
    // Nobody signed in yet (or no navigator): stash the tap
    // and route it once sign-in completes — the provider body
    // above picks it up when the profile arrives. Without
    // this the terminated-app tap was silently dropped.
    if (viewer == null) _pendingInitialMessage = message.data;
    return;
  }
  await openPushData(navigator, message.data, viewer);
}
