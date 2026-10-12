import 'dart:async';

import '../../../core/clock.dart';
import '../../../core/data/attachment_store.dart';
import '../../../core/data/notes_repository.dart';
import '../../../core/data/settings_repository.dart';
import '../../../core/models/models.dart';
import '../logic/cloud_store.dart';
import '../logic/sync_engine.dart';
import '../logic/sync_status.dart';
import 'google_drive_store.dart';
import 'icloud_store.dart';

/// Creates the [CloudStore] for a provider. Tests pass a factory returning a
/// `MemoryCloudStore`.
typedef CloudStoreFactory = CloudStore Function(SyncProviderId provider);

/// The real stores: Google Drive everywhere, iCloud on iOS/macOS.
CloudStore defaultCloudStoreFactory(SyncProviderId provider) {
  switch (provider) {
    case SyncProviderId.googleDrive:
      return GoogleDriveStore();
    case SyncProviderId.icloud:
      return ICloudStore();
  }
}

/// What the UI talks to for everything sync related: it wires the
/// repository, the chosen cloud store and the settings together.
///
/// Typical use (through `syncControllerProvider`):
///
/// * show `watchStatus()` in the sync chip;
/// * `connect(provider)` from the sync-setup screen;
/// * `syncNow()` for pull-to-refresh / "Sync now";
/// * list and `resolveConflict` for the conflict screen;
/// * `disconnect()` from settings (local notes are kept).
///
/// After [init], edits made through the repository trigger an automatic sync
/// [autoSyncDelay] after the last change (when a cloud is connected).
class SyncController {
  SyncController({
    required this.repository,
    required this.attachments,
    required this.settings,
    CloudStoreFactory? storeFactory,
    Clock? clock,
    this.autoSyncDelay = const Duration(seconds: 5),
    this.isOnWifi,
  })  : _factory = storeFactory ?? defaultCloudStoreFactory,
        _clock = clock ?? systemClock;

  final NotesRepository repository;
  final AttachmentStore attachments;
  final SettingsRepository settings;
  final CloudStoreFactory _factory;
  final Clock _clock;

  /// Quiet period after a local edit before syncing automatically; null
  /// disables automatic syncing.
  final Duration? autoSyncDelay;

  /// Optional probe used to honour the "Wi-Fi only" setting (wired in
  /// `syncControllerProvider`). Without it the setting cannot be enforced.
  final Future<bool> Function()? isOnWifi;

  SyncEngine? _engine;
  SyncProviderId? _provider;
  SyncStatus _status = const SyncIdle();
  StreamSubscription<SyncStatus>? _engineSub;
  StreamSubscription<void>? _changesSub;
  Timer? _debounce;
  bool _disposed = false;
  final StreamController<SyncStatus> _statusController =
      StreamController<SyncStatus>.broadcast();

  // ------------------------------------------------------------------- state

  /// The latest status.
  SyncStatus get status => _status;

  /// Emits the current status first, then every change.
  Stream<SyncStatus> watchStatus() async* {
    yield _status;
    yield* _statusController.stream;
  }

  /// The connected provider, or null.
  SyncProviderId? get activeProvider => _provider;

  /// True when a cloud is connected.
  bool get isConnected => _engine != null;

  /// Signed-in account label of the connected cloud (email for Google).
  String? get accountLabel => _engine?.store.accountLabel;

  /// Whether the UI should offer [provider] on this platform (iCloud only on
  /// iOS/macOS).
  bool isProviderSupported(SyncProviderId provider) {
    switch (provider) {
      case SyncProviderId.googleDrive:
        return true;
      case SyncProviderId.icloud:
        return ICloudStore.isSupportedPlatform;
    }
  }

  /// Number of records changed locally and not yet uploaded.
  Future<int> pendingChanges() => repository.countUnsynced();

  void _setStatus(SyncStatus status) {
    _status = status;
    if (!_statusController.isClosed) {
      _statusController.add(status);
    }
  }

  // --------------------------------------------------------------- lifecycle

  /// Restores the connection saved in settings and starts watching for local
  /// edits. Call once at app start (the provider does this for you).
  Future<void> init() async {
    final AppSettings saved = await settings.load();
    final SyncProviderId? provider = saved.syncProvider;
    if (provider != null && _engine == null) {
      _provider = provider;
      _attachEngine(_newEngine(_factory(provider), saved.includeMedia));
    }
    _changesSub ??= repository.changes.listen(_onLocalChange);
    final int conflicts = (await repository.listConflicts()).length;
    if (conflicts > 0 && _engine != null) {
      _setStatus(SyncConflicts(conflicts));
    }
  }

  SyncEngine _newEngine(CloudStore store, bool includeMedia) {
    return SyncEngine(
      repository: repository,
      attachments: attachments,
      store: store,
      clock: _clock,
      includeMedia: includeMedia,
    );
  }

