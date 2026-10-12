import 'model_utils.dart';
import 'note_card.dart';
import 'notebook.dart';

/// Which cloud holds the user's data.
enum SyncProviderId {
  googleDrive,
  icloud;

  String get displayName =>
      this == SyncProviderId.googleDrive ? 'Google Drive' : 'iCloud';

  static SyncProviderId? fromName(String? name) {
    for (final SyncProviderId p in SyncProviderId.values) {
      if (p.name == name) {
        return p;
      }
    }
    return null;
  }
}

/// How the user resolved a [SyncConflict].
enum ConflictResolution {
  /// Local version wins and overwrites the cloud copy.
  keepLocal,

  /// Cloud version wins and overwrites the local copy.
  keepRemote,

  /// Cloud version wins on the original id; the local version is saved as a
  /// new record (a copy) so nothing is lost.
  keepBoth,
}

/// Notebook or card.
enum RecordKind {
  notebook,
  card;

  /// File-name prefix: `nb` or `card`.
  String get prefix => this == RecordKind.notebook ? 'nb' : 'card';
}

final RegExp _recordFileName = RegExp(r'^(nb|card)_(.+)\.json$');

/// A syncable record in neutral form: just enough metadata for the sync
/// engine plus the JSON that goes in the cloud file.
class SyncRecord {
  const SyncRecord({
    required this.kind,
    required this.id,
    required this.updatedAt,
    required this.deleted,
    required this.json,
  });

  final RecordKind kind;
  final String id;
  final DateTime updatedAt;
  final bool deleted;
  final Map<String, Object?> json;

  factory SyncRecord.fromNotebook(Notebook n) => SyncRecord(
        kind: RecordKind.notebook,
        id: n.id,
        updatedAt: n.updatedAt,
        deleted: n.deleted,
        json: n.toJson(),
      );

  factory SyncRecord.fromCard(NoteCard c) => SyncRecord(
        kind: RecordKind.card,
        id: c.id,
        updatedAt: c.updatedAt,
        deleted: c.deleted,
        json: c.toJson(),
      );

  /// Parses and normalises a decoded cloud file. Throws on malformed input.
  factory SyncRecord.fromJson(RecordKind kind, Map<String, Object?> json) {
    if (kind == RecordKind.notebook) {
      return SyncRecord.fromNotebook(Notebook.fromJson(json));
    }
    return SyncRecord.fromCard(NoteCard.fromJson(json));
  }

  /// Identity key: `nb_<id>` or `card_<id>`.
  String get key => keyFor(kind, id);

  /// Cloud file name: `<key>.json`.
  String get fileName => '$key.json';

  static String keyFor(RecordKind kind, String id) => '${kind.prefix}_$id';

  /// Splits a cloud file name into kind and id; null when it is not a record
  /// file (for example `att_<id>.bin`).
  static ({RecordKind kind, String id})? parseFileName(String name) {
    final RegExpMatch? m = _recordFileName.firstMatch(name);
    if (m == null) {
      return null;
    }
    final RecordKind kind =
        m.group(1) == 'nb' ? RecordKind.notebook : RecordKind.card;
    return (kind: kind, id: m.group(2)!);
  }

  /// True when both records say the same thing, ignoring `updatedAt`. Two
  /// tombstones are always equal.
  bool contentEquals(SyncRecord other) {
    if (kind != other.kind || id != other.id) {
      return false;
    }
    if (deleted && other.deleted) {
      return true;
    }
    if (deleted != other.deleted) {
      return false;
    }
    return _withoutUpdatedAt(json) == _withoutUpdatedAt(other.json);
  }

  static String _withoutUpdatedAt(Map<String, Object?> json) {
    final Map<String, Object?> copy = Map<String, Object?>.of(json)
      ..remove('updatedAt');
    return canonicalJson(copy);
  }
}

/// Bookkeeping that remembers what was last in sync for one record.
class SyncState {
  const SyncState({
    required this.key,
    required this.lastSyncedLocalUpdatedAt,
    this.lastSyncedRemoteModified,
    this.lastSyncedRemoteEtag,
  });

  /// `nb_<id>` / `card_<id>`.
  final String key;

  /// The local `updatedAt` that was uploaded or received at the last sync.
  final DateTime lastSyncedLocalUpdatedAt;

  /// The cloud file's modified time at the last sync.
  final DateTime? lastSyncedRemoteModified;

  /// The cloud file's etag/version at the last sync, when the store has one.
  final String? lastSyncedRemoteEtag;

