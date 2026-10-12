import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../../../core/clock.dart';
import '../../../core/data/attachment_store.dart';
import '../../../core/data/notes_repository.dart';
import '../../../core/models/model_utils.dart';
import '../../../core/models/models.dart';
import 'cloud_store.dart';
import 'sync_status.dart';

class _Counters {
  int uploaded = 0;
  int downloaded = 0;
  int mediaUploaded = 0;
  int mediaDownloaded = 0;
  final List<SyncFileError> errors = <SyncFileError>[];
}

/// Two-way sync between the local database and a [CloudStore]. Pure Dart.
///
/// Remote layout: `nb_<id>.json`, `card_<id>.json` (one JSON file per record,
/// tombstones included) and `att_<id>.bin` (attachment bytes, immutable).
///
/// Per record the engine compares the local `updatedAt` and the cloud file's
/// modified time/etag against the [SyncState] saved at the last sync:
///
/// * only local changed  -> upload
/// * only cloud changed  -> download and apply
/// * both changed, same content (ignoring `updatedAt`) -> just record state
/// * both changed, different content -> store a [SyncConflict]; neither side
///   is overwritten until [resolveConflict]
/// * neither changed -> skip
///
/// A failure on one file is collected in `SyncReport.errors`; [sync] never
/// throws.
class SyncEngine {
  SyncEngine({
    required this.repository,
    required this.attachments,
    required CloudStore store,
    Clock? clock,
    this.includeMedia = true,
  })  : _store = store,
        _clock = clock ?? systemClock;

  final NotesRepository repository;
  final AttachmentStore attachments;
  final Clock _clock;

  /// Whether attachment blobs (`att_<id>.bin`) are synced too.
  bool includeMedia;

  CloudStore _store;

  /// The active cloud store.
  CloudStore get store => _store;

  SyncStatus _status = const SyncIdle();
  DateTime? _lastSyncedAt;
  Future<SyncReport>? _running;
  final StreamController<SyncStatus> _controller =
      StreamController<SyncStatus>.broadcast();

  /// The current status.
  SyncStatus get status => _status;

  /// Status changes (does not replay the current value; read [status] for
  /// that).
  Stream<SyncStatus> get statusStream => _controller.stream;

  bool get isSyncing => _running != null;

  /// File name of an attachment's bytes in the cloud.
  static String attachmentFileName(String attachmentId) =>
      'att_$attachmentId.bin';

  void _emit(SyncStatus status) {
    _status = status;
    if (!_controller.isClosed) {
      _controller.add(status);
    }
  }

  /// Runs a sync. Calls made while a sync is running share that run.
  Future<SyncReport> sync() {
    final Future<SyncReport>? running = _running;
    if (running != null) {
      return running;
    }
    final Future<SyncReport> run = _run().whenComplete(() {
      _running = null;
    });
    _running = run;
    return run;
  }

  /// Makes [newStore] the active store: forgets the per-record sync state,
  /// then runs a full sync so everything local is pushed to it (and anything
  /// already there is merged, with conflicts for differing records).
  ///
  /// If the new store is unavailable, or the first sync cannot list or reach
  /// it, nothing changes: the previous store and its sync state are restored
  /// and the returned report has `offline` or `aborted` set.
  Future<SyncReport> switchProvider(CloudStore newStore) async {
    final Future<SyncReport>? running = _running;
    if (running != null) {
      try {
        await running;
      } catch (_) {
        // sync() never throws; ignore defensively.
      }
    }
    if (!await newStore.isAvailable()) {
      return SyncReport(
        aborted: true,
        errors: <SyncFileError>[
          SyncFileError(
            'provider',
            '${newStore.displayName} is not available. Sign in first.',
          ),
        ],
      );
    }
    final CloudStore oldStore = _store;
    final List<SyncState> savedStates = await repository.allSyncStates();
    final List<SyncConflict> savedConflicts = await repository.listConflicts();
    await repository.clearSyncStates();
    await repository.clearConflicts();
    _store = newStore;
    final SyncReport report = await sync();
    if (report.offline || report.aborted) {
      _store = oldStore;
      await repository.replaceSyncStates(savedStates);
      await repository.clearConflicts();
      for (final SyncConflict c in savedConflicts) {
        await repository.putConflict(c);
      }
    }
    return report;
  }

