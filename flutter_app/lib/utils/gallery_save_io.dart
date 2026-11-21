import 'dart:typed_data';
import 'package:gal/gal.dart';

/// Phones: writes the bytes to the gallery. False when the save
/// fails (e.g. permission denied) — the caller shows the
/// failure snackbar.
Future<bool> saveImageToGallery(Uint8List bytes) async {
  try {
    await Gal.putImageBytes(bytes);
    return true;
  } catch (_) {
    return false;
  }
}
