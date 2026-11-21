import 'dart:typed_data';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_strings.dart';
import '../models/app_user.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/locale_provider.dart';
import '../services/chat_media_service.dart';
import '../theme/app_tokens.dart';
import '../widgets/chat_media_bubble.dart';
import '../widgets/member_tile.dart';
import '../widgets/section_label.dart';
import '../widgets/skeleton_card.dart';
import '../widgets/voice_record_button.dart';

/// Broadcast composer (admin/manager only): pick recipients
/// from the crew, write one message, send. Each recipient gets
/// their own private conversation with the message in it — a
/// reply comes back 1:1 to the sender, never to the group.
class BroadcastScreen extends ConsumerStatefulWidget {
  const BroadcastScreen({super.key});

  @override
  ConsumerState<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends ConsumerState<BroadcastScreen> {
  final TextEditingController _controller = TextEditingController();
  final ChatMediaService _mediaService = ChatMediaService();
  final Set<String> _selected = {};
  bool _sending = false;

  /// One pending attachment (photo, video or voice note):
  /// picked locally, uploaded when Send is tapped. Null when
  /// no media is attached. [bytes]/[filename] is the web path:
  /// on web the picker returns a blob URL no File can read, so
  /// the bytes are read at pick time and uploaded instead.
  ({
    String path,
    String mediaType,
    int? durationSeconds,
    Uint8List? bytes,
    String? filename,
  })? _attachment;

  bool _sendingMedia = false;
  double? _uploadProgress;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Pick a photo/video from the (+) sheet and stage it as the
  /// pending attachment (a voice note stages itself via the
  /// mic button).
  Future<void> _pickMedia(AppStrings s) async {
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
      setState(() {
        _attachment = (
          path: file.path,
          mediaType: mediaType,
          durationSeconds: null,
          bytes: bytes,
          filename: file.name,
        );
      });
      return;
    }
    final duration = mediaType == 'video'
        ? await _mediaService.videoDurationSeconds(file.path)
        : null;
    setState(() {
      _attachment = (
        path: file.path,
        mediaType: mediaType,
        durationSeconds: duration,
        bytes: null,
        filename: null,
      );
    });
  }

