import 'package:flutter/material.dart';

/// Non-mobile platforms: the queue never parks photos, so a
/// pending thumbnail never renders.
Widget pendingPhotoThumbnail(String localPath, {double size = 64}) =>
    SizedBox(width: size, height: size);
