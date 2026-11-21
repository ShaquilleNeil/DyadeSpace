import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/team.dart';

/// All Firestore access for teams (named groups of crew members).
/// Mirrors [TaskService]: the service owns the writes, providers
/// and screens read through it.
class TeamService {
  final FirebaseFirestore _db;
  TeamService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _teams =>
      _db.collection('teams');

  /// Creates a team and returns its new doc id. [toMap] stamps
  /// `createdAt` with the server timestamp on create.
  Future<String> createTeam({
    required String name,
    required List<String> memberIds,
    required String createdBy,
  }) async {
    final team = Team(
      id: '',
      name: name,
      memberIds: memberIds,
      createdBy: createdBy,
    );
    final ref = await _teams.add(team.toMap());
    return ref.id;
  }

  Future<void> updateTeam(Team team) {
    return _teams.doc(team.id).update(team.toMap());
  }

  Future<void> deleteTeam(String id) => _teams.doc(id).delete();

  Future<void> addMember(String teamId, String userId) {
    return _teams.doc(teamId).update({
      'memberIds': FieldValue.arrayUnion([userId]),
    });
  }

  Future<void> removeMember(String teamId, String userId) {
    return _teams.doc(teamId).update({
      'memberIds': FieldValue.arrayRemove([userId]),
    });
  }
}
