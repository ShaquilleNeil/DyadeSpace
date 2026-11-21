import 'package:flutter_web_plugins/flutter_web_plugins.dart';

/// URL strategy, web implementation: read the browser's
/// pathname as the route (path URLs, not hash URLs).
///
/// Flutter web defaults to hash routing: the engine reads the
/// route from location.hash and ignores the pathname, so
/// opening app.dyademanagement.com/privacy started the app at
/// '/' (the sign-in screen) and the /privacy onGenerateRoute in
/// app.dart never ran. Path routing makes the public /privacy
/// URL work for signed-out visitors. The Firebase Hosting SPA
/// rewrite ("**" -> /index.html, in firebase.json) already
/// serves the app for that path, so no hosting change is
/// needed. Only /privacy is public; every other route is still
/// behind the sign-in gate in app.dart.
void configureUrlStrategy() => usePathUrlStrategy();
