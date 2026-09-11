import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_providers.dart';

/// Admin-only: invites a new staff member by email via the `inviteStaff`
/// Cloud Function (creates the Auth user + `employees/{uid}` doc server-side,
/// since self-signup can only ever create a plain client account).
final inviteControllerProvider = Provider<InviteController>((ref) => InviteController(ref));

/// Thrown when the staff account was created successfully but the
/// follow-up password-reset email couldn't be sent — distinct from a failed
/// invite so the caller can tell the admin the account does exist.
class InviteEmailFailedException implements Exception {
  InviteEmailFailedException(this.cause);

  final Object cause;
}

class InviteController {
  InviteController(this._ref);

  final Ref _ref;

  Future<void> inviteStaff({
    required String firstName,
    required String lastName,
    required String email,
    required String role,
    required List<String> projectIds,
  }) async {
    final callable = _ref.read(firebaseFunctionsProvider).httpsCallable('inviteStaff');
    await callable.call<Map<String, dynamic>>({
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'role': role,
      'projectIds': projectIds,
    });

    // Let the invitee set their own password via Firebase's hosted email —
    // nothing sensitive is ever relayed through the admin. The account is
    // already created at this point, so a failure here is reported
    // separately rather than as an overall invite failure: re-inviting the
    // same email would now fail with "already exists", so the recovery
    // path is telling the invitee to use "Forgot password?" on login.
    try {
      await _ref.read(authServiceProvider).sendPasswordResetEmail(email);
    } catch (e) {
      throw InviteEmailFailedException(e);
    }
  }
}
