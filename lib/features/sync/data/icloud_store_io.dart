import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart' show PlatformException;
import 'package:icloud_storage/icloud_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../../../app_config.dart';
import '../logic/cloud_store.dart';

/// [CloudStore] on top of the user's iCloud container (iOS and macOS only).
///
/// There is no explicit sign-in: the user must be signed in to iCloud in the
/// system settings. On Android and other platforms [isAvailable] is false.
///
/// Files live in the container's documents area, flat, with the same names as
/// every other store (`card_<id>.json`, ...). iCloud gives no etag, so change
/// detection relies on `contentChangeDate`.
class ICloudStore implements CloudStore {
  ICloudStore({String? containerId})
      : containerId = containerId ?? AppConfig.iCloudContainerId;

  /// The iCloud container id (must match the app's entitlements).
  final String containerId;

  /// True on iOS and macOS builds.
  static bool get isSupportedPlatform => Platform.isIOS || Platform.isMacOS;

  static const Set<String> _notFoundCodes = <String>{'fileNotFound', 'E_FNF'};
  static const Set<String> _accessCodes = <String>{
    'iCloudConnectionOrPermission',
    'E_CTR',
  };

  @override
  String get displayName => 'iCloud';

  @override
  String? get accountLabel => isSupportedPlatform ? 'iCloud' : null;

  @override
  Future<bool> isAvailable() async {
    if (!isSupportedPlatform) {
      return false;
    }
    try {
      await ICloudStorage.gather(containerId: containerId);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> signIn() => isAvailable();

  @override
  Future<void> signOut() async {
    // Nothing to sign out of; the account is managed by the OS.
  }

  CloudException _translate(Object error) {
    if (error is CloudException) {
      return error;
    }
    if (error is PlatformException) {
      if (_accessCodes.contains(error.code)) {
        return CloudAuthException(
          'iCloud is not reachable. Check that you are signed in to iCloud.',
        );
      }
      return CloudException(error.message ?? error.code);
    }
    return CloudException(error.toString());
  }

  /// iCloud lists not-yet-downloaded files as `.name.icloud` placeholders.
  String _cleanName(String relativePath) {
    final int slash = relativePath.lastIndexOf('/');
    final String dir = slash >= 0 ? relativePath.substring(0, slash + 1) : '';
    String base = slash >= 0 ? relativePath.substring(slash + 1) : relativePath;
    if (base.startsWith('.') && base.endsWith('.icloud')) {
      base = base.substring(1, base.length - '.icloud'.length);
    }
    return '$dir$base';
  }

  @override
  Future<List<RemoteFile>> listFiles() async {
    if (!isSupportedPlatform) {
      throw CloudException('iCloud is not available on this platform.');
    }
    try {
      final List<ICloudFile> files =
          await ICloudStorage.gather(containerId: containerId);
      final List<RemoteFile> out = <RemoteFile>[];
      for (final ICloudFile f in files) {
        final dynamic path = f.relativePath;
        final dynamic changed = f.contentChangeDate;
        if (path is! String) {
          continue;
        }
        out.add(RemoteFile(
          name: _cleanName(path.toString()),
          modified: changed is DateTime
              ? changed.toUtc()
              : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        ));
      }
      return out;
    } catch (e) {
      throw _translate(e);
    }
  }

  Future<Directory> _scratchDir() async {
    final Directory tmp = await getTemporaryDirectory();
    final Directory dir = Directory('${tmp.path}/varna_icloud');
    await dir.create(recursive: true);
    return dir;
  }

  // Wraps the plugin's progress stream into a future that completes when the
  // transfer stream is done (or after [limit], whichever comes first).
  void Function(Stream<double>) _progressWatcher(
    Completer<void> done,
    List<StreamSubscription<double>> subs,
  ) {
    return (Stream<double> stream) {
      subs.add(stream.listen(
        (double _) {},
        onDone: () {
          if (!done.isCompleted) {
            done.complete();
          }
        },
        onError: (Object _) {
          if (!done.isCompleted) {
            done.complete();
          }
        },
        cancelOnError: true,
      ));
    };
  }

  @override
  Future<Uint8List> download(String name) async {
    final Directory dir = await _scratchDir();
    final File target = File('${dir.path}/dl_${DateTime.now().microsecondsSinceEpoch}');
    final Completer<void> done = Completer<void>();
    final List<StreamSubscription<double>> subs =
        <StreamSubscription<double>>[];
    try {
      await ICloudStorage.download(
        containerId: containerId,
        relativePath: name,
        destinationFilePath: target.path,
        onProgress: _progressWatcher(done, subs),
      );
      await done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
      // The plugin's future can complete before the copy lands: poll.
      for (int i = 0; i < 120; i++) {
        if (await target.exists()) {
          return await target.readAsBytes();
        }
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      throw CloudException('Timed out downloading $name from iCloud.');
    } catch (e) {
      if (e is PlatformException && _notFoundCodes.contains(e.code)) {
        throw CloudException('File not found in iCloud: $name');
      }
      throw _translate(e);
    } finally {
      for (final StreamSubscription<double> s in subs) {
        await s.cancel();
      }
      if (await target.exists()) {
        await target.delete();
      }
    }
  }

  @override
  Future<RemoteFile> upload(String name, Uint8List bytes) async {
    final Directory dir = await _scratchDir();
    // The plugin names the cloud file after destinationRelativePath, but keep
    // the scratch file name equal to [name] to be safe.
    final Directory unique =
        await Directory('${dir.path}/up_${DateTime.now().microsecondsSinceEpoch}')
            .create(recursive: true);
    final File source = File('${unique.path}/$name');
    final Completer<void> done = Completer<void>();
    final List<StreamSubscription<double>> subs =
        <StreamSubscription<double>>[];
    try {
      await source.writeAsBytes(bytes, flush: true);
      await ICloudStorage.upload(
        containerId: containerId,
        filePath: source.path,
        destinationRelativePath: name,
        onProgress: _progressWatcher(done, subs),
      );
      await done.future.timeout(const Duration(seconds: 20), onTimeout: () {});
    } catch (e) {
      throw _translate(e);
    } finally {
      for (final StreamSubscription<double> s in subs) {
        await s.cancel();
      }
      if (await unique.exists()) {
        await unique.delete(recursive: true);
      }
    }
    // Report the file as iCloud lists it, falling back to "now".
    try {
      final List<RemoteFile> files = await listFiles();
      for (final RemoteFile f in files) {
        if (f.name == name) {
          return f;
        }
      }
    } catch (_) {
      // Fall through.
    }
    return RemoteFile(name: name, modified: DateTime.now().toUtc());
  }

  @override
  Future<void> delete(String name) async {
    try {
      await ICloudStorage.delete(containerId: containerId, relativePath: name);
    } catch (e) {
      if (e is PlatformException && _notFoundCodes.contains(e.code)) {
        return;
      }
      throw _translate(e);
    }
  }
}
