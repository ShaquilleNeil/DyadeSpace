import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../l10n/app_strings.dart';
import '../models/app_user.dart';
import '../models/chat.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/teams_provider.dart';
import '../services/chat_media_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/chat_media_bubble.dart';
import '../widgets/empty_state.dart';
import '../widgets/member_tile.dart';
import '../widgets/photo_viewer.dart';
import '../widgets/skeleton_card.dart';
import '../widgets/voice_record_button.dart';
import 'video_player_screen.dart';
import 'worker_profile_screen.dart';

/// One conversation: message bubbles + send box. Photos,
/// videos and voice notes attach from the send box; images
/// open the shared photo viewer, videos the in-app player.
/// Opens mark the conversation read for me (conversation
/// flag + per-message readBy) whenever unread messages are
/// on screen.
class ChatScreen extends ConsumerStatefulWidget {
  final String conversationId;

  /// The conversation as the list saw it — the header falls
  /// back to this while the live doc loads. Null when opened
  /// straight from a DM lookup: the live doc (created first by
  /// findOrCreateDm) fills it in.
  final Conversation? conversation;

  const ChatScreen({
    super.key,
    required this.conversationId,
    this.conversation,
  });

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ChatMediaService _mediaService = ChatMediaService();
  bool _sending = false;

  /// A media upload is in flight (photo/video/voice note).
  bool _sendingMedia = false;

