import 'package:flutter/material.dart';

import 'client_share_screen.dart';

/// The public client-share route: `/client/<token>`.
///
/// This file is the part of the share link that lives outside
/// the owned web screens — `app.dart` calls it from its
/// `onGenerateRoute`, next to the `/privacy` branch (same
/// pattern: a public route that must open WITHOUT signing in).
/// The coordinator wires it in; the exact patch is:
///
/// ```dart
/// // in app.dart, inside onGenerateRoute, before `return null`:
/// final clientRoute = clientShareRoute(settings);
/// if (clientRoute != null) return clientRoute;
/// ```
///
/// (with `import 'screens/client_share_route.dart';` at the top
/// of app.dart). The hosting SPA rewrite already serves
/// `/index.html` for any path, so a browser opening
/// `app.dyademanagement.com/client/<token>` lands here, and
/// `configureUrlStrategy()` (main.dart) keeps the path as the
/// route instead of a hash. Trailing slashes and query strings
/// are tolerated; anything that is not `/client/<token>`
/// returns null so the normal routing applies.
Route<dynamic>? clientShareRoute(RouteSettings settings) {
  final name = settings.name ?? '';
  final path = name.split('?').first;
  final trimmed =
      path.endsWith('/') && path.length > 1 ? path.substring(0, path.length - 1) : path;
  const prefix = '/client/';
  if (!trimmed.startsWith(prefix)) return null;
  final token = trimmed.substring(prefix.length);
  // One path segment only — `/client/a/b` is not a share link.
  if (token.isEmpty || token.contains('/')) return null;
  return MaterialPageRoute(
    builder: (_) => ClientShareScreen(token: token),
    settings: settings,
  );
}
