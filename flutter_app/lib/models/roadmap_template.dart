import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : null;

/// One task inside a saved roadmap template: just the
/// definition — title, notes, materials. No assignee, no
/// status, no dates: applying or copying a template always
/// creates fresh To do, unassigned tasks.
class TemplateTask {
  final String title;
  final String notes;
  final List<String> materials;

  const TemplateTask({
    required this.title,
    this.notes = '',
    this.materials = const [],
  });

  factory TemplateTask.fromMap(Map<String, dynamic> map) {
    return TemplateTask(
      title: map['title'] as String? ?? '',
      notes: map['notes'] as String? ?? '',
      materials: List<String>.from(map['materials'] as List? ?? []),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'notes': notes,
      'materials': materials,
    };
  }
}

/// One stage inside a saved roadmap template, with the tasks
/// it should already contain.
class TemplateStage {
  final String name;
  final int order;
  final List<TemplateTask> tasks;

  const TemplateStage({
    required this.name,
    this.order = 0,
    this.tasks = const [],
  });

  factory TemplateStage.fromMap(Map<String, dynamic> map) {
    final tasks = map['tasks'];
    return TemplateStage(
      name: map['name'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      tasks: tasks is List
          ? tasks
              .whereType<Map<String, dynamic>>()
              .map(TemplateTask.fromMap)
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'order': order,
      'tasks': tasks.map((t) => t.toMap()).toList(),
    };
  }
}

/// A saved site roadmap, reusable as a starting point: stored
/// in the top-level `roadmap_templates` collection as one doc
/// (name + ordered stages with their task definitions). Created
/// from a site's roadmap ("Save as template") and applied from
/// the create-roadmap dialog; copying a roadmap to another site
/// builds the same shape in memory without saving it.
class RoadmapTemplate {
  final String id;
  final String name;
  final String createdBy;
  final DateTime? createdAt;
  final List<TemplateStage> stages;

  const RoadmapTemplate({
    required this.id,
    required this.name,
    required this.createdBy,
    this.createdAt,
    this.stages = const [],
  });

  factory RoadmapTemplate.fromFirestore(DocumentSnapshot doc) {
    return RoadmapTemplate.fromMap(
        doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory RoadmapTemplate.fromMap(String id, Map<String, dynamic> map) {
    final stages = map['stages'];
    return RoadmapTemplate(
      id: id,
      name: map['name'] as String? ?? '',
      createdBy: map['createdBy'] as String? ?? '',
      createdAt: _date(map['createdAt']),
      stages: stages is List
          ? stages
              .whereType<Map<String, dynamic>>()
              .map(TemplateStage.fromMap)
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'createdBy': createdBy,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
      'stages': stages.map((s) => s.toMap()).toList(),
    };
  }
}