  /// 0.0–1.0 while uploading; null when idle. A failed upload
  /// offers a retry in a snackbar — the file is never
  /// silently dropped.
  double? _uploadProgress;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Pick an attachment from the (+) sheet, upload it, then
  /// send the message. A cancelled upload or a cancelled
  /// pick just returns — nothing is sent.
  Future<void> _pickMedia(AppUser me, AppStrings s) async {
    final choice = await showAttachSheet(context, s);
    if (choice == null || !mounted) return;
    XFile? file;
    var mediaType = 'image';
    try {
      switch (choice) {
        case 'camera-photo':
          file = await _mediaService.pickPhoto(ImageSource.camera);
          break;
        case 'gallery-photo':
          file = await _mediaService.pickPhoto(ImageSource.gallery);
          break;
        case 'camera-video':
          file = await _mediaService.pickVideo(ImageSource.camera);
          mediaType = 'video';
          break;
        case 'gallery-video':
          file = await _mediaService.pickVideo(ImageSource.gallery);
          mediaType = 'video';
          break;
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.mediaUploadFailed)),
      );
      return;
    }
    if (file == null || !mounted) return;
    if (kIsWeb) {
      // Web: the picker returns a blob URL, not a local file —
      // File() cannot read it. Read the bytes (works on both
      // platforms) and upload those instead. Video duration is
      // skipped on web (VideoPlayerController.file is dart:io).
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      await _uploadAndSend(
        me: me,
        s: s,
        localPath: file.path,
        mediaType: mediaType,
        bytes: bytes,
        filename: file.name,
      );
      return;
    }
    int? duration;
    if (mediaType == 'video') {
      duration = await _mediaService.videoDurationSeconds(file.path);
    }
    await _uploadAndSend(
      me: me,
      s: s,
      localPath: file.path,
      mediaType: mediaType,
      durationSeconds: duration,
    );
  }

  /// Uploads a local media file and sends the message carrying
  /// its URL. Shows progress and, on failure, a retry snackbar.
  /// [bytes]/[filename] is the web path: when set, the bytes are
  /// uploaded instead of reading a local file (no File on web).
  Future<void> _uploadAndSend({
    required AppUser me,
    required AppStrings s,
    required String localPath,
    required String mediaType,
    int? durationSeconds,
    Uint8List? bytes,
    String? filename,
  }) async {
    final messageId = ChatMediaService.newMessageId();
    setState(() {
      _sendingMedia = true;
      _uploadProgress = 0;
    });
    void progress(double p) {
      if (mounted) setState(() => _uploadProgress = p);
    }

    try {
      final url = bytes != null
          ? await _mediaService.uploadChatMediaBytes(
              bytes: bytes,
              filename: filename ?? localPath.split('/').last,
              folder: widget.conversationId,
              messageId: messageId,
              onProgress: progress,
            )
          : await _mediaService.uploadChatMedia(
              localPath: localPath,
              folder: widget.conversationId,
              messageId: messageId,
              onProgress: progress,
            );
      if (!mounted) return;
      final label = mediaType == 'video'
          ? s.mediaLabelVideo
          : mediaType == 'audio'
              ? s.mediaLabelVoiceNote
              : s.mediaLabelPhoto;
      await ref.read(chatServiceProvider).sendMessage(
            conversationId: widget.conversationId,
            senderId: me.id,
            senderName: me.name,
            text: '',
            mediaUrl: url,
            mediaType: mediaType,
            mediaDurationSeconds: durationSeconds,
            previewLabel: label,
          );
    } on ChatMediaTooLargeException {
      // Over the 10 MB cap: no retry is offered — the file
      // itself is too big, not the connection.
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.mediaTooLarge)),
      );
    } on FirebaseException catch (e) {
      // 'canceled' is the user cancelling mid-upload — not a
      // failure, and no retry is offered for it.
      if (e.code == 'canceled' || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.mediaUploadFailed),
          action: SnackBarAction(
            label: s.retry,
            onPressed: () => _uploadAndSend(
              me: me,
              s: s,
              localPath: localPath,
              mediaType: mediaType,
              durationSeconds: durationSeconds,
              bytes: bytes,
              filename: filename,
            ),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(s.mediaUploadFailed),
          action: SnackBarAction(
            label: s.retry,
            onPressed: () => _uploadAndSend(
              me: me,
              s: s,
              localPath: localPath,
              mediaType: mediaType,
              durationSeconds: durationSeconds,
              bytes: bytes,
              filename: filename,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sendingMedia = false;
          _uploadProgress = null;
        });
      }
    }
  }

  /// A finished voice note arrives from the record button:
  /// upload it and send it like any other media.
  Future<void> _sendVoiceNote(
      AppUser me, AppStrings s, String path, int seconds) async {
    await _uploadAndSend(
      me: me,
      s: s,
      localPath: path,
      mediaType: 'audio',
      durationSeconds: seconds,
    );
  }

  Future<void> _send(AppUser me) async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(chatServiceProvider).sendMessage(
            conversationId: widget.conversationId,
            senderId: me.id,
            senderName: me.name,
            text: text,
          );
      // Only clear the composer once the send landed — on
      // failure the text stays put so nothing is lost.
      if (mounted) _controller.clear();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ref.read(stringsProvider).sendFailedKept)),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _markReadIfNeeded(AppUser me, List<ChatMessage> messages) {
    if (!messages.any(
        (m) => m.senderId != me.id && !m.readByUser(me.id))) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(chatServiceProvider).markRead(
            conversationId: widget.conversationId,
            myId: me.id,
            messages: messages,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final users = ref.watch(allUsersProvider).valueOrNull ?? [];
    final userById = {for (final u in users) u.id: u};
    final teams = ref.watch(teamsProvider).valueOrNull ?? [];
    final teamById = {for (final t in teams) t.id: t};
    final liveAsync = ref.watch(conversationProvider(widget.conversationId));
    final conv = liveAsync.valueOrNull ?? widget.conversation;
    final messagesAsync = ref.watch(chatMessagesProvider(widget.conversationId));

    if (me == null || conv == null) {
      return Scaffold(
        appBar: AppBar(title: Text(s.chats)),
        body: const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 96),
          child: SkeletonList(count: 6),
        ),
      );
    }

    final String title;
    final String? subtitle;
    // DM only: the other participant, for the tappable header
    // below. Team channels and broadcasts have no single
    // person, so they keep the plain title.
    final AppUser? other;
    if (conv.isTeam) {
      other = null;
      final team = conv.teamId == null ? null : teamById[conv.teamId];
      title = conv.title ?? team?.name ?? s.team;
      final count = team?.memberIds.length;
      subtitle = count == null ? null : s.membersCount(count);
    } else {
      final otherId = conv.participantIds
          .firstWhere((id) => id != me.id, orElse: () => me.id);
      other = userById[otherId];
      title = other?.name ?? s.formerMember;
      subtitle = conv.isBroadcast ? s.broadcast : null;
    }
    // Tappable header only for a DM with a known person.
    final headerPerson = conv.isDm ? other : null;

    return Scaffold(
      appBar: AppBar(
        title: headerPerson == null
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              )
            : GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          WorkerProfileScreen(user: headerPerson),
                    ),
                  );
                },
                child: Row(
                  children: [
                    RoleAvatar(
                      name: headerPerson.name,
                      role: headerPerson.role,
                      size: 36,
                      photoUrl: headerPerson.photoUrl,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: tokens.textSecondary,
                                fontWeight: FontWeight.w400,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
      body: Column(
        children: [
          Expanded(
            child: messagesAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 96),
                child: SkeletonList(count: 6),
              ),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    '$error',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: tokens.textSecondary),
                  ),
                ),
              ),
              data: (messages) {
                if (messages.isEmpty) {
                  return EmptyState(
                    icon: Icons.chat_bubble_outline,
                    title: s.noMessagesYet,
                  );
                }
                _markReadIfNeeded(me, messages);
                // Newest at the bottom: reversed list, newest
                // message first in the data order below.
                final reversed = messages.reversed.toList();
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                  itemCount: reversed.length,
                  itemBuilder: (context, index) {
                    final m = reversed[index];
                    final mine = m.senderId == me.id;
                    final sender = userById[m.senderId];
                    // Images only, oldest first, for the
                    // photo viewer set when one is tapped.
                    final images = reversed
                        .where((x) => x.isImage)
                        .toList()
                        .reversed
                        .toList();
                    return _bubble(
                      context,
                      m,
                      mine,
                      sender,
                      conv.isTeam,
                      s,
                      tokens,
                      imageMessages: images,
                    );
                  },
                );
              },
            ),
          ),
          // No manual viewInsets padding here: the Scaffold
          // already resizes the body above the keyboard, and
          // adding the inset a second time pushed the send box
          // taller than the body when the keyboard opened.
          Container(
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border(top: BorderSide(color: tokens.border)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_sendingMedia)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: LinearProgressIndicator(
                              value: _uploadProgress,
                              backgroundColor: tokens.border,
                              color: tokens.accentText,
                              minHeight: 4,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            s.mediaUploading,
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.add_outlined),
                        color: tokens.accentText,
                        tooltip: s.attachMedia,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        onPressed: _sendingMedia
                            ? null
                            : () => _pickMedia(me, s),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          decoration: InputDecoration(
                            hintText: s.typeMessage,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 10),
                          ),
                          textCapitalization: TextCapitalization.sentences,
                          onSubmitted: (_) => _send(me),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Voice notes stay phone-only: recording
                      // uploads through a File path, which has no
                      // web equivalent (a blob URL cannot be read
                      // with dart:io File). The button is hidden
                      // on web rather than failing at send time.
                      if (!kIsWeb) ...[
                        VoiceRecordButton(
                          mediaService: _mediaService,
                          strings: s,
                          onRecorded: (path, seconds) =>
                              _sendVoiceNote(me, s, path, seconds),
                        ),
                        const SizedBox(width: 8),
                      ],
                      IconButton(
                        icon: const Icon(Icons.send_outlined),
                        color: tokens.accentText,
                        tooltip: s.send,
                        onPressed: _sending ? null : () => _send(me),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bubble(
    BuildContext context,
    ChatMessage m,
    bool mine,
    AppUser? sender,
    bool isTeamChat,
    AppStrings s,
    AppColors tokens, {
    required List<ChatMessage> imageMessages,
  }) {
    final time = m.createdAt == null
        ? ''
        : DateFormat('HH:mm').format(m.createdAt!);
    final showName = isTeamChat && !mine;
    final hasText = m.text.trim().isNotEmpty;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: mine ? tokens.accentMuted : tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showName)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  (sender?.name ?? s.formerMember).split(' ').first,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: tokens.accentText,
                  ),
                ),
              ),
            if (m.hasMedia) _mediaContent(context, m, imageMessages),
            if (hasText)
              Padding(
                padding: EdgeInsets.only(top: m.hasMedia ? 6 : 0),
                child: Text(
                  m.text,
                  style: TextStyle(fontSize: 15, color: tokens.textPrimary),
                ),
              ),
            if (time.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  time,
                  style: TextStyle(
                    fontSize: 11,
                    color: tokens.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// The media half of a bubble: image thumbnail (tap opens
  /// the photo viewer on this photo, swipeable across all the
  /// thread's images), video tile (tap opens the player), or
  /// voice-note player.
  Widget _mediaContent(
    BuildContext context,
    ChatMessage m,
    List<ChatMessage> imageMessages,
  ) {
    final url = m.mediaUrl;
    if (url == null) return const SizedBox.shrink();
    if (m.isImage) {
      final index = imageMessages.indexWhere((x) => x.id == m.id);
      return ChatImageBubble(
        url: url,
        onTap: () => showPhotoViewer(
          context,
          items: imageMessages
              .map((x) => PhotoViewerItem(
                    url: x.mediaUrl,
                    label: x.senderName,
                  ))
              .toList(),
          initialIndex: index < 0 ? 0 : index,
        ),
      );
    }
    if (m.isVideo) {
      return ChatVideoBubble(
        url: url,
        durationSeconds: m.mediaDurationSeconds,
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => VideoPlayerScreen(url: url, title: m.senderName),
          ),
        ),
      );
    }
    if (m.isAudio) {
      return ChatVoiceNoteBubble(
        url: url,
        durationSeconds: m.mediaDurationSeconds,
      );
    }
    return const SizedBox.shrink();
  }
}
