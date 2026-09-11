import 'package:firebase_auth/firebase_auth.dart';

/// Maps a thrown error to copy a user can act on, instead of a raw
/// `[firebase_auth/wrong-password] The password is invalid...` string.
/// Covers Firebase Auth, Firestore, and Storage exceptions; anything else
/// falls back to a caller-supplied, context-appropriate message.
String friendlyErrorMessage(
  Object error, {
  String fallback = 'Something went wrong. Please try again.',
}) {
  if (error is FirebaseAuthException) {
    switch (error.code) {
      case 'invalid-credential':
      case 'wrong-password':
      case 'user-not-found':
        return 'Incorrect email or password.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Contact your manager.';
      case 'email-already-in-use':
        return 'An account already exists for that email.';
      case 'weak-password':
        return 'Password should be at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Please check your connection and try again.';
      default:
        return fallback;
    }
  }
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
      case 'unauthorized':
        return "You don't have permission to do that.";
      case 'unavailable':
      case 'deadline-exceeded':
        return 'Network error. Please check your connection and try again.';
      case 'not-found':
      case 'object-not-found':
        return 'That item could not be found — it may have been deleted.';
      case 'unauthenticated':
        return 'Please sign in and try again.';
      case 'already-exists':
        return 'An account already exists for that email.';
      case 'invalid-argument':
        return 'Please check the details and try again.';
      default:
        return fallback;
    }
  }
  return fallback;
}
