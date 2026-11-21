import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dyadespace/app.dart';
import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/l10n/privacy_policy.dart';
import 'package:dyadespace/models/app_user.dart';
import 'package:dyadespace/providers/auth_provider.dart';
import 'package:dyadespace/providers/locale_provider.dart';
import 'package:dyadespace/root_navigator.dart';
import 'package:dyadespace/screens/privacy_screen.dart';
import 'package:dyadespace/screens/settings_screen.dart';
import 'package:dyadespace/services/auth_service.dart';
import 'package:dyadespace/theme/app_theme.dart';

/// Privacy policy + self-service account deletion (Nov 16,
/// 2026): the policy renders without sign-in (public /privacy
/// route), Settings links to it, and the delete row calls the
/// server function then signs out — or stays signed in with
/// an error when the call fails. Pumped with mocked
/// providers — no Firebase, no network.
const _worker = AppUser(
  id: 'wanda',
  name: 'Wanda',
  email: 'wanda@example.com',
  role: UserRole.worker,
);

/// Fake AuthService: records the delete + sign-out calls
/// instead of touching Firebase. Constructible without
/// Firebase because AuthService resolves its singletons
/// lazily — only the methods actually called touch the SDKs.
class _FakeAuthService extends AuthService {
  bool deleteCalled = false;
  bool signOutCalled = false;
  bool throwOnDelete = false;

  @override
  Future<void> deleteMyAccount() async {
    deleteCalled = true;
    if (throwOnDelete) throw Exception('server down');
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }
}

Future<void> _pumpSettings(
  WidgetTester tester,
  _FakeAuthService fake, {
  String lang = 'en',
}) async {
  SharedPreferences.setMockInitialValues({});
  // Tall viewport: the Settings ListView only builds
  // on-screen children, and the privacy + delete rows sit
  // near the bottom — everything must be in view for the
  // finds below.
  tester.view.physicalSize = const Size(390, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        stringsProvider.overrideWithValue(AppStrings(lang)),
        currentUserProvider.overrideWith((ref) => Stream.value(_worker)),
        authServiceProvider.overrideWithValue(fake),
      ],
      child: MaterialApp(
        theme: buildAppDarkTheme(),
        home: const Scaffold(body: SettingsBody()),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('privacy policy renders all sections in English',
      (tester) async {
    // Tall viewport: the ListView only builds on-screen
    // children, and the policy is long — everything must be
    // in view for the finds below.
    tester.view.physicalSize = const Size(390, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(const AppStrings('en')),
          localeProvider.overrideWith((ref) => 'en'),
        ],
        child: MaterialApp(
          theme: buildAppDarkTheme(),
          home: const PrivacyScreen(),
        ),
      ),
    );
    await tester.pump();
    for (final section in privacyPolicySections('en')) {
      expect(find.text(section.title), findsOneWidget);
    }
    expect(find.textContaining('Last updated:'), findsOneWidget);
  });

  testWidgets('privacy policy renders in French', (tester) async {
    tester.view.physicalSize = const Size(390, 8000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(const AppStrings('fr')),
          // The policy sections follow localeProvider, not
          // just the strings override — both must be French.
          localeProvider.overrideWith((ref) => 'fr'),
        ],
        child: MaterialApp(
          theme: buildAppDarkTheme(),
          home: const PrivacyScreen(),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Politique de confidentialité'), findsOneWidget);
    expect(find.text('Qui nous sommes'), findsOneWidget);
    expect(find.textContaining('Dernière mise à jour'), findsOneWidget);
  });

  testWidgets('public /privacy route opens without signing in',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(const AppStrings('en')),
          // Signed out: no user at all.
          currentUserProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const DyadeSpaceApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    // The sign-in screen is showing; the public route must
    // still open on top of it without any account.
    expect(find.text('Sign in'), findsOneWidget);
    rootNavigatorKey.currentState!.pushNamed('/privacy');
    await tester.pumpAndSettle();
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Who we are'), findsOneWidget);
  });

  testWidgets(
      'direct /privacy URL renders the policy for a signed-out visitor',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Simulate the browser opening app.dyademanagement.com
    // /privacy directly: the initial route is /privacy, not /.
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/privacy';
    addTearDown(() {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(const AppStrings('en')),
          // Signed out: no user at all.
          currentUserProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const DyadeSpaceApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    // The policy must be the screen showing — not the sign-in
    // form, even though the auth gate owns '/'.
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Who we are'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets(
      'direct /privacy URL renders the policy when auth resolves late',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    // Same direct-URL start, but auth is still loading on the
    // first frames (the real web startup: Firebase Auth has not
    // emitted yet) and only resolves to signed-out afterwards.
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/privacy';
    addTearDown(() {
      tester.binding.platformDispatcher.defaultRouteNameTestValue = '/';
    });
    final controller = StreamController<AppUser?>();
    addTearDown(controller.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          stringsProvider.overrideWithValue(const AppStrings('en')),
          currentUserProvider.overrideWith((ref) => controller.stream),
        ],
        child: const DyadeSpaceApp(),
      ),
    );
    await tester.pump();
    await tester.pump();
    controller.add(null);
    await tester.pump();
    await tester.pump();
    // The policy must be the screen showing — not the sign-in
    // form, even though the auth gate owns '/'.
    expect(find.text('Privacy policy'), findsOneWidget);
    expect(find.text('Who we are'), findsOneWidget);
    expect(find.text('Sign in'), findsNothing);
  });

  testWidgets('Settings links to the privacy policy', (tester) async {
    final fake = _FakeAuthService();
    await _pumpSettings(tester, fake);
    expect(find.text('Privacy policy'), findsOneWidget);
    await tester.tap(find.text('Privacy policy'));
    await tester.pumpAndSettle();
    expect(find.text('Who we are'), findsOneWidget);
  });

  testWidgets('delete row shows the confirmation dialog', (tester) async {
    final fake = _FakeAuthService();
    await _pumpSettings(tester, fake);
    expect(find.text('Delete my account'), findsOneWidget);
    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    // The dialog states what is deleted and what is kept.
    expect(find.text('Delete your account?'), findsOneWidget);
    expect(find.textContaining('payroll record'), findsOneWidget);
    expect(find.textContaining('Former member'), findsOneWidget);
    // Cancelling deletes nothing.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(fake.deleteCalled, isFalse);
    expect(fake.signOutCalled, isFalse);
  });

  testWidgets('confirming delete calls the function then signs out',
      (tester) async {
    final fake = _FakeAuthService();
    await _pumpSettings(tester, fake);
    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    // Two "Delete my account" texts now: the row and the
    // dialog's confirm button — the button is the last one.
    await tester.tap(find.text('Delete my account').last);
    await tester.pumpAndSettle();
    expect(fake.deleteCalled, isTrue);
    expect(fake.signOutCalled, isTrue);
  });

  testWidgets('failed delete shows an error and stays signed in',
      (tester) async {
    final fake = _FakeAuthService()..throwOnDelete = true;
    await _pumpSettings(tester, fake);
    await tester.tap(find.text('Delete my account'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete my account').last);
    await tester.pumpAndSettle();
    expect(fake.deleteCalled, isTrue);
    expect(fake.signOutCalled, isFalse);
    expect(find.text('Could not delete your account. Try again.'),
        findsOneWidget);
  });
}
