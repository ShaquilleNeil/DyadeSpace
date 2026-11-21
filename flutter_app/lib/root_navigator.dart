import 'package:flutter/material.dart';

/// The app's root navigator, owned by MaterialApp (see
/// app.dart). Push taps have no BuildContext, so they navigate
/// through this key. It lives in its own file (not in
/// notification_router.dart) because app.dart needs it and the
/// router pulls in phone-only screens — the web build must be
/// able to import this key without importing the router.
final GlobalKey<NavigatorState> rootNavigatorKey =
    GlobalKey<NavigatorState>();
