import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

import '../../../app_config.dart';
import '../logic/cloud_store.dart';

/// [CloudStore] backed by the hidden per-app `appDataFolder` of the user's
/// Google Drive (scope `drive.appdata`, so the app can never see the user's
/// other files and the files do not clutter their Drive).
///
/// Written against google_sign_in 6.x and
/// extension_google_sign_in_as_googleapis_auth 2.x. Works on Android, iOS and
/// web, but needs OAuth client ids supplied with `--dart-define` (see
/// `AppConfig`).
class GoogleDriveStore implements CloudStore {
  GoogleDriveStore({GoogleSignIn? googleSignIn})
      : _signIn = googleSignIn ?? _defaultSignIn();

  static const String driveAppDataScope =
      'https://www.googleapis.com/auth/drive.appdata';

  static const String _fields = 'id,name,modifiedTime,version';

  static GoogleSignIn _defaultSignIn() {
    String? clientId;
    String? serverClientId;
    if (kIsWeb) {
      clientId = _orNull(AppConfig.googleWebClientId);
    } else {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        clientId = _orNull(AppConfig.googleIosClientId);
      }
      serverClientId = _orNull(AppConfig.googleServerClientId);
    }
    return GoogleSignIn(
      scopes: const <String>[driveAppDataScope],
      clientId: clientId,
      serverClientId: serverClientId,
    );
  }

  static String? _orNull(String value) => value.isEmpty ? null : value;

  final GoogleSignIn _signIn;
  final Map<String, String> _idsByName = <String, String>{};

  @override
  String get displayName => 'Google Drive';

  @override
  String? get accountLabel => _signIn.currentUser?.email;

  @override
  Future<bool> isAvailable() async {
    try {
      if (_signIn.currentUser != null) {
        return true;
      }
      final GoogleSignInAccount? account = await _signIn.signInSilently();
      return account != null;
    } catch (e) {
      // No network is not "signed out": let the real request report it as
      // offline instead of asking the user to sign in again.
      return e is PlatformException && e.code == GoogleSignIn.kNetworkError;
    }
  }

  @override
  Future<bool> signIn() async {
    try {
      final GoogleSignInAccount? account = await _signIn.signIn();
      return account != null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> signOut() async {
    _idsByName.clear();
    try {
      await _signIn.signOut();
    } catch (_) {
      // Already signed out or plugin unavailable.
    }
  }

  Future<T> _withApi<T>(Future<T> Function(drive.DriveApi api) body) async {
    final http.Client? client;
    try {
      client = await _signIn.authenticatedClient();
    } catch (e) {
      throw _translate(e);
    }
    if (client == null) {
      throw CloudAuthException('Not signed in to Google.');
    }
    try {
      return await body(drive.DriveApi(client));
    } catch (e) {
      throw _translate(e);
    } finally {
      client.close();
    }
  }

  CloudException _translate(Object error) {
    if (error is CloudException) {
      return error;
    }
    if (error is drive.DetailedApiRequestError) {
      final int? status = error.status;
      if (status == 401 || status == 403) {
        return CloudAuthException(
          'Google Drive refused access. Sign in again.',
        );
      }
      return CloudException(
        'Google Drive error ${status ?? ''}: ${error.message ?? ''}'.trim(),
      );
    }
    if (error is http.ClientException) {
      return CloudOfflineException();
    }
    if (error is PlatformException && error.code == GoogleSignIn.kNetworkError) {
      return CloudOfflineException();
    }
    return CloudException(error.toString());
  }

  RemoteFile _toRemote(drive.File f) {
    return RemoteFile(
      name: f.name ?? '',
      modified: (f.modifiedTime ?? DateTime.fromMillisecondsSinceEpoch(0)).toUtc(),
      etag: f.version,
    );
  }

  @override
  Future<List<RemoteFile>> listFiles() {
    return _withApi<List<RemoteFile>>((drive.DriveApi api) async {
      final List<RemoteFile> out = <RemoteFile>[];
      String? pageToken;
      do {
        final drive.FileList page = await api.files.list(
          spaces: 'appDataFolder',
          pageSize: 1000,
          pageToken: pageToken,
          $fields: 'nextPageToken,files($_fields)',
        );
        for (final drive.File f in page.files ?? <drive.File>[]) {
          final String? id = f.id;
          final String? name = f.name;
          if (id != null && name != null) {
            _idsByName[name] = id;
            out.add(_toRemote(f));
          }
        }
        pageToken = page.nextPageToken;
      } while (pageToken != null);
      return out;
    });
  }

  Future<String?> _findId(drive.DriveApi api, String name) async {
    final String? cached = _idsByName[name];
    if (cached != null) {
      return cached;
    }
    final String escaped = name.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final drive.FileList page = await api.files.list(
      spaces: 'appDataFolder',
      q: "name = '$escaped'",
      pageSize: 1,
      $fields: 'files(id,name)',
    );
    final List<drive.File> files = page.files ?? <drive.File>[];
    if (files.isEmpty || files.first.id == null) {
      return null;
    }
    _idsByName[name] = files.first.id!;
    return files.first.id;
  }

  @override
  Future<Uint8List> download(String name) {
    return _withApi<Uint8List>((drive.DriveApi api) async {
      final String? id = await _findId(api, name);
      if (id == null) {
        throw CloudException('File not found in Google Drive: $name');
      }
      final Object response = await api.files.get(
        id,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );
      final drive.Media media = response as drive.Media;
      final BytesBuilder builder = BytesBuilder(copy: false);
      await for (final List<int> chunk in media.stream) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    });
  }

  @override
  Future<RemoteFile> upload(String name, Uint8List bytes) {
    return _withApi<RemoteFile>((drive.DriveApi api) async {
      final drive.Media media = drive.Media(
        Stream<List<int>>.value(bytes),
        bytes.length,
      );
      final String? existing = await _findId(api, name);
      final drive.File result;
      if (existing == null) {
        final drive.File metadata = drive.File()
          ..name = name
          ..parents = <String>['appDataFolder'];
        result = await api.files.create(
          metadata,
          uploadMedia: media,
          $fields: _fields,
        );
        final String? id = result.id;
        if (id != null) {
          _idsByName[name] = id;
        }
      } else {
        result = await api.files.update(
          drive.File(),
          existing,
          uploadMedia: media,
          $fields: _fields,
        );
      }
      final RemoteFile remote = _toRemote(result);
      return RemoteFile(
        name: name,
        modified: remote.modified,
        etag: remote.etag,
      );
    });
  }

  @override
  Future<void> delete(String name) {
    return _withApi<void>((drive.DriveApi api) async {
      final String? id = await _findId(api, name);
      if (id == null) {
        return;
      }
      try {
        await api.files.delete(id);
      } on drive.DetailedApiRequestError catch (e) {
        if (e.status != 404) {
          rethrow;
        }
      }
      _idsByName.remove(name);
    });
  }
}
