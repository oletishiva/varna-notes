import 'package:sembast/sembast.dart';

import 'attachment_store.dart';

/// Web / fallback: bytes live in the database as base64.
AttachmentStore createAttachmentStore(Database db) =>
    SembastAttachmentStore(db);
