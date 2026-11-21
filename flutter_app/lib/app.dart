import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'providers/auth_provider.dart';
import 'providers/locale_provider.dart';
import 'providers/theme_provider.dart';
import 'root_navigator.dart';
import 'screens/privacy_screen.dart';
import 'screens/sign_in_screen.dart';
import 'theme/app_theme.dart';

// The home shell is platform-specific: the phone shell on
// mobile, the web control center on web. dart.library.js_interop
// is true on both web renderers (JS and WASM) and false on
// mobile — dart.library.html would be false on WASM, so it must
// not be the condition. Both files expose the same `HomeShell`
// name (the web one via a typedef), so the line below does not
// change. The FCM topic sync, photo-queue drain, and push-tap
// routing used to be watched here; they live in HomeShell now
// (phone-only: the queue is dart:io and the web shell has no
// push), and HomeShell only ever builds while signed in, so the
// behaviour is identical.
import 'screens/home_shell.dart'
    if (dart.library.js_interop) 'screens/web/control_center_shell.dart'
    as shell;

/// Root app: shows sign-in when signed out, otherwise the
/// role-based home shell. Language comes from localeProvider,
/// theme mode from themeModeProvider (dark default).
class DyadeSpaceApp extends ConsumerWidget {
  const DyadeSpaceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lang = ref.watch(localeProvider);
    final themeMode = ref.watch(themeModeProvider);
    final user = ref.watch(currentUserProvider);
    return MaterialApp(
      title: 'DyadeSpace',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      locale: Locale(lang),
      supportedLocales: const [Locale('en'), Locale('fr'), Locale('es')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildAppTheme(),
      darkTheme: buildAppDarkTheme(),
      themeMode: themeMode,
      // Public route: the privacy policy must open WITHOUT
      // signing in — it is the link the app stores point to,
      // and it states the in-app account-deletion path. The
      // web hosting SPA rewrite serves /index.html for this
      // path, so a browser opening app.dyademanagement.com
      // /privacy lands here. `home` still owns '/' below; this
      // only handles the named route, signed in or not.
      onGenerateRoute: (settings) {
        if (settings.name == '/privacy') {
          return MaterialPageRoute(
            builder: (_) => const PrivacyScreen(),
            settings: settings,
          );
        }
        return null;
      },
      home: user.when(
        data: (u) {
          if (u == null) return const SignInScreen();
          // Deactivated while signed in: say so plainly instead
          // of silently looping back to the sign-in screen (the
          // profile stream still delivers the doc, just with
          // active=false). The state explains itself and offers
          // sign-out; the account itself can only be
          // re-activated by an admin.
          if (!u.active) return const _DeactivatedScreen();
          return const shell.HomeShell();
        },
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        // The profile stream can error during auth transitions -
        // most often at sign-out, when the Firestore listener for
        // the user doc is cut off as the token is revoked. That
        // is not a user-facing failure: the session is over
        // either way, so land on the sign-in screen, never an
        // error wall. Any OTHER error (network, rules, a
        // malformed doc) is a real failure for a signed-in user
        // and must NOT silently dump them to sign-in — show an
        // error state with a retry instead.
        error: (e, _) {
          if (e is FirebaseException && e.code == 'permission-denied') {
            return const SignInScreen();
          }
          return const _ProfileErrorScreen();
        },
      ),
    );
  }
}

/// Signed-in but the profile could not be loaded (network,
/// rules, malformed doc — anything except the
/// permission-denied-at-sign-out transition, which lands on
/// sign-in instead). Retry re-reads the profile stream; sign
/// out is the escape hatch if the account itself is the
/// problem.
class _ProfileErrorScreen extends ConsumerWidget {
  const _ProfileErrorScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.profileLoadFailed,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () => ref.invalidate(currentUserProvider),
                child: Text(s.retry),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () =>
                    ref.read(authServiceProvider).signOut(),
                child: Text(s.signOut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The signed-in user's profile was deactivated by an admin.
/// Plain explanation + sign-out; nothing else on this screen
/// works without an active profile.
class _DeactivatedScreen extends ConsumerWidget {
  const _DeactivatedScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                s.accountDeactivatedTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                s.accountDeactivatedBody,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () =>
                    ref.read(authServiceProvider).signOut(),
                child: Text(s.signOut),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
