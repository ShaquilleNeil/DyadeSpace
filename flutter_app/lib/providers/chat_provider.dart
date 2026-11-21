import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/chat.dart';
import '../services/chat_service.dart';
import 'auth_provider.dart';

final chatServiceProvider = Provider<ChatService>((ref) => ChatService());

/// Conversations the signed-in user is in, newest activity
/// first. Gated on sign-in so signing out stays silent.
final conversationsProvider = StreamProvider<List<Conversation>>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null) return Stream.value([]);
  return ref.watch(chatServiceProvider).watchConversations(me.id);
});

/// One conversation by id, or null while it loads / when it is
/// gone. The chat screen falls back to the Conversation passed
/// in from the list.
final conversationProvider =
    StreamProvider.family<Conversation?, String>((ref, conversationId) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null) return Stream.value(null);
  return ref.watch(chatServiceProvider).watchConversation(conversationId);
});

/// Messages of one conversation, oldest first. Gated on
/// sign-in like the other streams.
final chatMessagesProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, conversationId) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null) return Stream.value([]);
  return ref.watch(chatServiceProvider).watchMessages(conversationId);
});

/// Number of conversations with unread messages for the
/// signed-in user — the badge on the Chats tab. Derived from
/// the conversations stream (two arrayContains filters are not
/// allowed in one Firestore query, so the unread filter runs
/// in Dart).
final unreadChatsProvider = Provider<int>((ref) {
  final me = ref.watch(currentUserProvider).valueOrNull;
  if (me == null) return 0;
  final conversations = ref.watch(conversationsProvider).valueOrNull ?? [];
  return conversations.where((c) => c.isUnreadBy(me.id)).length;
});