  Future<int> _conflictCount() async =>
      (await repository.listConflicts()).length;

  Future<SyncReport> _report(
    _Counters c, {
    bool offline = false,
    bool aborted = false,
  }) async {
    return SyncReport(
      uploaded: c.uploaded,
      downloaded: c.downloaded,
      conflicts: await _conflictCount(),
      errors: List<SyncFileError>.unmodifiable(c.errors),
      mediaUploaded: c.mediaUploaded,
      mediaDownloaded: c.mediaDownloaded,
      offline: offline,
      aborted: aborted,
    );
  }

  String _describe(Object error) {
    if (error is CloudException) {
      return error.message;
    }
    return error.toString();
  }

  Future<SyncReport> _run() async {
    _emit(const SyncSyncing());
    final _Counters c = _Counters();
    try {
      if (!await _store.isAvailable()) {
        _emit(const SyncOffline());
        return await _report(c, offline: true);
      }

      List<RemoteFile> files = const <RemoteFile>[];
      try {
        files = await _store.listFiles();
      } on CloudOfflineException {
        _emit(const SyncOffline());
        return await _report(c, offline: true);
      } catch (e) {
        c.errors.add(SyncFileError('(list)', _describe(e)));
        _emit(SyncError(_describe(e)));
        return await _report(c, aborted: true);
      }
      final Map<String, RemoteFile> remoteByName = <String, RemoteFile>{
        for (final RemoteFile f in files) f.name: f,
      };

      try {
        await _syncRecords(remoteByName, c);
        if (includeMedia) {
          await _syncMedia(remoteByName, c);
        }
      } on CloudOfflineException {
        _emit(const SyncOffline());
        return await _report(c, offline: true);
      }

      final SyncReport report = await _report(c);
      if (c.errors.isEmpty) {
        _lastSyncedAt = _clock().toUtc();
      }
      if (report.conflicts > 0) {
        _emit(SyncConflicts(report.conflicts));
      } else if (c.errors.isNotEmpty) {
        _emit(SyncError(c.errors.first.toString()));
      } else {
        _emit(SyncSynced(_lastSyncedAt!));
      }
      return report;
    } catch (e) {
      c.errors.add(SyncFileError('(sync)', _describe(e)));
      _emit(SyncError(_describe(e)));
      return _report(c, aborted: true);
    }
  }

  // ------------------------------------------------------------------ records

  Future<void> _syncRecords(
    Map<String, RemoteFile> remoteByName,
    _Counters c,
  ) async {
    final List<SyncRecord> locals = await repository.allSyncRecords();
    final Map<String, SyncRecord> localByKey = <String, SyncRecord>{
      for (final SyncRecord r in locals) r.key: r,
    };
    final Map<String, RemoteFile> remoteByKey = <String, RemoteFile>{};
    for (final RemoteFile f in remoteByName.values) {
      if (SyncRecord.parseFileName(f.name) != null) {
        remoteByKey[f.name.substring(0, f.name.length - '.json'.length)] = f;
      }
    }
    final Map<String, SyncConflict> conflicts = <String, SyncConflict>{
      for (final SyncConflict cf in await repository.listConflicts())
        cf.key: cf,
    };
    final List<String> keys = <String>{
      ...localByKey.keys,
      ...remoteByKey.keys,
    }.toList()
      ..sort();

    for (final String key in keys) {
      try {
        await _syncKey(
          key: key,
          local: localByKey[key],
          remote: remoteByKey[key],
          state: await repository.getSyncState(key),
          conflict: conflicts[key],
          counters: c,
        );
      } on CloudOfflineException {
        rethrow;
      } catch (e) {
        c.errors.add(SyncFileError('$key.json', _describe(e)));
      }
    }
  }

