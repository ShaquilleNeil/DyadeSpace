import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// One shared player for chat voice notes: starting one note
/// stops any other, so two voice notes never talk over each
/// other. Bubbles read [currentUrl] plus the player's own
/// streams to render play/pause, position and duration.
///
/// Picked over just_audio because the job is small — play a
/// URL, report position/duration, stop on completion — and
/// audioplayers does exactly that with no native setup and no
/// extra audio-session configuration.
class ChatAudioService {
  static final ChatAudioService instance = ChatAudioService._();

  ChatAudioService._() {
    _player.onPlayerComplete.listen((_) {
      currentUrl.value = null;
    });
  }

  final AudioPlayer _player = AudioPlayer();

  /// The url currently playing (or paused), or null when idle.
  final ValueNotifier<String?> currentUrl = ValueNotifier<String?>(null);

  AudioPlayer get player => _player;

  /// Plays [url], or resumes it when it is the paused one.
  Future<void> play(String url) async {
    if (currentUrl.value == url) {
      await _player.resume();
      return;
    }
    await _player.stop();
    currentUrl.value = url;
    await _player.play(UrlSource(url));
  }

  Future<void> pause() async => _player.pause();

  Future<void> stop() async {
    await _player.stop();
    currentUrl.value = null;
  }
}
