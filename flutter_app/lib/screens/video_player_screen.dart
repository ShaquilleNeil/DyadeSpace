import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../providers/locale_provider.dart';

/// Full-screen video player for a chat video message: tap to
/// play/pause, scrub with the progress bar. Plays on open.
/// A video that fails to load shows an error state with a
/// retry button instead of spinning forever.
class VideoPlayerScreen extends ConsumerStatefulWidget {
  final String url;
  final String? title;

  const VideoPlayerScreen({super.key, required this.url, this.title});

  @override
  ConsumerState<VideoPlayerScreen> createState() =>
      _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _ready = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await _controller.initialize();
      if (!mounted) return;
      setState(() => _ready = true);
      _controller.play();
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  Future<void> _retry() async {
    await _controller.dispose();
    if (!mounted) return;
    setState(() {
      _ready = false;
      _failed = false;
    });
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(stringsProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: widget.title == null
            ? null
            : Text(
                widget.title!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 15),
              ),
      ),
      body: Center(
        child: _failed
            ? Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline,
                        color: Colors.white70, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      s.videoLoadError,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _retry,
                      child: Text(s.retry),
                    ),
                  ],
                ),
              )
            : !_ready
                ? const CircularProgressIndicator(color: Colors.white)
                : GestureDetector(
                onTap: () {
                  setState(() {
                    if (_controller.value.isPlaying) {
                      _controller.pause();
                    } else {
                      _controller.play();
                    }
                  });
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                    ValueListenableBuilder<VideoPlayerValue>(
                      valueListenable: _controller,
                      builder: (context, value, _) {
                        if (value.isPlaying) {
                          return const SizedBox.shrink();
                        }
                        return Container(
                          decoration: const BoxDecoration(
                            color: Colors.black45,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(12),
                          child: const Icon(
                            Icons.play_arrow,
                            size: 48,
                            color: Colors.white,
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: !_ready
          ? null
          : Container(
              color: Colors.black,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              child: Row(
                children: [
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: _controller,
                    builder: (context, value, _) => Text(
                      _fmt(value.position),
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: VideoProgressIndicator(
                      _controller,
                      allowScrubbing: true,
                      colors: const VideoProgressColors(
                        playedColor: Colors.white,
                        backgroundColor: Colors.white24,
                        bufferedColor: Colors.white38,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _fmt(_controller.value.duration),
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
    );
  }
}
