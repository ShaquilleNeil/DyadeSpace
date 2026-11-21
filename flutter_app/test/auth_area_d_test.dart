import 'package:dyadespace/l10n/app_strings.dart';
import 'package:dyadespace/providers/auth_provider.dart';
import 'package:dyadespace/providers/locale_provider.dart';
import 'package:dyadespace/screens/sign_in_screen.dart';
import 'package:dyadespace/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Area D audit fixes (Nov 21, 2026): sign-up validation,
/// invite lowercasing / bulk-invite cap, and robust CSV parsing.
/// Firestore-backed paths (findInvite/createInvite round-trips)
/// are not covered here — they need the Firebase emulators;
/// what is covered is everything pure or validation-only.
void main() {
  group('AuthService.parseCsvEmails', () {
    test('skips an "email" header row and reads the email column', () {
      expect(
        AuthService.parseCsvEmails(
            'Name,Email\nAlice,alice@example.com\nBob,BOB@Example.com\n'),
        ['alice@example.com', 'bob@example.com'],
      );
    });

    test('header without an email-named column but no @ in row 0 is skipped',
        () {
      expect(
        AuthService.parseCsvEmails(
            'First name,Last name,Contact\nAlice,Smith,alice@example.com\n'),
        ['alice@example.com'],
      );
    });

    test('no header: first row counts as data', () {
      expect(
        AuthService.parseCsvEmails(
            'alice@example.com\nbob@example.com\n'),
        ['alice@example.com', 'bob@example.com'],
      );
    });

    test('quoted fields spanning newlines do not split rows', () {
      expect(
        AuthService.parseCsvEmails(
            'email,notes\n"alice@example.com","line one\nline two"\n"bob@example.com","hi"\n'),
        ['alice@example.com', 'bob@example.com'],
      );
    });

    test('quoted commas and escaped quotes stay inside the field', () {
      expect(
        AuthService.parseCsvEmails(
            'email,notes\n"alice@example.com","says ""hi"", then leaves"\n'),
        ['alice@example.com'],
      );
    });

    test('BOM, CRLF and duplicates are handled', () {
      expect(
        AuthService.parseCsvEmails(
            '\uFEFFemail\r\nalice@example.com\r\nAlice@Example.com\r\nnot-an-email\r\n'),
        ['alice@example.com'],
      );
    });
  });

  group('bulk invite cap', () {
    test('maxBulkInvites is 100', () {
      expect(AuthService.maxBulkInvites, 100);
    });

    test('BulkInviteResult defaults overCap to empty', () {
      const result = BulkInviteResult(created: ['a@example.com']);
      expect(result.overCap, isEmpty);
    });
  });

  group('signUpWithInvite validation', () {
    test('empty name throws before touching Firebase', () async {
      // The empty-name guard runs before createUserWithEmail-
      // AndPassword, so this needs no Firebase at all.
      final service = AuthService();
      await expectLater(
        service.signUpWithInvite(
          email: 'a@example.com',
          password: 'password1',
          name: '   ',
        ),
        throwsA(isA<StateError>().having(
          (e) => e.message,
          'message',
          'empty-name',
        )),
      );
    });
  });

  group('Area D strings exist in EN/FR/ES', () {
    const keys = [
      'createAccount',
      'confirmPassword',
      'nameRequired',
      'passwordsDoNotMatch',
      'noInvite',
      'accountDeactivatedTitle',
      'accountDeactivatedBody',
      'profileLoadFailed',
      'settingsSaveFailed',
      'adminInviteRequiresAdmin',
    ];
    test('every key is non-empty in every language', () {
      for (final lang in ['en', 'fr', 'es']) {
        final s = AppStrings(lang);
        final values = {
          'createAccount': s.createAccount,
          'confirmPassword': s.confirmPassword,
          'nameRequired': s.nameRequired,
          'passwordsDoNotMatch': s.passwordsDoNotMatch,
          'noInvite': s.noInvite,
          'accountDeactivatedTitle': s.accountDeactivatedTitle,
          'accountDeactivatedBody': s.accountDeactivatedBody,
          'profileLoadFailed': s.profileLoadFailed,
          'settingsSaveFailed': s.settingsSaveFailed,
          'adminInviteRequiresAdmin': s.adminInviteRequiresAdmin,
        };
        for (final key in keys) {
          expect(values[key], isNotEmpty, reason: '$key in $lang');
        }
        expect(s.bulkInviteOverCap(2), isNotEmpty);
      }
    });

    test('French strings differ from English (not untranslated)', () {
      const en = AppStrings('en');
      const fr = AppStrings('fr');
      expect(fr.createAccount, isNot(en.createAccount));
      expect(fr.confirmPassword, isNot(en.confirmPassword));
      expect(fr.passwordsDoNotMatch, isNot(en.passwordsDoNotMatch));
      expect(fr.noInvite, isNot(en.noInvite));
    });
  });

  group('SignInScreen sign-up validation', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            stringsProvider.overrideWithValue(const AppStrings('en')),
            // Real service: validation rejects before any Auth
            // call, so Firebase is never touched.
            authServiceProvider.overrideWithValue(AuthService()),
          ],
          child: const MaterialApp(home: SignInScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('empty name is rejected without creating an account',
        (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Confirm password'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your name first.'), findsOneWidget);
    });

    testWidgets('mismatched passwords are rejected', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), 'Test User');
      await tester.enterText(fields.at(1), 'a@example.com');
      await tester.enterText(fields.at(2), 'password1');
      await tester.enterText(fields.at(3), 'password2');
      await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
      await tester.pumpAndSettle();
      expect(find.text('The passwords do not match. Check them and try again.'),
          findsOneWidget);
    });
  });
}
