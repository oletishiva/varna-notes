import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';

import 'attachment_store.dart';

/// Mobile/desktop: one file per attachment in `<documents>/attachments/`.
AttachmentStore createAttachmentStore(Database db) => FileAttachmentStore();

/// Stores each attachment as `<documents>/attachments/<id>.bin`.
class FileAttachmentStore implements AttachmentStore {
  FileAttachmentStore({Directory? directory}) : _directoryOverride = directory;

  final Directory? _directoryOverride;
  Directory? _dir;

  Future<Directory> _directory() async {
    final Directory? cached = _dir;
    if (cached != null) {
      return cached;
    }
    final Directory? overrideDir = _directoryOverride;
    final Directory dir;
    if (overrideDir != null) {
      dir = overrideDir;
    } else {
      final Directory docs = await getApplicationDocumentsDirectory();
      dir = Directory('${docs.path}/attachments');
    }
    await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  Future<File> _file(String id) async {
    final Directory dir = await _directory();
    return File('${dir.path}/${_safe(id)}.bin');
  }

  // Ids are UUIDs, but never let an id escape the directory.
  String _safe(String id) => id.replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');

  @override
  Future<void> save(String id, Uint8List bytes) async {
    final File file = await _file(id);
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<Uint8List?> read(String id) async {
    final File file = await _file(id);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsBytes();
  }

  @override
  Future<bool> exists(String id) async => (await _file(id)).exists();

  @override
  Future<void> delete(String id) async {
    final File file = await _file(id);
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<String?> localPath(String id) async {
    final File file = await _file(id);
    return await file.exists() ? file.path : null;
  }
}
