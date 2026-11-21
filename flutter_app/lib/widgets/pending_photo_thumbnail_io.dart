import 'dart:io';
import 'package:flutter/material.dart';

/// Phones: the parked photo file, as a small square thumbnail.
/// A missing file (cleaned up mid-upload) shows a photo icon
/// instead of crashing the row.
Widget pendingPhotoThumbnail(String localPath, {double size = 64}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(8),
    child: Image.file(
      File(localPath),
      width: size,
      height: size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => SizedBox(
        width: size,
        height: size,
        child: const Icon(Icons.photo_outlined),
      ),
    ),
  );
}
