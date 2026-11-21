import 'package:cloud_firestore/cloud_firestore.dart';

/// Timestamps arrive as Firestore Timestamps from direct reads
/// and as ISO strings from the `getClientShare` callable.
DateTime? _date(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is String) return DateTime.tryParse(v);
  return null;
}

/// One client share link: a random, unguessable token that
/// opens a read-only progress view of one site, with no app
/// or login needed (SaaS plan §10, priority #3).
///
/// The token IS the doc id in the top-level `clientShares`
/// collection, so the public view can fetch it with a single
/// unauthenticated `get` — the token is the capability, and
/// nothing else in Firestore is opened to the public (see
/// ClientShareService: the progress itself is served by the
/// `getClientShare` callable, which validates the token
/// server-side). Revoking flips [revoked]; the old link then
/// loads nothing. Regenerating revokes the old token and
/// creates a fresh one — one active link per site.
class ClientShare {
  final String token;
  final String siteId;
  final String siteName;
  final String createdBy;
  final DateTime? createdAt;
  final bool revoked;
  final DateTime? revokedAt;

  const ClientShare({
    required this.token,
    required this.siteId,
    required this.siteName,
    required this.createdBy,
    this.createdAt,
    this.revoked = false,
    this.revokedAt,
  });

  factory ClientShare.fromFirestore(DocumentSnapshot doc) {
    return ClientShare.fromMap(
        doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory ClientShare.fromMap(String token, Map<String, dynamic> map) {
    return ClientShare(
      token: token,
      siteId: map['siteId'] as String? ?? '',
      siteName: map['siteName'] as String? ?? '',
      createdBy: map['createdBy'] as String? ?? '',
      createdAt: _date(map['createdAt']),
      revoked: map['revoked'] as bool? ?? false,
      revokedAt: _date(map['revokedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'siteId': siteId,
      'siteName': siteName,
      'createdBy': createdBy,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'revoked': revoked,
      'revokedAt': revokedAt,
    };
  }

  ClientShare copyWith({bool? revoked, DateTime? revokedAt}) {
    return ClientShare(
      token: token,
      siteId: siteId,
      siteName: siteName,
      createdBy: createdBy,
      createdAt: createdAt,
      revoked: revoked ?? this.revoked,
      revokedAt: revokedAt ?? this.revokedAt,
    );
  }
}

/// One roadmap stage in the public progress payload: name,
/// derived status, and done/total task counts. Only
/// public-safe fields — no assignees, no notes.
class ClientStageProgress {
  final String id;
  final String name;
  final int order;
  final String status;
  final int done;
  final int total;

  const ClientStageProgress({
    required this.id,
    required this.name,
    required this.order,
    required this.status,
    required this.done,
    required this.total,
  });

  factory ClientStageProgress.fromMap(Map<String, dynamic> map) {
    return ClientStageProgress(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      order: (map['order'] as num?)?.toInt() ?? 0,
      status: map['status'] as String? ?? '',
      done: (map['done'] as num?)?.toInt() ?? 0,
      total: (map['total'] as num?)?.toInt() ?? 0,
    );
  }
}

/// One task in the public progress payload: title, status and
/// (for finished work) its completion photo URLs. No assignees,
/// no notes, no internal fields.
class ClientTaskProgress {
  final String id;
  final String title;
  final String status;
  final String? stageId;
  final String? unitName;
  final DateTime? finishedAt;
  final List<String> photoUrls;

  const ClientTaskProgress({
    required this.id,
    required this.title,
    required this.status,
    this.stageId,
    this.unitName,
    this.finishedAt,
    this.photoUrls = const [],
  });

  factory ClientTaskProgress.fromMap(Map<String, dynamic> map) {
    return ClientTaskProgress(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? '',
      status: map['status'] as String? ?? '',
      stageId: map['stageId'] as String?,
      unitName: map['unitName'] as String?,
      finishedAt: _date(map['finishedAt']),
      photoUrls: (map['photoUrls'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
    );
  }
}

/// The whole public payload for one share token, as returned
/// by the `getClientShare` callable: the site, its roadmap
/// stages, and its tasks. The screen renders only this —
/// it never reads the site/tasks collections directly, so an
/// unauthenticated visitor cannot reach anything beyond the
/// one shared site.
class ClientSiteProgress {
  final String siteId;
  final String siteName;
  final String siteAddress;
  final List<ClientStageProgress> stages;
  final List<ClientTaskProgress> tasks;

  const ClientSiteProgress({
    required this.siteId,
    required this.siteName,
    required this.siteAddress,
    required this.stages,
    required this.tasks,
  });

  factory ClientSiteProgress.fromMap(Map<String, dynamic> map) {
    return ClientSiteProgress(
      siteId: map['siteId'] as String? ?? '',
      siteName: map['siteName'] as String? ?? '',
      siteAddress: map['siteAddress'] as String? ?? '',
      stages: (map['stages'] as List?)
              ?.map((e) => ClientStageProgress.fromMap(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
      tasks: (map['tasks'] as List?)
              ?.map((e) => ClientTaskProgress.fromMap(
                  Map<String, dynamic>.from(e as Map)))
              .toList() ??
          const [],
    );
  }

  /// Finished tasks, most recently finished first.
  List<ClientTaskProgress> get recentlyCompleted {
    final done = tasks.where((t) => t.status == 'done').toList();
    done.sort((a, b) {
      final fa = a.finishedAt;
      final fb = b.finishedAt;
      if (fa == null && fb == null) return 0;
      if (fa == null) return 1;
      if (fb == null) return -1;
      return fb.compareTo(fa);
    });
    return done;
  }
}
