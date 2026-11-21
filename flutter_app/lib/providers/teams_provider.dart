import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/team.dart';
import '../services/team_service.dart';
import 'auth_provider.dart';

final teamServiceProvider = Provider<TeamService>((ref) => TeamService());

/// All teams, ordered by name. Gated on sign-in so signing out
/// does not surface permission-denied errors - same pattern as
/// [sitesProvider].
final teamsProvider = StreamProvider<List<Team>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return FirebaseFirestore.instance
      .collection('teams')
      .orderBy('name')
      .snapshots()
      .map((snap) => snap.docs.map(Team.fromFirestore).toList());
});

/// teamId -> Team lookup, handy for cards and group headers.
final teamByIdProvider = Provider<Map<String, Team>>((ref) {
  final teams = ref.watch(teamsProvider).valueOrNull ?? [];
  return {for (final t in teams) t.id: t};
});
