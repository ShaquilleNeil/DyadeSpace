import 'package:cloud_firestore/cloud_firestore.dart';

/// A chat conversation, stored in the top-level `conversations`
/// collection. Three kinds:
/// - 'dm': a private one-to-one conversation (exactly 2 participants).
///   Doc id is deterministic — `dm_<smallerUid>_<largerUid>` — so a
///   pair can only ever have one DM, however it is opened.
/// - 'team': one channel per team. Doc id is deterministic —
///   `team_<teamId>`. participantIds is the team members plus every
///   admin/manager (admins/managers see every team channel);
///   [ChatService.ensureTeamChannel] keeps the list fresh.
/// - 'broadcast': one conversation per recipient, created by an
///   admin/manager sending to selected employees. A reply comes
///   back as a 1:1 DM to the sender, not to the whole group —
///   the WhatsApp broadcast-list model.
///
/// `unreadBy` is the per-conversation unread signal (the list
/// badge counts conversations where it holds my uid). It is set
/// to every participant except the sender on each message, and
/// cleared for a user when they open the chat.
class Conversation {
  final String id;
  final String type; // 'dm' | 'team' | 'broadcast'
  final List<String> participantIds;
  final String? teamId;

  /// Team channels store the team name here (kept fresh by
  /// ensureTeamChannel); DMs and broadcasts leave it empty and
  /// the UI resolves the other person's name live.
  final String? title;
  final String createdBy;
  final DateTime? createdAt;

  /// Last message preview + who sent it, for the list row.
  final String lastMessage;
  final String? lastSenderId;

  /// Sort key for the list (bumped on every message).
  final DateTime? updatedAt;

  /// Uids with unread messages in this conversation.
  final List<String> unreadBy;

  const Conversation({
    required this.id,
    required this.type,
    this.participantIds = const [],
    this.teamId,
    this.title,
    this.createdBy = '',
    this.createdAt,
    this.lastMessage = '',
    this.lastSenderId,
    this.updatedAt,
    this.unreadBy = const [],
  });

  bool get isDm => type == 'dm';
  bool get isTeam => type == 'team';
  bool get isBroadcast => type == 'broadcast';

  bool isUnreadBy(String uid) => unreadBy.contains(uid);

  factory Conversation.fromFirestore(DocumentSnapshot doc) {
    return Conversation.fromMap(
        doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory Conversation.fromMap(String id, Map<String, dynamic> map) {
    return Conversation(
      id: id,
      type: map['type'] as String? ?? 'dm',
      participantIds: (map['participantIds'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      teamId: map['teamId'] as String?,
      title: map['title'] as String?,
      createdBy: map['createdBy'] as String? ?? '',
      createdAt: _date(map['createdAt']),
      lastMessage: map['lastMessage'] as String? ?? '',
      lastSenderId: map['lastSenderId'] as String?,
      updatedAt: _date(map['updatedAt']),
      unreadBy: (map['unreadBy'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'participantIds': participantIds,
      'teamId': teamId,
      'title': title,
      'createdBy': createdBy,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
      'lastMessage': lastMessage,
      'lastSenderId': lastSenderId,
      'updatedAt': updatedAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(updatedAt!),
      'unreadBy': unreadBy,
    };
  }

  Conversation copyWith({
    String? type,
    List<String>? participantIds,
    String? teamId,
    String? title,
    String? createdBy,
    DateTime? createdAt,
    String? lastMessage,
    String? lastSenderId,
    DateTime? updatedAt,
    List<String>? unreadBy,
  }) {
    return Conversation(
      id: id,
      type: type ?? this.type,
      participantIds: participantIds ?? this.participantIds,
      teamId: teamId ?? this.teamId,
      title: title ?? this.title,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      lastMessage: lastMessage ?? this.lastMessage,
      lastSenderId: lastSenderId ?? this.lastSenderId,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadBy: unreadBy ?? this.unreadBy,
    );
  }
}

/// One message in a conversation, stored in
/// conversations/{conversationId}/messages. Text plus an
/// optional media attachment: a photo, a video, or a voice
/// note stored under chatMedia/<conversationId>/. Text stays
/// optional — a message may be media-only.
///
/// `readBy` holds the uids that have seen this message (the
/// sender is in it from the start). The conversation doc's
/// `unreadBy` is the cheap unread signal for the list; `readBy`
/// is the per-message record.
class ChatMessage {
  final String id;
  final String senderId;

  /// Display name, snapshotted at send time so the thread still
  /// reads well if the profile is renamed later.
  final String senderName;
  final String text;
  final List<String> readBy;
  final DateTime? createdAt;

  /// Media attachment, or null for a text-only message.
  final String? mediaUrl;

  /// 'image' | 'video' | 'audio' — null when [mediaUrl] is null.
  final String? mediaType;

  /// Audio / video length in seconds (null for photos and for
  /// older media sent before the field existed).
  final int? mediaDurationSeconds;

  const ChatMessage({
    required this.id,
    required this.senderId,
    this.senderName = '',
    this.text = '',
    this.readBy = const [],
    this.createdAt,
    this.mediaUrl,
    this.mediaType,
    this.mediaDurationSeconds,
  });

  bool get hasMedia => mediaUrl != null && mediaUrl!.isNotEmpty;
  bool get isImage => mediaType == 'image';
  bool get isVideo => mediaType == 'video';
  bool get isAudio => mediaType == 'audio';

  bool readByUser(String uid) => readBy.contains(uid);

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    return ChatMessage.fromMap(
        doc.id, doc.data() as Map<String, dynamic>? ?? {});
  }

  factory ChatMessage.fromMap(String id, Map<String, dynamic> map) {
    return ChatMessage(
      id: id,
      senderId: map['senderId'] as String? ?? '',
      senderName: map['senderName'] as String? ?? '',
      text: map['text'] as String? ?? '',
      readBy: (map['readBy'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      createdAt: _date(map['createdAt']),
      mediaUrl: map['mediaUrl'] as String?,
      mediaType: map['mediaType'] as String?,
      mediaDurationSeconds: (map['mediaDurationSeconds'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'senderId': senderId,
      'senderName': senderName,
      'text': text,
      'readBy': readBy,
      'createdAt': createdAt == null
          ? FieldValue.serverTimestamp()
          : Timestamp.fromDate(createdAt!),
      'mediaUrl': mediaUrl,
      'mediaType': mediaType,
      'mediaDurationSeconds': mediaDurationSeconds,
    };
  }
}

/// Defensive Timestamp parse, mirroring TaskItem: a missing or
/// not-yet-resolved (serverTimestamp pending) value reads as null.
DateTime? _date(dynamic v) => v is Timestamp ? v.toDate() : null;
