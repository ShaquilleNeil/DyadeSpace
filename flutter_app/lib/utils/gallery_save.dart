/// Saves image bytes to the device gallery. The gallery plugin
/// (gal) has no web implementation, so the call is routed by
/// platform: phones use gal, everything else gets the stub
/// (which reports failure — the photo viewer falls back to
/// opening the image URL on web). Never import the platform
/// files directly; always go through here.
library;
export 'gallery_save_stub.dart'
    if (dart.library.io) 'gallery_save_io.dart';
