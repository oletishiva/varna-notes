import 'dart:typed_data';

/// Metadata about one file in the cloud.
class RemoteFile {
  const RemoteFile({required this.name, required this.modified, this.etag});

  /// File name, e.g. `card_<id>.json`.
  final String name;

  /// Last-modified time as reported by the provider (UTC).
  final DateTime modified;

  /// Provider version/etag when available; changes whenever content changes.
  final String? etag;

  @override
  bool operator ==(Object other) =>
      other is RemoteFile &&
      other.name == name &&
      other.modified == modified &&
      other.etag == etag;

  @override
  int get hashCode => Object.hash(name, modified, etag);

  @override
  String toString() => 'RemoteFile($name, $modified, $etag)';
}

/// Base class for failures raised by a [CloudStore].
class CloudException implements Exception {
  CloudException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The network (or the provider) cannot be reached right now.
class CloudOfflineException extends CloudException {
  CloudOfflineException([super.message = 'You appear to be offline.']);
}

/// The user is not signed in or the permission was revoked.
class CloudAuthException extends CloudException {
  CloudAuthException([super.message = 'Not signed in to the cloud.']);
}

/// A flat file store in the user's own cloud account. Pure Dart interface;
/// implementations: `GoogleDriveStore`, `ICloudStore`, `MemoryCloudStore`.
///
/// Implementations throw [CloudOfflineException] / [CloudAuthException] /
/// [CloudException] on failure.
abstract class CloudStore {
  /// Human-readable provider name, e.g. "Google Drive".
  String get displayName;

  /// Signed-in account (email) or a generic label; null if unknown.
  String? get accountLabel;

  /// True when the provider is usable right now: supported on this platform
  /// and signed in. Never throws.
  Future<bool> isAvailable();

  /// Interactive sign-in. Returns false when cancelled/unsupported.
  Future<bool> signIn();

  /// Signs out. Local notes are not touched.
  Future<void> signOut();

  /// All files this app has in the cloud.
  Future<List<RemoteFile>> listFiles();

  Future<Uint8List> download(String name);

  /// Creates or overwrites [name]; returns the resulting file info.
  Future<RemoteFile> upload(String name, Uint8List bytes);

  /// Deletes [name]; no error if it does not exist.
  Future<void> delete(String name);
}