  bool _remoteChanged(RemoteFile remote, SyncState state) {
    if (remote.etag != null && state.lastSyncedRemoteEtag != null) {
      return remote.etag != state.lastSyncedRemoteEtag;
    }
    final DateTime? known = state.lastSyncedRemoteModified;
    return known == null || remote.modified.toUtc() != known;
  }

  bool _sameRemote(RemoteFile remote, SyncConflict conflict) {
    if (remote.etag != null && conflict.remoteEtag != null) {
      return remote.etag == conflict.remoteEtag;
    }
    return conflict.remoteModified != null &&
        remote.modified.toUtc() == conflict.remoteModified;
  }

  Future<SyncRecord> _fetch(RemoteFile file) async {
    final ({RecordKind kind, String id})? parsed =
        SyncRecord.parseFileName(file.name);
    if (parsed == null) {
      throw FormatException('Not a record file: ${file.name}');
    }
    final Uint8List bytes = await _store.download(file.name);
    final Map<String, Object?> map =
        asStringMap(jsonDecode(utf8.decode(bytes)));
    final SyncRecord record = SyncRecord.fromJson(parsed.kind, map);
    if (record.id != parsed.id) {
      throw FormatException('Record id does not match file name ${file.name}');
    }
    return record;
  }

  Future<void> _markSynced(SyncRecord local, RemoteFile remote) {
    return repository.putSyncState(SyncState(
      key: local.key,
      lastSyncedLocalUpdatedAt: local.updatedAt,
      lastSyncedRemoteModified: remote.modified.toUtc(),
      lastSyncedRemoteEtag: remote.etag,
    ));
  }

  Future<RemoteFile> _push(SyncRecord local) async {
    final Uint8List bytes = Uint8List.fromList(utf8.encode(jsonEncode(local.json)));
    final RemoteFile result = await _store.upload(local.fileName, bytes);
    await _markSynced(local, result);
    return result;
  }

  Future<void> _syncKey({
    required String key,
    required SyncRecord? local,
    required RemoteFile? remote,
    required SyncState? state,
    required SyncConflict? conflict,
    required _Counters counters,
  }) async {
    if (local == null && remote == null) {
      return;
    }

    // Only the cloud has it: receive (a tombstone is received as a tombstone).
    if (local == null) {
      final SyncRecord received = await _fetch(remote!);
      await repository.applyRemoteRecord(received);
      await _markSynced(received, remote);
      counters.downloaded++;
      return;
    }

    // Only this device has it: send.
    if (remote == null) {
      await _push(local);
      counters.uploaded++;
      return;
    }

    // Both have it, and a conflict is already open: keep it fresh, never
    // overwrite either side.
    if (conflict != null) {
      await _refreshConflict(local, remote, conflict);
      return;
    }

    final bool localChanged =
        state == null || local.updatedAt != state.lastSyncedLocalUpdatedAt;
    final bool remoteChanged = state == null || _remoteChanged(remote, state);

    if (!localChanged && !remoteChanged) {
      return;
    }
    if (localChanged && !remoteChanged) {
      await _push(local);
      counters.uploaded++;
      return;
    }

    // The cloud copy changed (and maybe the local one too): look at it.
    final SyncRecord received = await _fetch(remote);
    if (local.contentEquals(received)) {
      await _markSynced(local, remote);
      return;
    }
    if (!localChanged) {
      await repository.applyRemoteRecord(received);
      await _markSynced(received, remote);
      counters.downloaded++;
      return;
    }
    await repository.putConflict(SyncConflict(
      kind: local.kind,
      id: local.id,
      local: local.json,
      remote: received.json,
      detectedAt: _clock().toUtc(),
      remoteModified: remote.modified.toUtc(),
      remoteEtag: remote.etag,
    ));
  }

