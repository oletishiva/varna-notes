/// What the sync engine is doing / did last. Switch over the subclasses:
///
/// ```dart
/// switch (status) {
///   case SyncIdle(): ...
///   case SyncSyncing(): ...
///   case SyncSynced(:final at): ...
///   case SyncOffline(): ...
///   case SyncError(:final message): ...
///   case SyncConflicts(:final count): ...
/// }
/// ```
sealed class SyncStatus {
  const SyncStatus();
}

/// Nothing has happened yet, or no cloud is connected.
class SyncIdle extends SyncStatus {
  const SyncIdle();

  @override
  bool operator ==(Object other) => other is SyncIdle;

  @override
  int get hashCode => 1;
}

/// A sync is running.
class SyncSyncing extends SyncStatus {
  const SyncSyncing();

  @override
  bool operator ==(Object other) => other is SyncSyncing;

  @override
  int get hashCode => 2;
}

/// The last sync finished cleanly at [at].
class SyncSynced extends SyncStatus {
  const SyncSynced(this.at);
  final DateTime at;

  @override
  bool operator ==(Object other) => other is SyncSynced && other.at == at;

  @override
  int get hashCode => Object.hash(3, at);
}

/// The cloud could not be reached or is not signed in.
class SyncOffline extends SyncStatus {
  const SyncOffline();

  @override
  bool operator ==(Object other) => other is SyncOffline;

  @override
  int get hashCode => 4;
}

/// The last sync failed with [message] (e.g. a provider error).
class SyncError extends SyncStatus {
  const SyncError(this.message);
  final String message;

  @override
  bool operator ==(Object other) =>
      other is SyncError && other.message == message;

  @override
  int get hashCode => Object.hash(5, message);
}

/// [count] records need the user to pick a version.
class SyncConflicts extends SyncStatus {
  const SyncConflicts(this.count);
  final int count;

  @override
  bool operator ==(Object other) =>
      other is SyncConflicts && other.count == count;

  @override
  int get hashCode => Object.hash(6, count);
}

/// Shown (as a [SyncError]) when the cloud account needs to be signed in to
/// again and nobody could do that interactively.
const String kSignInAgainMessage = 'Sign in again to keep syncing';

/// A failure for one file; the rest of the sync carries on.
class SyncFileError {
  const SyncFileError(this.name, this.message);

  /// The cloud file name (or a label such as `(list)`).
  final String name;
  final String message;

  @override
  String toString() => '$name: $message';
}

/// Outcome of one sync run.
class SyncReport {
  const SyncReport({
    this.uploaded = 0,
    this.downloaded = 0,
    this.conflicts = 0,
    this.errors = const <SyncFileError>[],
    this.mediaUploaded = 0,
    this.mediaDownloaded = 0,
    this.offline = false,
    this.aborted = false,
  });

  /// Records (notebooks/cards/tombstones) pushed to the cloud.
  final int uploaded;

  /// Records received from the cloud and applied locally.
  final int downloaded;

  /// Total open conflicts after this run (new and older ones).
  final int conflicts;

  /// Per-file failures; never thrown.
  final List<SyncFileError> errors;

  /// Attachment blobs pushed / received.
  final int mediaUploaded;
  final int mediaDownloaded;

  /// True when the run stopped because the cloud was unreachable.
  final bool offline;

  /// True when the run could not start or list the cloud (nothing synced).
  final bool aborted;

  /// True when nothing went wrong (conflicts are not failures).
  bool get isOk => !offline && !aborted && errors.isEmpty;

  @override
  String toString() => 'SyncReport(up=$uploaded, down=$downloaded, '
      'conflicts=$conflicts, errors=${errors.length}, offline=$offline, '
      'aborted=$aborted)';
}
