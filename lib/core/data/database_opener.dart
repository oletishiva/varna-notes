// Opens the platform database. The implementation is chosen at compile time:
//  * dart:io platforms (Android/iOS/desktop): sembast_io, a file in the app
//    documents directory.
//  * web (dart:js_interop): sembast_web (IndexedDB).
export 'database_opener_stub.dart'
    if (dart.library.io) 'database_opener_io.dart'
    if (dart.library.js_interop) 'database_opener_web.dart';
