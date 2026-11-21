import 'package:flutter/material.dart';
import '../l10n/app_strings.dart';
import '../services/chat_audio_service.dart';
import '../theme/app_tokens.dart';

/// "m:ss" for a bubble duration / position.
String formatMediaDuration(int totalSeconds) {
  final m = totalSeconds ~/ 60;
  final s = totalSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// The attach (+) sheet shared by the chat send box and the
/// broadcast composer. Returns 'camera-photo',
/// 'gallery-photo', 'camera-video' or 'gallery-video' — or
/// null when the sheet is dismissed.
Future<String?> showAttachSheet(BuildContext context, AppStrings s) {
  return showModalBottomSheet<String>(
    context: context,
    builder: (ctx) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text(s.takePhoto),
              onTap: () => Navigator.pop(ctx, 'camera-photo'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text(s.choosePhoto),
              onTap: () => Navigator.pop(ctx, 'gallery-photo'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(s.recordVideo),
              onTap: () => Navigator.pop(ctx, 'camera-video'),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: Text(s.chooseVideo),
              onTap: () => Navigator.pop(ctx, 'gallery-video'),
            ),
          ],
        ),
      );
    },
  );
}

/// A chat image message: thumbnail that opens the shared photo
/// viewer (pinch-zoom, swipe, download, share) on tap.
class ChatImageBubble extends StatelessWidget {
  final String url;
  final VoidCallback onTap;

  const ChatImageBubble({super.key, required this.url, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220, maxHeight: 240),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const SizedBox(
                width: 220,
                height: 160,
                child: Center(child: CircularProgressIndicator()),
              );
            },
            errorBuilder: (_, __, ___) => const SizedBox(
              width: 220,
              height: 120,
              child: Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        ),
      ),
    );
  }
}

/// A chat video message: still tile with a play button and the
/// duration. Tapping opens the full-screen player.
class ChatVideoBubble extends StatelessWidget {
  final String url;
  final int? durationSeconds;
  final VoidCallback onTap;

  const ChatVideoBubble({
    super.key,
    required this.url,
    required this.durationSeconds,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 220,
        height: 140,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            const Icon(Icons.play_circle_fill,
                size: 56, color: Colors.white),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam_outlined,
                        size: 14, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      durationSeconds == null
                          ? ''
                          : formatMediaDuration(durationSeconds!),
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A chat voice note: play/pause, a progress bar and the
/// duration. One shared player ([ChatAudioService]) means
/// starting one note stops any other.
class ChatVoiceNoteBubble extends StatefulWidget {
  final String url;
  final int? durationSeconds;

  const ChatVoiceNoteBubble({
    super.key,
    required this.url,
    required this.durationSeconds,
  });

  @override
  State<ChatVoiceNoteBubble> createState() => _ChatVoiceNoteBubbleState();
}

class _ChatVoiceNoteBubbleState extends State<ChatVoiceNoteBubble> {
  final ChatAudioService _audio = ChatAudioService.instance;

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    final total = widget.durationSeconds;
    return ValueListenableBuilder<String?>(
      valueListenable: _audio.currentUrl,
      builder: (context, currentUrl, _) {
        final active = currentUrl == widget.url;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                active ? Icons.pause_circle_filled : Icons.play_circle_filled,
                size: 36,
              ),
              color: tokens.accentText,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () async {
                if (active) {
                  await _audio.pause();
                } else {
                  await _audio.play(widget.url);
                }
              },
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StreamBuilder<Duration>(
                    stream: _audio.player.onPositionChanged,
                    builder: (context, posSnap) {
                      final position =
                          active ? (posSnap.data ?? Duration.zero) : Duration.zero;
                      final duration = total == null
                          ? null
                          : Duration(seconds: total);
                      final progress = duration == null ||
                              duration.inMilliseconds == 0
                          ? 0.0
                          : (position.inMilliseconds /
                                  duration.inMilliseconds)
                              .clamp(0.0, 1.0);
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: progress,
                            backgroundColor: tokens.border,
                            color: tokens.accentText,
                            minHeight: 4,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            active
                                ? formatMediaDuration(
                                    position.inSeconds)
                                : (total == null
                                    ? ''
                                    : formatMediaDuration(total)),
                            style: TextStyle(
                              fontSize: 12,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
