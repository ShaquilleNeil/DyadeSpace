import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : null;

/// One subdivision of a site — an apartment / unit inside a
/// building, e.g. "502" at 5360 Macdonald. Stored in the
/// top-level `units` collection. A site has units iff it has at
/// least one unit doc; a site with no units works exactly as
/// today, and a task with no unitId is an ordinary site-level
/// task. Mirrors [Stage]: site-scoped, ordered, managed by
/// admins/managers, linked from tasks via a nullable `unitId`.
/// A unit has no lifecycle of its own (no start/skip): it is a
/// grouping, never a visibility filter — its tasks surface in
/// My Day / Today / Board exactly like site-level tasks.
class Unit {
  final String id;
  final String siteId;

  /// The unit's label, e.g. "502", "A", "Penthouse".
  final String name;

  /// 1-based position among the site's units (Unit 1, Unit 2…).
  final int order;
  final DateTime? createdAt;

  const Unit({
    required this.id,
    required this.siteId,
    required this.name,
    this.order = 0,
    this.createdAt,
  });

  factory Unit.fromFirestore(DocumentSnapshot doc) {
    return Unit.fromMap(doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory Unit.fromMap(String id, Map<String, dynamic> map) {
    return Unit(
      id: id,
      siteId: map['siteId'] as String? ?? '',
      name: map['name'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      createdAt: _date(map['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'siteId': siteId,
      'name': name,
      'order': order,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
    };
  }

  Unit copyWith({String? name, int? order}) {
    return Unit(
      id: id,
      siteId: siteId,
      name: name ?? this.name,
      order: order ?? this.order,
      createdAt: createdAt,
    );
  }
}
