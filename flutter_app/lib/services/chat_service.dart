import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/chat.dart';
import '../models/team.dart';

/// Thrown when a chat Firestore call fails (for example a
/// permission-denied from the rules). Screens catch this and
/// show a plain-language message instead of letting the
/// exception escape silently.
class ChatException implements Exception {
  final String message;
  const ChatException(this.message);
  @override
  String toString() => message;
}

/// All Firestore access for in-app chat (DMs, team channels,
/// broadcasts). Mirrors [TaskService]: the service owns the
/// writes, providers and screens read through it.
///
/// Conversation ids are deterministic where a conversation must
/// be unique: DMs are `dm_<smallerUid>_<largerUid>`, team
/// channels are `team_<teamId>`. Broadcasts get an auto id per
/// recipient (one conversation per recipient, so a reply comes
/// back 1:1 to the sender).
class ChatService {
  final FirebaseFirestore _db;
  ChatService({FirebaseFirestore? db}) : _db = db ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _conversations =>
      _db.collection('conversations');

  CollectionReference<Map<String, dynamic>> _messages(String conversationId) =>
      _conversations.doc(conversationId).collection('messages');

  /// Deterministic DM id for a pair, so a pair can only ever
  /// have one DM however it is opened.
  static String dmIdFor(String a, String b) {
    final ids = [a, b]..sort();
    return 'dm_${ids[0]}_${ids[1]}';
  }

