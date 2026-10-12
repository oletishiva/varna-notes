import 'dart:typed_data';

import '../../../core/clock.dart';
import 'cloud_store.dart';

/// In-memory [CloudStore] used by tests (and handy for previews). Offers
/// switches to simulate failures.
class MemoryCloudStore implements CloudStore {
  MemoryCloudStore({
    Clock? clock,
    this.displayName = 'Memory cloud',
    this.accountLabel = 'test@example.com',
  }) : _clock = clock ?? systemClock;

  final Clock _clock;

  @override
  final String displayName;

  @override
  String? accountLabel;

  /// Result of [isAvailable]. Set false to simulate "not signed in".
  bool available = true;

  /// When true, every operation throws [CloudOfflineException].
  bool offline = false;

  /// File names whose upload throws a [CloudException].
  final Set<String> failUploadFor = <String>{};

  /// File names whose download throws a [CloudException].
  final Set<String> failDownloadFor = <String>{};

  /// Names passed to [upload], in order (test assertion helper).
  final List<String> uploadLog = <String>[];

  /// Names passed to [download], in order.
  final List<String> downloadLog = <String>[];

  /// Names passed to [delete], in order.
  final List<String> deleteLog = <String>[];

  final Map<String, Uint8List> _bytes = <String, Uint8List>{};
  final Map<String, DateTime> _modified = <String, DateTime>{};
  final Map<String, String> _etags = <String, String>{};
  int _version = 0;

  void _checkOnline() {
    if (offline) {
      throw CloudOfflineException();
    }
  }

  /// Seeds or replaces a file without going through [upload] (no logging, no
  /// failure injection).
  RemoteFile put(String name, Uint8List bytes) {
    _bytes[name] = Uint8List.fromList(bytes);
    _modified[name] = _clock().toUtc();
    _version++;
    _etags[name] = 'v$_version';
    return RemoteFile(
      name: name,
      modified: _modified[name]!,
      etag: _etags[name],
    );
  }

  /// Raw bytes of a stored file, or null (test helper).
  Uint8List? peek(String name) => _bytes[name];

  bool contains(String name) => _bytes.containsKey(name);

  /// Names of all stored files, sorted.
  List<String> get names => _bytes.keys.toList()..sort();

  @override
  Future<bool> isAvailable() async => available && !offline;

  @override
  Future<bool> signIn() async {
    _checkOnline();
    available = true;
    return true;
  }

  @override
  Future<void> signOut() async {
    available = false;
  }

  @override
  Future<List<RemoteFile>> listFiles() async {
    _checkOnline();
    return <RemoteFile>[
      for (final String name in names)
        RemoteFile(
          name: name,
          modified: _modified[name]!,
          etag: _etags[name],
        ),
    ];
  }

  @override
  Future<Uint8List> download(String name) async {
    _checkOnline();
    downloadLog.add(name);
    if (failDownloadFor.contains(name)) {
      throw CloudException('download failed: $name');
    }
    final Uint8List? bytes = _bytes[name];
    if (bytes == null) {
      throw CloudException('not found: $name');
    }
    return Uint8List.fromList(bytes);
  }

  @override
  Future<RemoteFile> upload(String name, Uint8List bytes) async {
    _checkOnline();
    uploadLog.add(name);
    if (failUploadFor.contains(name)) {
      throw CloudException('upload failed: $name');
    }
    return put(name, bytes);
  }

  @override
  Future<void> delete(String name) async {
    _checkOnline();
    deleteLog.add(name);
    _bytes.remove(name);
    _modified.remove(name);
    _etags.remove(name);
  }
}
