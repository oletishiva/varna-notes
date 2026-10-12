import 'package:sembast/sembast.dart';
import 'package:varna/core/data/attachment_store.dart';
import 'package:varna/core/data/memory_database.dart';
import 'package:varna/core/data/notes_repository.dart';
import 'package:varna/core/data/settings_repository.dart';
import 'package:varna/features/sync/logic/memory_cloud_store.dart';
import 'package:varna/features/sync/logic/sync_engine.dart';

/// A clock the test moves by hand.
class TestClock {
  TestClock([DateTime? start]) : _now = start ?? DateTime.utc(2026, 10, 12, 10);

  DateTime _now;

  /// Use `clock.call` wherever a `Clock` is expected.
  DateTime call() => _now;

  void advance([Duration by = const Duration(minutes: 1)]) {
    _now = _now.add(by);
  }

  void set(DateTime value) {
    _now = value;
  }
}

/// A simulated phone: its own database, attachments and sync engine, talking
/// to a (shared) cloud store.
class Device {
  Device._({
    required this.db,
    required this.repo,
    required this.settings,
    required this.attachments,
    required this.engine,
  });

  final Database db;
  final NotesRepository repo;
  final SettingsRepository settings;
  final MemoryAttachmentStore attachments;
  final SyncEngine engine;

  static Future<Device> create(
    MemoryCloudStore cloud,
    TestClock clock, {
    bool includeMedia = false,
  }) async {
    final Database db = await openInMemoryDatabase();
    final MemoryAttachmentStore attachments = MemoryAttachmentStore();
    final NotesRepository repo = NotesRepository(
      db,
      clock: clock.call,
      attachments: attachments,
    );
    final SettingsRepository settings =
        SettingsRepository(db, clock: clock.call);
    final SyncEngine engine = SyncEngine(
      repository: repo,
      attachments: attachments,
      store: cloud,
      clock: clock.call,
      includeMedia: includeMedia,
    );
    return Device._(
      db: db,
      repo: repo,
      settings: settings,
      attachments: attachments,
      engine: engine,
    );
  }

  Future<void> close() async {
    await engine.dispose();
    await repo.dispose();
    await db.close();
  }
}