  void _attachEngine(SyncEngine engine) {
    _engine = engine;
    _engineSub?.cancel();
    _engineSub = engine.statusStream.listen(_setStatus);
  }

  Future<void> _detachEngine() async {
    final SyncEngine? engine = _engine;
    _engine = null;
    await _engineSub?.cancel();
    _engineSub = null;
    await engine?.dispose();
  }

  void _onLocalChange(void _) {
    final Duration? delay = autoSyncDelay;
    if (delay == null || _engine == null || _disposed) {
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      unawaited(_autoSync());
    });
  }

  Future<void> _autoSync() async {
    if (_disposed || _engine == null) {
      return;
    }
    try {
      await syncNow();
    } catch (_) {
      // syncNow reports problems through the status stream.
    }
  }

  // ------------------------------------------------------------------- sync

  /// Runs a sync now. Never throws; inspect the report (or [watchStatus]).
  /// Returns an aborted report when no cloud is connected.
  Future<SyncReport> syncNow() async {
    final SyncEngine? engine = _engine;
    if (engine == null) {
      return const SyncReport(
        aborted: true,
        errors: <SyncFileError>[
          SyncFileError('provider', 'No cloud is connected.'),
        ],
      );
    }
    final AppSettings s = await settings.load();
    engine.includeMedia = s.includeMedia;
    final Future<bool> Function()? wifiProbe = isOnWifi;
    if (s.wifiOnly && wifiProbe != null && !await wifiProbe()) {
      _setStatus(const SyncOffline());
      return const SyncReport(offline: true);
    }
    final SyncReport report = await engine.sync();
    if (!report.offline && !report.aborted) {
      await settings.setLastSyncAt(_clock().toUtc());
    }
    return report;
  }

  /// Signs in to [provider] (if needed), pushes all local data to it and makes
  /// it the active cloud. When another cloud was connected, it is signed out
  /// afterwards. On failure nothing changes and the report has `aborted` or
  /// `offline` set. Never throws.
  Future<SyncReport> connect(SyncProviderId provider) async {
    try {
      final CloudStore store = _factory(provider);
      bool ready = await store.isAvailable();
      if (!ready) {
        ready = await store.signIn();
      }
      if (!ready) {
        return SyncReport(
          aborted: true,
          errors: <SyncFileError>[
            SyncFileError(
              'provider',
              'Could not sign in to ${store.displayName}.',
            ),
          ],
        );
      }

      final bool includeMedia = (await settings.load()).includeMedia;
      final SyncEngine? previous = _engine;
      final CloudStore? previousStore = previous?.store;
      final SyncEngine engine =
          previous ?? _newEngine(store, includeMedia);
      engine.includeMedia = includeMedia;
      if (previous == null) {
        _attachEngine(engine);
      }

      final SyncReport report = await engine.switchProvider(store);

      if (report.offline || report.aborted) {
        if (previous == null) {
          await _detachEngine();
          _setStatus(const SyncIdle());
        }
        return report;
      }

      if (previousStore != null &&
          _provider != null &&
          _provider != provider) {
        try {
          await previousStore.signOut();
        } catch (_) {
          // Best effort.
        }
      }
      _provider = provider;
      await settings.setSyncProvider(provider);
      await settings.setLastSyncAt(_clock().toUtc());
      return report;
    } catch (e) {
      return SyncReport(
        aborted: true,
        errors: <SyncFileError>[SyncFileError('provider', e.toString())],
      );
    }
  }

  /// Signs out and forgets the connection. Local notes are kept.
  Future<void> disconnect() async {
    _debounce?.cancel();
    final SyncEngine? engine = _engine;
    if (engine != null) {
      try {
        await engine.store.signOut();
      } catch (_) {
        // Best effort.
      }
    }
    await _detachEngine();
    await repository.clearSyncStates();
    await repository.clearConflicts();
    await settings.setSyncProvider(null);
    _provider = null;
    _setStatus(const SyncIdle());
  }

  // --------------------------------------------------------------- conflicts

  /// Open conflicts; emits now and after every change.
  Stream<List<SyncConflict>> watchConflicts() => repository.watchConflicts();

  Future<List<SyncConflict>> listConflicts() => repository.listConflicts();

  /// The conflict for a notebook/card id, or null.
  Future<SyncConflict?> getConflict(String id) => repository.getConflict(id);

  /// Applies the user's choice (see `SyncEngine.resolveConflict`). Throws a
  /// [CloudException] if `keepLocal` cannot reach the cloud; the conflict then
  /// stays open.
  Future<void> resolveConflict(String id, ConflictResolution resolution) async {
    final SyncEngine? engine = _engine;
    if (engine == null) {
      throw StateError('No cloud is connected.');
    }
    await engine.resolveConflict(id, resolution);
  }

  // ----------------------------------------------------------------- dispose

  Future<void> dispose() async {
    _disposed = true;
    _debounce?.cancel();
    await _changesSub?.cancel();
    await _detachEngine();
    await _statusController.close();
  }
}
