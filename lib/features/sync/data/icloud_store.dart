// iCloud-backed CloudStore. The real implementation (icloud_store_io.dart)
// uses the icloud_storage plugin and is only compiled where dart:io exists;
// everywhere else (web) the stub reports isAvailable() == false so the UI can
// hide the option. Both export the same class: `ICloudStore`.
export 'icloud_store_stub.dart'
    if (dart.library.io) 'icloud_store_io.dart';
