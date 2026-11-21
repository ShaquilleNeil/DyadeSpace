import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';

final authServiceProvider = Provider<AuthService>((ref) => AuthService());

/// One-time notice shown on the sign-in screen after a user
/// deletes their own account ("Your account was deleted.").
/// Set by the Settings screen just before signing out; the
/// sign-in screen shows it once and clears it.
final deletedAccountNoticeProvider = StateProvider<String?>((ref) => null);

/// The signed-in user profile, or null. Drives the whole app shell:
/// null -> sign-in screen; otherwise role-based home.
final currentUserProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authServiceProvider).watchCurrentUser(),
);

/// All user profiles (manager People screen + assignee pickers).
/// Gated on sign-in so signing out stays silent.
final allUsersProvider = StreamProvider<List<AppUser>>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null) return Stream.value([]);
  return ref.watch(authServiceProvider).allUsers();
});

/// Pending invites (People screen). The rules only let
/// admin/manager read other people's invites, so gate it the
/// same way - other roles get an empty list.
final pendingInvitesProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null || !me.isAdminOrManager) return Stream.value([]);
  return ref.watch(authServiceProvider).pendingInvites();
});
