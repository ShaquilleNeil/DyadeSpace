import 'package:cloud_firestore/cloud_firestore.dart';

/// A named group of crew members, e.g. "Maple Court crew".
/// Stored in the top-level `teams` collection.
///
/// No colour is stored on the doc: the UI derives it from the team
/// id with [AppTokens.siteTagColorFor], exactly like sites do, so a
/// team keeps its colour everywhere without extra data.
class Team {
  final String id;
  final String name;
  final List<String> memberIds;
  final String createdBy;
  final DateTime? createdAt;

  const Team({
    required this.id,
    required this.name,
    this.memberIds = const [],
    this.createdBy = '',
    this.createdAt,
  });

  factory Team.fromFirestore(DocumentSnapshot doc) {
    return Team.fromMap(doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory Team.fromMap(String id, Map<String, dynamic> map) {
    return Team(
      id: id,
      name: map['name'] as String? ?? '',
      memberIds: (map['memberIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      createdBy: map['createdBy'] as String? ?? '',
      createdAt: _date(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'memberIds': memberIds,
      'createdBy': createdBy,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
    };
  }

  Team copyWith({
    String? name,
    List<String>? memberIds,
    String? createdBy,
    DateTime? createdAt,
  }) {
    return Team(
      id: id,
      name: name ?? this.name,
      memberIds: memberIds ?? this.memberIds,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

/// Defensive Timestamp parse, mirroring TaskItem: a missing or
/// not-yet-resolved (serverTimestamp pending) value reads as null.
DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : null;
