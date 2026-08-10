import 'package:cloud_firestore/cloud_firestore.dart';

class Project {
  final String id;
  final String name;
  final String? description;
  final String? address;
  final String? photoUrl;
  final DateTime? createdAt;
  final List<String> memberIds;

  const Project({
    required this.id,
    required this.name,
    this.description,
    this.address,
    this.photoUrl,
    this.createdAt,
    this.memberIds = const [],
  });

  factory Project.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return Project(
      id: doc.id,
      name: data['name'] as String? ?? '',
      description: data['description'] as String?,
      address: data['address'] as String?,
      photoUrl: data['photoUrl'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      memberIds: List<String>.from(data['memberIds'] as List? ?? const []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'address': address,
      'photoUrl': photoUrl,
      'createdAt': createdAt != null
          ? Timestamp.fromDate(createdAt!)
          : FieldValue.serverTimestamp(),
      'memberIds': memberIds,
    };
  }
}
