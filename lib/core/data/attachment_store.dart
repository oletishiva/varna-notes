import 'dart:convert';
import 'dart:typed_data';

import 'package:sembast/sembast.dart';

/// Stores the bytes of attachments (audio, images) by attachment id.
///
/// Implementations: `FileAttachmentStore` (mobile/desktop, files in the app
/// documents directory), [SembastAttachmentStore] (web, base64 in the
/// database) and [MemoryAttachmentStore] (tests). Get the right one for the
/// current platform with `createAttachmentStore` (attachment_store_factory.dart)
/// or the `attachmentStoreProvider`.
abstract class AttachmentStore {
  /// Writes (or overwrites) the bytes for [id].
  Future<void> save(String id, Uint8List bytes);

  /// Returns the bytes, or null when [id] is unknown.
  Future<Uint8List?> read(String id);

  /// Whether bytes for [id] are stored.
  Future<bool> exists(String id);

  /// Removes the bytes for [id]; no error when it does not exist.
  Future<void> delete(String id);

  /// Absolute path of the file holding [id], for players that need a path.
  /// Always null on web and for non-file stores; use [read] there.
  Future<String?> localPath(String id);
}

/// Keeps attachments as base64 strings in a sembast store. Used on web, and
/// usable anywhere.
class SembastAttachmentStore implements AttachmentStore {
  SembastAttachmentStore(this._db);

  final Database _db;
  final StoreRef<String, Map<String, Object?>> _store =
      stringMapStoreFactory.store('attachments');

  @override
  Future<void> save(String id, Uint8List bytes) async {
    await _store.record(id).put(_db, <String, Object?>{
      'data': base64Encode(bytes),
    });
  }

  @override
  Future<Uint8List?> read(String id) async {
    final Map<String, Object?>? value = await _store.record(id).get(_db);
    if (value == null) {
      return null;
    }
    return base64Decode(value['data'] as String);
  }

  @override
  Future<bool> exists(String id) => _store.record(id).exists(_db);

  @override
  Future<void> delete(String id) async {
    await _store.record(id).delete(_db);
  }

  @override
  Future<String?> localPath(String id) async => null;
}

/// Pure in-memory implementation for tests.
class MemoryAttachmentStore implements AttachmentStore {
  final Map<String, Uint8List> _files = <String, Uint8List>{};

  @override
  Future<void> save(String id, Uint8List bytes) async {
    _files[id] = Uint8List.fromList(bytes);
  }

  @override
  Future<Uint8List?> read(String id) async {
    final Uint8List? bytes = _files[id];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<bool> exists(String id) async => _files.containsKey(id);

  @override
  Future<void> delete(String id) async {
    _files.remove(id);
  }

  @override
  Future<String?> localPath(String id) async => null;

  /// Number of stored blobs (test helper).
  int get length => _files.length;
}
