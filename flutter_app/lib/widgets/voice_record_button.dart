import 'dart:async';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../l10n/app_strings.dart';
import '../services/chat_media_service.dart';
import '../theme/app_tokens.dart';
import 'chat_media_bubble.dart' show formatMediaDuration;

/// The chat send box's microphone: press and hold to record a
/// voice note (max 2 minutes — auto-stops at 120s), release to
/// send, drag away from the button to cancel. A note under 1s
/// is discarded with a snackbar. Recording errors surface as a
/// snackbar; a missing mic permission is requested at runtime
/// and, when denied, explained in a dialog that offers the
/// system settings.
///
/// [onRecorded] receives the finished local path and its
/// length in seconds, so the caller can upload and send it.
/// The widget never writes to Firestore itself.
class VoiceRecordButton extends StatefulWidget {
  final ChatMediaService mediaService;
  final void Function(String path, int seconds) onRecorded;
  final AppStrings strings;

  const VoiceRecordButton({
    super.key,
    required this.mediaService,
    required this.onRecorded,
    required this.strings,
  });

  @override
  State<VoiceRecordButton> createState() => _VoiceRecordButtonState();
}

class _VoiceRecordButtonState extends State<VoiceRecordButton> {
  bool _recording = false;
  bool _cancelled = false;
  // True between pointer-down and pointer-up/cancel. The mic
  // permission prompt can take seconds: if the finger lifted
  // while it was up, _start must not start a recording nobody
  // is holding (it would run to the 120s auto-stop and send).
  bool _pointerHeld = false;
  int _seconds = 0;
  Timer? _timer;
  String? _path;
  static const int maxSeconds = 120;

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  /// Explains the missing mic permission and offers the system
  /// settings, where the user can allow it.
  Future<void> _showMicPermissionDialog() async {
    final s = widget.strings;
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.micPermissionTitle),
        content: Text(s.micPermissionBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.openSettings),
          ),
        ],
      ),
    );
    if (open == true) {
      await openAppSettings();
    }
  }

  Future<void> _start() async {
    // The mic permission is requested at runtime (the manifest
    // entry alone is not enough): denied — or permanently denied
    // — explains itself and offers the settings screen.
    final status = await Permission.microphone.request();
    if (!mounted) return;
    if (!status.isGranted) {
      await _showMicPermissionDialog();
      return;
    }
    if (!_pointerHeld) return;
    final allowed = await widget.mediaService.canRecord;
    if (!mounted || !_pointerHeld) return;
    if (!allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings.recordingFailed)),
      );
      return;
    }
    String path;
    try {
      path = await widget.mediaService.startVoiceNote();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(widget.strings.recordingFailed)),
      );
      return;
    }
    _path = path;
    setState(() {
      _recording = true;
      _cancelled = false;
      _seconds = 0;
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_seconds >= maxSeconds) {
        _finish(send: true);
        return;
      }
      setState(() => _seconds++);
    });
  }

  Future<void> _finish({required bool send}) async {
    if (!_recording) return;
    _stopTimer();
    final path = _path;
    // Capture the length before the reset — the too-short
    // check below reads this, not the reset field.
    final seconds = _seconds;
    setState(() {
      _recording = false;
      _seconds = 0;
    });
    if (send) {
      if (path == null) return;
      await widget.mediaService.stopVoiceNote();
      if (!mounted) return;
      // A 0s note means the recorder never really ran.
      if (seconds < 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(widget.strings.voiceNoteTooShort)),
        );
        return;
      }
      widget.onRecorded(path, seconds);
    } else {
      await widget.mediaService.discardVoiceNote();
    }
    _path = null;
  }

  @override
  void dispose() {
    _stopTimer();
    // Popped mid-recording (back button while holding): stop
    // and discard the note instead of recording forever into
    // a temp file nobody will send.
    if (_recording) {
      widget.mediaService.discardVoiceNote();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = AppTokens.of(context);
    if (_recording) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: const BoxDecoration(
                color: Colors.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              formatMediaDuration(_seconds),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _cancelled
                    ? widget.strings.dragToCancel
                    : widget.strings.releaseToSend,
                style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: tokens.textSecondary),
              tooltip: widget.strings.cancel,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () => _finish(send: false),
            ),
          ],
        ),
      );
    }
    // Press and hold: pointer-down starts, pointer-up (or a
    // cancelled pointer) stops and sends, unless the press was
    // dragged away from the button — that arms cancel instead.
    // A Listener (not a long-press) starts at once, so the
    // <1s discard below still covers an accidental tap.
    return Listener(
      onPointerDown: (_) {
        _pointerHeld = true;
        _start();
      },
      onPointerMove: (event) {
        if (!_recording) return;
        final box = context.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(event.position);
        // Dragging well up/away from the button arms cancel.
        final shouldCancel = local.dy < -32;
        if (shouldCancel != _cancelled) {
          setState(() => _cancelled = shouldCancel);
        }
      },
      onPointerUp: (_) {
        _pointerHeld = false;
        _finish(send: !_cancelled);
        _cancelled = false;
      },
      onPointerCancel: (_) {
        _pointerHeld = false;
        _finish(send: false);
        _cancelled = false;
      },
      child: IconButton(
        icon: const Icon(Icons.mic_outlined),
        color: tokens.accentText,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(),
        onPressed: null,
      ),
    );
  }
}
