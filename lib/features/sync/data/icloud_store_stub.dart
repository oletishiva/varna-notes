import 'dart:typed_data';

import '../logic/cloud_store.dart';

/// Web / unsupported-platform stand-in: never available.
class ICloudStore implements CloudStore {
  ICloudStore({String? containerId});

  /// True when this platform can use iCloud at all (iOS/macOS builds).
  static bool get isSupportedPlatform => false;

  @override
  String get displayName => 'iCloud';

  @override
  String? get accountLabel => null;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<bool> signIn() async => false;

  @override
  Future<void> signOut() async {}

  CloudException _unsupported() =>
      CloudException('iCloud is not available on this platform.');

  @override
  Future<List<RemoteFile>> listFiles() => Future<List<RemoteFile>>.error(
        _unsupported(),
      );

  @override
  Future<Uint8List> download(String name) =>
      Future<Uint8List>.error(_unsupported());

  @override
  Future<RemoteFile> upload(String name, Uint8List bytes) =>
      Future<RemoteFile>.error(_unsupported());

  @override
  Future<void> delete(String name) => Future<void>.error(_unsupported());
}
