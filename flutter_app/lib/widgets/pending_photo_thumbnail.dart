/// Thumbnail of a photo parked in the offline queue, for the
/// pending update row on the task detail screen. Phones read
/// the parked file; other platforms get the stub (the web queue
/// never parks photos, so a pending thumbnail never renders
/// there). Never import the platform files directly; always go
/// through here.
library;
export 'pending_photo_thumbnail_stub.dart'
    if (dart.library.io) 'pending_photo_thumbnail_io.dart';