  Future<void> _send(AppUser me, AppStrings s) async {
    final text = _controller.text.trim();
    if (_sending) return;
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.pickAtLeastOne)),
      );
      return;
    }
    if (text.isEmpty && _attachment == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.messageNeeded)),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      String? mediaUrl;
      String? mediaType;
      int? durationSeconds;
      final attachment = _attachment;
      if (attachment != null) {
        setState(() {
          _sendingMedia = true;
          _uploadProgress = 0;
        });
        try {
          final messageId = ChatMediaService.newMessageId();
          mediaUrl = attachment.bytes != null
              ? await _mediaService.uploadChatMediaBytes(
                  bytes: attachment.bytes!,
                  filename: attachment.filename ??
                      attachment.path.split('/').last,
                  folder: 'broadcast',
                  messageId: messageId,
                  onProgress: (p) {
                    if (mounted) setState(() => _uploadProgress = p);
                  },
                )
              : await _mediaService.uploadChatMedia(
                  localPath: attachment.path,
                  // One shared folder: every recipient's copy of the
                  // broadcast points at the same file.
                  folder: 'broadcast',
                  messageId: messageId,
                  onProgress: (p) {
                    if (mounted) setState(() => _uploadProgress = p);
                  },
                );
        } on ChatMediaTooLargeException {
          // Over the 10 MB cap: say so plainly instead of the
          // generic failure — the user needs a smaller file,
          // not a retry.
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.mediaTooLarge)),
          );
          return;
        } on FirebaseException catch (e) {
          // 'canceled' is the user cancelling mid-upload.
          if (e.code == 'canceled' || !mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.mediaUploadFailed)),
          );
          return;
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(s.mediaUploadFailed)),
          );
          return;
        } finally {
          if (mounted) {
            setState(() {
              _sendingMedia = false;
              _uploadProgress = null;
            });
          }
        }
        mediaType = attachment.mediaType;
        durationSeconds = attachment.durationSeconds;
      }
      final previewLabel = mediaType == 'video'
          ? s.mediaLabelVideo
          : mediaType == 'audio'
              ? s.mediaLabelVoiceNote
              : mediaType == 'image'
                  ? s.mediaLabelPhoto
                  : null;
      final result = await ref.read(chatServiceProvider).sendBroadcast(
            senderId: me.id,
            senderName: me.name,
            recipientIds: _selected.toList(),
            text: text,
            mediaUrl: mediaUrl,
            mediaType: mediaType,
            mediaDurationSeconds: durationSeconds,
            previewLabel: previewLabel,
          );
      if (!mounted) return;
      if (result.noneSent) {
        // Nobody got it: stay on the screen so the user can
        // retry, instead of popping with a "sent" message.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(s.couldNotSend)),
        );
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(result.allSent
                ? s.broadcastSent
                : s.broadcastPartiallySent(
                    result.sentIds.length, result.failedIds.length))),
      );
      Navigator.of(context).pop();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(s.couldNotSend)),
      );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _sendingMedia = false;
          _uploadProgress = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final s = ref.watch(stringsProvider);
    final me = ref.watch(currentUserProvider).valueOrNull;
    final usersAsync = ref.watch(allUsersProvider);
    final users = usersAsync.valueOrNull ?? [];
    final others = users.where((u) => me == null || u.id != me.id).toList();
    // While the crew list is still loading the recipient section
    // would render empty — show the skeleton instead so the
    // screen never looks blank for no reason.
    if (me == null || usersAsync.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(s.newBroadcast)),
        body: const Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, 96),
          child: SkeletonList(count: 6),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(s.newBroadcast)),
      body: Column(
              children: [
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                    children: [
                      Text(
                        s.broadcastHint,
                        style: TextStyle(
                          fontSize: 14,
                          color: tokens.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SectionLabel(s.selectRecipients),
                      const SizedBox(height: 8),
                      for (final u in others)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: InkWell(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              setState(() {
                                if (_selected.contains(u.id)) {
                                  _selected.remove(u.id);
                                } else {
                                  _selected.add(u.id);
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(16),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: _selected.contains(u.id),
                                  onChanged: (v) {
                                    HapticFeedback.lightImpact();
                                    setState(() {
                                      if (v == true) {
                                        _selected.add(u.id);
                                      } else {
                                        _selected.remove(u.id);
                                      }
                                    });
                                  },
                                ),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        u.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: tokens.textPrimary,
                                        ),
                                      ),
                                      Text(
                                        roleLabel(s, u.role),
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: tokens.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                // No manual viewInsets padding here: the Scaffold
                // already resizes the body above the keyboard, and
                // adding the inset a second time pushed the send
                // box taller than the body when the keyboard opened.
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
                        if (_attachment != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Chip(
                                avatar: Icon(
                                  _attachment!.mediaType == 'video'
                                      ? Icons.videocam_outlined
                                      : _attachment!.mediaType == 'audio'
                                          ? Icons.mic_outlined
                                          : Icons.photo_outlined,
                                  size: 18,
                                ),
                                label: Text(
                                  _attachment!.mediaType == 'video'
                                      ? s.mediaLabelVideo
                                      : _attachment!.mediaType == 'audio'
                                          ? s.mediaLabelVoiceNote
                                          : s.mediaLabelPhoto,
                                ),
                                deleteIcon: const Icon(Icons.close, size: 18),
                                onDeleted: () =>
                                    setState(() => _attachment = null),
                              ),
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
                                  : () => _pickMedia(s),
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
                                textCapitalization:
                                    TextCapitalization.sentences,
                                onSubmitted: (_) => _send(me, s),
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
                                onRecorded: (path, seconds) {
                                  setState(() {
                                    _attachment = (
                                      path: path,
                                      mediaType: 'audio',
                                      durationSeconds: seconds,
                                      bytes: null,
                                      filename: null,
                                    );
                                  });
                                },
                              ),
                              const SizedBox(width: 8),
                            ],
                            FilledButton(
                              onPressed:
                                  _sending ? null : () => _send(me, s),
                              child: Text(s.send),
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
}