  Map<String, Object?> toJson() => <String, Object?>{
        'key': key,
        'lastSyncedLocalUpdatedAt': formatUtc(lastSyncedLocalUpdatedAt),
        'lastSyncedRemoteModified': lastSyncedRemoteModified == null
            ? null
            : formatUtc(lastSyncedRemoteModified!),
        'lastSyncedRemoteEtag': lastSyncedRemoteEtag,
      };

  factory SyncState.fromJson(Map<String, Object?> json) {
    return SyncState(
      key: json['key'] as String,
      lastSyncedLocalUpdatedAt: parseUtc(json['lastSyncedLocalUpdatedAt']),
      lastSyncedRemoteModified: parseUtcOrNull(json['lastSyncedRemoteModified']),
      lastSyncedRemoteEtag: json['lastSyncedRemoteEtag'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SyncState &&
      other.key == key &&
      other.lastSyncedLocalUpdatedAt == lastSyncedLocalUpdatedAt &&
      other.lastSyncedRemoteModified == lastSyncedRemoteModified &&
      other.lastSyncedRemoteEtag == lastSyncedRemoteEtag;

  @override
  int get hashCode => Object.hash(key, lastSyncedLocalUpdatedAt,
      lastSyncedRemoteModified, lastSyncedRemoteEtag);

  @override
  String toString() => 'SyncState($key)';
}

/// A record that changed on this device and in the cloud with different
/// content. Neither side is overwritten until the user decides.
class SyncConflict {
  const SyncConflict({
    required this.kind,
    required this.id,
    required this.local,
    required this.remote,
    required this.detectedAt,
    this.remoteModified,
    this.remoteEtag,
  });

  final RecordKind kind;

  /// Id of the notebook/card in conflict (use it for the `/conflict/:id`
  /// route and `resolveConflict`).
  final String id;

  /// JSON of the local version (a `Notebook`/`NoteCard` toJson map).
  final Map<String, Object?> local;

  /// JSON of the cloud version.
  final Map<String, Object?> remote;

  final DateTime detectedAt;
  final DateTime? remoteModified;
  final String? remoteEtag;

  String get key => SyncRecord.keyFor(kind, id);

  Notebook get localNotebook => Notebook.fromJson(local);
  Notebook get remoteNotebook => Notebook.fromJson(remote);
  NoteCard get localCard => NoteCard.fromJson(local);
  NoteCard get remoteCard => NoteCard.fromJson(remote);

  bool get localDeleted => (local['deleted'] as bool?) ?? false;
  bool get remoteDeleted => (remote['deleted'] as bool?) ?? false;

  DateTime get localUpdatedAt => parseUtc(local['updatedAt']);
  DateTime get remoteUpdatedAt => parseUtc(remote['updatedAt']);

  /// Title of the local version (notebook or card).
  String get localTitle => (local['title'] as String?) ?? '';

  /// Title of the cloud version.
  String get remoteTitle => (remote['title'] as String?) ?? '';

  SyncConflict copyWith({
    Map<String, Object?>? local,
    Map<String, Object?>? remote,
    DateTime? remoteModified,
    String? remoteEtag,
  }) {
    return SyncConflict(
      kind: kind,
      id: id,
      local: local ?? this.local,
      remote: remote ?? this.remote,
      detectedAt: detectedAt,
      remoteModified: remoteModified ?? this.remoteModified,
      remoteEtag: remoteEtag ?? this.remoteEtag,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'kind': kind.name,
        'id': id,
        'local': local,
        'remote': remote,
        'detectedAt': formatUtc(detectedAt),
        'remoteModified':
            remoteModified == null ? null : formatUtc(remoteModified!),
        'remoteEtag': remoteEtag,
      };

  factory SyncConflict.fromJson(Map<String, Object?> json) {
    return SyncConflict(
      kind: json['kind'] == 'notebook' ? RecordKind.notebook : RecordKind.card,
      id: json['id'] as String,
      local: asStringMap(json['local']),
      remote: asStringMap(json['remote']),
      detectedAt: parseUtc(json['detectedAt']),
      remoteModified: parseUtcOrNull(json['remoteModified']),
      remoteEtag: json['remoteEtag'] as String?,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SyncConflict &&
      other.kind == kind &&
      other.id == id &&
      canonicalJson(other.local) == canonicalJson(local) &&
      canonicalJson(other.remote) == canonicalJson(remote) &&
      other.detectedAt == detectedAt &&
      other.remoteModified == remoteModified &&
      other.remoteEtag == remoteEtag;

  @override
  int get hashCode => Object.hash(kind, id, canonicalJson(local),
      canonicalJson(remote), detectedAt, remoteModified, remoteEtag);

  @override
  String toString() => 'SyncConflict($key)';
}
