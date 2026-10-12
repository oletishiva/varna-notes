// Chooses the attachment storage implementation at compile time:
//  * dart:io platforms: FileAttachmentStore (files under app documents).
//  * everything else (web): SembastAttachmentStore.
// Exposes: `AttachmentStore createAttachmentStore(Database db)`.
export 'attachment_store_stub.dart'
    if (dart.library.io) 'attachment_store_io.dart';