  /// Conversations I am in, newest activity first. No `orderBy`
  /// on the query (no composite index) — the sort happens in
  /// Dart, same pattern as the notifications provider.
  Stream<List<Conversation>> watchConversations(String myId) {
    return _conversations
        .where('participantIds', arrayContains: myId)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(Conversation.fromFirestore).toList()
        ..sort((a, b) => (b.updatedAt ?? DateTime(1970))
            .compareTo(a.updatedAt ?? DateTime(1970)));
      return list;
    });
  }

  /// One conversation by id.
  Stream<Conversation?> watchConversation(String conversationId) {
    return _conversations.doc(conversationId).snapshots().map(
        (doc) => doc.exists ? Conversation.fromFirestore(doc) : null);
  }

  /// Messages of one conversation, oldest first.
  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return _messages(conversationId)
        .orderBy('createdAt')
        .snapshots()
        .map((snap) => snap.docs.map(ChatMessage.fromFirestore).toList());
  }

  /// Finds the DM for a pair, creating it when missing. The
  /// deterministic id makes concurrent creates harmless (same
  /// doc, same content). A rules failure surfaces as a
  /// [ChatException] instead of an unhandled Firestore error.
  Future<String> findOrCreateDm(String meId, String otherId) async {
    final id = dmIdFor(meId, otherId);
    final ref = _conversations.doc(id);
    try {
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set(Conversation(
          id: id,
          type: 'dm',
          participantIds: [meId, otherId],
          createdBy: meId,
        ).toMap());
      }
    } on FirebaseException catch (e) {
      throw ChatException('findOrCreateDm $id failed: ${e.code}');
    }
    return id;
  }

  /// Makes sure a team's channel exists and its participants
  /// match the team's current members plus every admin/manager
  /// (admins/managers see every team channel). Idempotent —
  /// safe to call every time the Chats tab opens. A rules
  /// failure surfaces as a [ChatException] so the caller can
  /// retry later instead of throwing unhandled.
  Future<String> ensureTeamChannel({
    required Team team,
    required List<String> adminManagerIds,
    required String createdBy,
  }) async {
    final id = 'team_${team.id}';
    final participants = <String>{
      ...team.memberIds,
      ...adminManagerIds,
    }.toList();
    final ref = _conversations.doc(id);
    try {
      final snap = await ref.get();
      if (!snap.exists) {
        await ref.set(Conversation(
          id: id,
          type: 'team',
          participantIds: participants,
          teamId: team.id,
          title: team.name,
          createdBy: createdBy,
        ).toMap());
      } else {
        await ref.set({
          'participantIds': participants,
          'title': team.name,
        }, SetOptions(merge: true));
      }
    } on FirebaseException catch (e) {
      throw ChatException('ensureTeamChannel $id failed: ${e.code}');
    }
    return id;
  }

  /// Sends one message: the message doc plus the conversation
  /// preview, timestamp, and unread flags — everyone except
  /// the sender is marked unread. A message may be media-only
  /// ([mediaUrl] set, [text] empty): then the list preview is
  /// [previewLabel] (e.g. "[Photo]", localized by the caller).
  Future<void> sendMessage({
    required String conversationId,
    required String senderId,
    required String senderName,
    required String text,
    String? mediaUrl,
    String? mediaType,
    int? mediaDurationSeconds,
    String? previewLabel,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty && mediaUrl == null) return;
    final DocumentSnapshot<Map<String, dynamic>> convSnap;
    try {
      convSnap = await _conversations.doc(conversationId).get();
    } on FirebaseException catch (e) {
      throw ChatException('sendMessage $conversationId failed: ${e.code}');
    }
    if (!convSnap.exists) {
      // Never swallow this: the composer clears only on
      // success, so a throw keeps the text and shows the
      // failure instead of silently dropping the message.
      throw ChatException(
          'sendMessage $conversationId failed: conversation not found');
    }
    final conv = Conversation.fromFirestore(convSnap);
    final unread = conv.participantIds.where((u) => u != senderId).toList();
    final preview =
        trimmed.isNotEmpty ? trimmed : (previewLabel ?? '');
    final batch = _db.batch();
    batch.set(
      _messages(conversationId).doc(),
      ChatMessage(
        id: '',
        senderId: senderId,
        senderName: senderName,
        text: trimmed,
        readBy: [senderId],
        mediaUrl: mediaUrl,
        mediaType: mediaType,
        mediaDurationSeconds: mediaDurationSeconds,
      ).toMap(),
    );
    batch.update(_conversations.doc(conversationId), {
      'lastMessage': preview,
      'lastSenderId': senderId,
      'updatedAt': FieldValue.serverTimestamp(),
      'unreadBy': unread,
    });
    await batch.commit();
  }

  /// Broadcast (admin/manager only — enforced by the rules):
  /// one 'broadcast' conversation per recipient, each with the
  /// message already in it. Replies come back 1:1 to the
  /// sender, never to the group. Returns which recipients got
  /// it and which failed.
  ///
  /// Recipients are deduplicated first (the same uid twice
  /// used to get two conversations). A failure for one
  /// recipient is recorded in [BroadcastResult.failedIds] and
  /// the send continues with the rest — it never throws away
  /// the recipients that already got it, and never leaves the
  /// later ones unsent with no record.
  ///
  /// Two writes per recipient, in order: the conversation doc
  /// first, then its first message. The message-create rule
  /// reads the parent conversation doc, and rules `get()` only
  /// sees committed state — creating both in one batch would
  /// deny the message because the parent does not exist yet.
  Future<BroadcastResult> sendBroadcast({
    required String senderId,
    required String senderName,
    required List<String> recipientIds,
    required String text,
    String? mediaUrl,
    String? mediaType,
    int? mediaDurationSeconds,
    String? previewLabel,
  }) async {
    final trimmed = text.trim();
    if ((trimmed.isEmpty && mediaUrl == null) || recipientIds.isEmpty) {
      return const BroadcastResult();
    }
    final preview =
        trimmed.isNotEmpty ? trimmed : (previewLabel ?? '');
    // Dedupe, preserving order; the sender never gets their
    // own broadcast.
    final uniqueRecipients = <String>{
      for (final id in recipientIds)
        if (id != senderId) id,
    }.toList();
    final sentIds = <String>[];
    final failedIds = <String>[];
    for (final recipientId in uniqueRecipients) {
      final convRef = _conversations.doc();
      try {
        await convRef.set(
          Conversation(
            id: convRef.id,
            type: 'broadcast',
            participantIds: [senderId, recipientId],
            createdBy: senderId,
            lastMessage: preview,
            lastSenderId: senderId,
            unreadBy: [recipientId],
          ).toMap(),
        );
        await convRef.collection('messages').doc().set(
              ChatMessage(
                id: '',
                senderId: senderId,
                senderName: senderName,
                text: trimmed,
                readBy: [senderId],
                mediaUrl: mediaUrl,
                mediaType: mediaType,
                mediaDurationSeconds: mediaDurationSeconds,
              ).toMap(),
            );
        sentIds.add(convRef.id);
      } on FirebaseException {
        // Record and continue: earlier recipients keep the
        // message, later ones still get their turn.
        failedIds.add(recipientId);
      }
    }
    return BroadcastResult(sentIds: sentIds, failedIds: failedIds);
  }

  /// Marks a conversation read for [myId]: clears my uid from
  /// the conversation's unread list and adds me to `readBy` on
  /// the messages I have seen. No 100-message cap: receipts
  /// are written in chunks of 499 message updates per batch
  /// (a batch holds at most 500 writes, and the first batch
  /// also carries the conversation update), so a long thread
  /// is fully marked read instead of stopping at 100.
  /// Fire-and-forget by design: a failure is swallowed here
  /// (the flag simply stays until the chat is opened again)
  /// so a read receipt can never throw an unhandled error
  /// into the UI.
  Future<void> markRead({
    required String conversationId,
    required String myId,
    required List<ChatMessage> messages,
  }) async {
    try {
      final unread = messages
          .where((m) => m.senderId != myId && !m.readByUser(myId))
          .toList();
      if (unread.isEmpty) {
        // Still clear the list flag — a message could have been
        // deleted server-side, or the flag set without a message.
        await _conversations.doc(conversationId).update({
          'unreadBy': FieldValue.arrayRemove([myId]),
        });
        return;
      }
      // 499 per batch: the first batch also updates the
      // conversation doc (1 + 499 = the 500-write limit).
      for (var i = 0; i < unread.length; i += 499) {
        final batch = _db.batch();
        if (i == 0) {
          batch.update(_conversations.doc(conversationId), {
            'unreadBy': FieldValue.arrayRemove([myId]),
          });
        }
        for (final m in unread.skip(i).take(499)) {
          batch.update(_messages(conversationId).doc(m.id), {
            'readBy': FieldValue.arrayUnion([myId]),
          });
        }
        await batch.commit();
      }
    } on FirebaseException {
      // Swallowed on purpose — see the doc comment above.
      return;
    }
  }
}

/// The outcome of a broadcast: which recipients got the
/// message and which did not. A failed recipient never aborts
/// the rest — the caller reports the failure (and can retry
/// just the failed ids) instead of silently half-sending.
class BroadcastResult {
  final List<String> sentIds;
  final List<String> failedIds;
  const BroadcastResult({this.sentIds = const [], this.failedIds = const []});

  bool get allSent => failedIds.isEmpty;
  bool get noneSent => sentIds.isEmpty;
}
