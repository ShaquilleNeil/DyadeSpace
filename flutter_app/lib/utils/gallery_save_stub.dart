import 'dart:typed_data';

/// Non-mobile platforms: no gallery to save to. The photo
/// viewer never calls this on web (it opens the image URL
/// instead), so this only ever runs if a caller forgets the
/// platform check.
Future<bool> saveImageToGallery(Uint8List bytes) async => false;
