import 'package:cloud_firestore/cloud_firestore.dart';

class MaterialRequestStatus {
  static const pending = 'pending';
  static const approved = 'approved';
  static const rejected = 'rejected';
  static const fulfilled = 'fulfilled';

  static const all = [pending, approved, rejected, fulfilled];

  static String label(String status) {
    switch (status) {
      case pending:
        return 'Pending';
      case approved:
        return 'Approved';
      case rejected:
        return 'Rejected';
      case fulfilled:
        return 'Fulfilled';
      default:
        return status;
    }
  }
}

class MaterialRequestItem {
  final String name;
  final String quantity;
  final String? unit;
  final String? note;

  const MaterialRequestItem({
    required this.name,
    required this.quantity,
    this.unit,
    this.note,
  });

  factory MaterialRequestItem.fromMap(Map<String, dynamic> map) {
    return MaterialRequestItem(
      name: map['name'] as String? ?? '',
      quantity: map['quantity'] as String? ?? '',
      unit: map['unit'] as String?,
      note: map['note'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {'name': name, 'quantity': quantity, 'unit': unit, 'note': note};
  }
}

class MaterialRequest {
  final String id;
  final String projectId;
  final String requestedById;
  final String requestedByName;
  final List<MaterialRequestItem> items;
  final List<String> photoUrls;
  final String status;
  final String? notes;
  final String? managerNote;
  final String? decidedById;
  final DateTime? decidedAt;
  final DateTime? createdAt;

  const MaterialRequest({
    required this.id,
    required this.projectId,
    required this.requestedById,
    required this.requestedByName,
    this.items = const [],
    this.photoUrls = const [],
    this.status = MaterialRequestStatus.pending,
    this.notes,
    this.managerNote,
    this.decidedById,
    this.decidedAt,
    this.createdAt,
  });

  factory MaterialRequest.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    return MaterialRequest(
      id: doc.id,
      projectId: data['projectId'] as String? ?? '',
      requestedById: data['requestedById'] as String? ?? '',
      requestedByName: data['requestedByName'] as String? ?? '',
      items: (data['items'] as List? ?? const [])
          .map((e) => MaterialRequestItem.fromMap(Map<String, dynamic>.from(e as Map)))
          .toList(),
      photoUrls: List<String>.from(data['photoUrls'] as List? ?? const []),
      status: data['status'] as String? ?? MaterialRequestStatus.pending,
      notes: data['notes'] as String?,
      managerNote: data['managerNote'] as String?,
      decidedById: data['decidedById'] as String?,
      decidedAt: (data['decidedAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'projectId': projectId,
      'requestedById': requestedById,
      'requestedByName': requestedByName,
      'items': items.map((e) => e.toMap()).toList(),
      'photoUrls': photoUrls,
      'status': status,
      'notes': notes,
      'managerNote': managerNote,
      'decidedById': decidedById,
      'decidedAt': decidedAt != null ? Timestamp.fromDate(decidedAt!) : null,
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }
}
