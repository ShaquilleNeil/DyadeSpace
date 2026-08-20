import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/employee.dart';
import '../utils/friendly_error.dart';
import 'firebase_providers.dart';

/// Raw Firebase auth state — mirrors Supabase's `SessionStatus` stream.
final authStateChangesProvider = StreamProvider<User?>((ref) {
  return ref.watch(authServiceProvider).authStateChanges;
});

/// The signed-in user's employee doc (carries `role`) — mirrors
/// `AuthViewModel.currentEmployee` + `fetchRole()` combined, since role now
/// lives directly on the employee doc instead of behind an RPC.
final currentEmployeeProvider = StreamProvider<Employee?>((ref) {
  final auth = ref.watch(authServiceProvider);
  final firestore = ref.watch(firestoreServiceProvider);
  return auth.authStateChanges.asyncExpand((user) {
    if (user == null) return Stream<Employee?>.value(null);
    return firestore.watchEmployee(user.uid);
  });
});

/// One-shot status/error messages — mirrors `AuthViewModel._authMessage`.
class AuthMessageNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? message) => state = message;
}

final authMessageProvider =
    NotifierProvider<AuthMessageNotifier, String?>(AuthMessageNotifier.new);

final authControllerProvider = Provider<AuthController>((ref) => AuthController(ref));

class AuthController {
  AuthController(this._ref);

  final Ref _ref;

  Future<void> signUp({
    required String firstName,
    required String lastName,
    required String phone,
    required String email,
    required String password,
  }) async {
    try {
      final user =
          await _ref.read(authServiceProvider).signUp(email: email, password: password);

      // Self-signup always creates a plain worker with no project — role
      // elevation and project assignment only ever happen through an admin's
      // staff-edit sheet (also enforced server-side by firestore.rules).
      await _ref.read(firestoreServiceProvider).createEmployee(
            Employee(
              id: user.uid,
              firstName: firstName,
              lastName: lastName,
              phone: phone,
              email: email,
              role: EmployeeRole.employee,
            ),
          );

      await _ref.read(authServiceProvider).signOut();
      _ref.read(authMessageProvider.notifier).set('Sign up successful');
    } catch (e) {
      _ref.read(authMessageProvider.notifier).set(
            friendlyErrorMessage(e, fallback: 'Could not create account. Please try again.'),
          );
    }
  }

  Future<void> logIn({required String email, required String password}) async {
    try {
      await _ref.read(authServiceProvider).logIn(email: email, password: password);
    } catch (e) {
      _ref.read(authMessageProvider.notifier).set(
            friendlyErrorMessage(e, fallback: 'Could not log in. Please try again.'),
          );
    }
  }

  Future<void> signOut() async {
    try {
      await _ref.read(authServiceProvider).signOut();
      _ref.read(authMessageProvider.notifier).set('Sign out successful');
    } catch (e) {
      _ref.read(authMessageProvider.notifier).set(
            friendlyErrorMessage(e, fallback: 'Could not sign out. Please try again.'),
          );
    }
  }

  Future<void> updateEmployee(Employee employee, {File? newAvatarFile}) async {
    try {
      String? avatarUrl = employee.avatarUrl;
      if (newAvatarFile != null) {
        avatarUrl = await _ref.read(storageServiceProvider).uploadAvatar(
              uid: employee.id,
              file: newAvatarFile,
              oldAvatarUrl: employee.avatarUrl,
            );
      }

      await _ref.read(firestoreServiceProvider).updateEmployee(employee.id, {
        'firstName': employee.firstName,
        'lastName': employee.lastName,
        'phone': employee.phone,
        'email': employee.email,
        'avatarUrl': avatarUrl,
      });

      _ref.read(authMessageProvider.notifier).set('Profile Updated');
    } catch (e) {
      _ref.read(authMessageProvider.notifier).set(
            friendlyErrorMessage(e, fallback: 'Could not update profile. Please try again.'),
          );
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _ref.read(authServiceProvider).sendPasswordResetEmail(email);
      _ref.read(authMessageProvider.notifier).set('Password reset email sent to $email');
    } catch (e) {
      _ref.read(authMessageProvider.notifier).set(
            friendlyErrorMessage(e, fallback: 'Could not send reset email. Please try again.'),
          );
    }
  }

  void setMessage(String? message) {
    _ref.read(authMessageProvider.notifier).set(message);
  }
}