  Future<void> _refreshConflict(
    SyncRecord local,
    RemoteFile remote,
    SyncConflict conflict,
  ) async {
    SyncRecord received;
    if (_sameRemote(remote, conflict)) {
      received = SyncRecord.fromJson(conflict.kind, conflict.remote);
    } else {
      received = await _fetch(remote);
    }
    if (local.contentEquals(received)) {
      // Both sides converged on their own; nothing left to decide.
      await _markSynced(local, remote);
      await repository.removeConflict(conflict.id);
      return;
    }
    await repository.putConflict(SyncConflict(
      kind: conflict.kind,
      id: conflict.id,
      local: local.json,
      remote: received.json,
      detectedAt: conflict.detectedAt,
      remoteModified: remote.modified.toUtc(),
      remoteEtag: remote.etag,
    ));
  }

  // -------------------------------------------------------------------- media

  Future<void> _syncMedia(
    Map<String, RemoteFile> remoteByName,
    _Counters c,
  ) async {
    final List<NoteCard> cards = await repository.listAllCards();
    final Set<String> seen = <String>{};
    for (final NoteCard card in cards) {
      for (final Attachment att in card.attachments) {
        if (!seen.add(att.id)) {
          continue;
        }
        final String name = attachmentFileName(att.id);
        try {
          final bool hasLocal = await attachments.exists(att.id);
          final bool hasRemote = remoteByName.containsKey(name);
          if (hasLocal && !hasRemote) {
            final Uint8List? bytes = await attachments.read(att.id);
            if (bytes != null) {
              await _store.upload(name, bytes);
              c.mediaUploaded++;
            }
          } else if (!hasLocal && hasRemote) {
            final Uint8List bytes = await _store.download(name);
            await attachments.save(att.id, bytes);
            c.mediaDownloaded++;
          }
        } on CloudOfflineException {
          rethrow;
        } catch (e) {
          c.errors.add(SyncFileError(name, _describe(e)));
        }
      }
    }
  }

  // ---------------------------------------------------------------- conflicts

  /// Applies the user's choice for the conflict on notebook/card [recordId].
  ///
  /// * `keepLocal`: the local version is given a fresh `updatedAt` and
  ///   uploaded over the cloud copy.
  /// * `keepRemote`: the cloud version replaces the local one.
  /// * `keepBoth`: the cloud version replaces the original; the local version
  ///   is saved as a new record titled "<title> (copy)" (not created when the
  ///   local version was a deletion). The copy uploads on the next sync.
  ///
  /// Does nothing when there is no such conflict. `keepLocal` talks to the
  /// cloud, so it can throw a [CloudException] (the conflict then stays open).
  Future<void> resolveConflict(
    String recordId,
    ConflictResolution resolution,
  ) async {
    final SyncConflict? conflict = await repository.getConflict(recordId);
    if (conflict == null) {
      return;
    }
    switch (resolution) {
      case ConflictResolution.keepLocal:
        final SyncRecord? touched =
            await repository.touchRecord(conflict.kind, conflict.id);
        if (touched == null) {
          await _applyConflictRemote(conflict);
        } else {
          await _push(touched);
        }
      case ConflictResolution.keepRemote:
        await _applyConflictRemote(conflict);
      case ConflictResolution.keepBoth:
        final SyncRecord? local =
            await repository.getSyncRecord(conflict.kind, conflict.id);
        await _applyConflictRemote(conflict);
        if (local != null && !local.deleted) {
          await repository.duplicateRecord(local);
        }
    }
    await repository.removeConflict(conflict.id);
    final int remaining = await _conflictCount();
    if (remaining > 0) {
      _emit(SyncConflicts(remaining));
    } else if (_lastSyncedAt != null) {
      _emit(SyncSynced(_lastSyncedAt!));
    } else {
      _emit(const SyncIdle());
    }
  }

  Future<void> _applyConflictRemote(SyncConflict conflict) async {
    final SyncRecord received =
        SyncRecord.fromJson(conflict.kind, conflict.remote);
    await repository.applyRemoteRecord(received);
    await repository.putSyncState(SyncState(
      key: conflict.key,
      lastSyncedLocalUpdatedAt: received.updatedAt,
      lastSyncedRemoteModified: conflict.remoteModified,
      lastSyncedRemoteEtag: conflict.remoteEtag,
    ));
  }

  /// Stops emitting status events.
  Future<void> dispose() => _controller.close();
}
