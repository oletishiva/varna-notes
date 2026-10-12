import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:varna/core/data/attachment_store.dart';
import 'package:varna/core/data/memory_database.dart';
import 'package:varna/core/data/notes_repository.dart';
import 'package:varna/core/data/settings_repository.dart';
import 'package:varna/core/models/models.dart';
import 'package:varna/features/sync/data/sync_controller.dart';
import 'package:varna/features/sync/logic/cloud_store.dart';
import 'package:varna/features/sync/logic/memory_cloud_store.dart';
import 'package:varna/features/sync/logic/sync_status.dart';

import 'support/test_support.dart';

/// A store whose sign-in is refused.
class _DeniedStore extends MemoryCloudStore {
  _DeniedStore(TestClock clock) : super(clock: clock.call) {
    available = false;
  }

  @override
  Future<bool> signIn() async => false;
}

/// A store whose sign-in can expire; counts interactive sign-in attempts.
class _ExpiringStore extends MemoryCloudStore {
  _ExpiringStore(TestClock clock) : super(clock: clock.call);

  bool allowSignIn = true;
  int signInCalls = 0;

  @override
  Future<bool> signIn() async {
    signInCalls++;
    if (!allowSignIn) {
      return false;
    }
    return super.signIn();
  }
}

/// Can hold an upload back so a test can edit "during" a sync.
class _GatedStore extends MemoryCloudStore {
  _GatedStore(TestClock clock) : super(clock: clock.call);

  Completer<void>? gate;
  final Completer<void> blocked = Completer<void>();
  int listCalls = 0;

  @override
  Future<List<RemoteFile>> listFiles() {
    listCalls++;
    return super.listFiles();
  }

  @override
  Future<RemoteFile> upload(String name, Uint8List bytes) async {
    final Completer<void>? held = gate;
    if (held != null) {
      if (!blocked.isCompleted) {
        blocked.complete();
      }
      await held.future;
    }
    return super.upload(name, bytes);
  }
}

void main() {
  late Database db;
  late TestClock clock;
  late NotesRepository repo;
  late SettingsRepository settings;
  late MemoryAttachmentStore attachments;
  late MemoryCloudStore cloud;

  SyncController makeController({
    Duration? autoSyncDelay,
    Future<bool> Function()? isOnWifi,
    CloudStoreFactory? factory,
  }) {
    return SyncController(
      repository: repo,
      attachments: attachments,
      settings: settings,
      storeFactory: factory ?? ((SyncProviderId id) => cloud),
      clock: clock.call,
      autoSyncDelay: autoSyncDelay,
      isOnWifi: isOnWifi,
    );
  }

  setUp(() async {
    db = await openInMemoryDatabase();
    clock = TestClock();
    attachments = MemoryAttachmentStore();
    repo = NotesRepository(db, clock: clock.call, attachments: attachments);
    settings = SettingsRepository(db, clock: clock.call);
    cloud = MemoryCloudStore(clock: clock.call);
  });

  tearDown(() async {
    await repo.dispose();
    await db.close();
  });

  test('without a connection, syncNow reports it and nothing happens', () async {
    final SyncController c = makeController();
    await c.init();
    expect(c.isConnected, isFalse);
    expect(c.activeProvider, isNull);
    expect(c.status, const SyncIdle());
    final SyncReport r = await c.syncNow();
    expect(r.aborted, isTrue);
    expect(r.errors.single.message, contains('No cloud'));
    await c.dispose();
  });

  test('connect pushes local data and remembers the provider', () async {
    final Notebook nb = await repo.createNotebook(title: 'Home');
    await repo.createCard(notebookId: nb.id, type: CardType.text, title: 'Milk');
    final SyncController c = makeController();
    await c.init();

    final SyncReport r = await c.connect(SyncProviderId.googleDrive);
    expect(r.uploaded, 2);
    expect(r.isOk, isTrue);
    expect(c.isConnected, isTrue);
    expect(c.activeProvider, SyncProviderId.googleDrive);
    expect(c.accountLabel, 'test@example.com');
    expect(cloud.names.length, 2);
    expect(await settings.getSyncProvider(), SyncProviderId.googleDrive);
    expect(await settings.getLastSyncAt(), clock());
    expect(c.status, isA<SyncSynced>());
    expect(await c.pendingChanges(), 0);

    // A new controller (an app restart) picks the connection up again.
    final SyncController restarted = makeController();
    await restarted.init();
    expect(restarted.activeProvider, SyncProviderId.googleDrive);
    expect(restarted.isConnected, isTrue);

    await repo.createCard(notebookId: nb.id, type: CardType.text, title: 'Eggs');
    expect(await restarted.pendingChanges(), 1);
    final SyncReport again = await restarted.syncNow();
    expect(again.uploaded, 1);

    await c.dispose();
    await restarted.dispose();
  });

  test('connect fails cleanly when sign-in is refused', () async {
    await repo.createNotebook(title: 'Home');
    final SyncController c = makeController(
      factory: (SyncProviderId id) => _DeniedStore(clock),
    );
    await c.init();
    final SyncReport r = await c.connect(SyncProviderId.icloud);
    expect(r.aborted, isTrue);
    expect(r.errors.single.message, contains('Could not sign in'));
    expect(c.isConnected, isFalse);
    expect(await settings.getSyncProvider(), isNull);
    await c.dispose();
  });

  test('connect while offline leaves no connection behind', () async {
    await repo.createNotebook(title: 'Home');
    final SyncController c = makeController(
      factory: (SyncProviderId id) => _BrokenAfterSignIn(clock),
    );
    await c.init();
    final SyncReport r = await c.connect(SyncProviderId.googleDrive);
    expect(r.aborted || r.offline, isTrue);
    expect(c.isConnected, isFalse);
    expect(c.status, const SyncIdle());
    expect(await settings.getSyncProvider(), isNull);
    await c.dispose();
  });

  test('disconnect signs out but keeps local notes', () async {
    final Notebook nb = await repo.createNotebook(title: 'Home');
    await repo.createCard(notebookId: nb.id, type: CardType.text, title: 'Milk');
    final SyncController c = makeController();
    await c.init();
    await c.connect(SyncProviderId.googleDrive);

    await c.disconnect();
    expect(c.isConnected, isFalse);
    expect(c.activeProvider, isNull);
    expect(c.status, const SyncIdle());
    expect(cloud.available, isFalse);
    expect(await settings.getSyncProvider(), isNull);
    expect((await repo.listNotebooks()).length, 1);
    expect((await repo.listCards(nb.id)).length, 1);
    // Everything counts as unsynced again for the next connection.
    expect(await c.pendingChanges(), 2);
    await c.dispose();
  });

  test('switching provider signs out of the old one', () async {
    final MemoryCloudStore drive = MemoryCloudStore(clock: clock.call);
    final MemoryCloudStore icloud = MemoryCloudStore(clock: clock.call);
    await repo.createNotebook(title: 'Home');
    final SyncController c = makeController(
      factory: (SyncProviderId id) =>
          id == SyncProviderId.googleDrive ? drive : icloud,
    );
    await c.init();
    await c.connect(SyncProviderId.googleDrive);
    expect(drive.names.length, 1);

    final SyncReport r = await c.connect(SyncProviderId.icloud);
    expect(r.uploaded, 1);
    expect(c.activeProvider, SyncProviderId.icloud);
    expect(icloud.names.length, 1);
    expect(drive.available, isFalse);
    expect(await settings.getSyncProvider(), SyncProviderId.icloud);
    await c.dispose();
  });

  test('Wi-Fi only blocks syncing when the probe says no', () async {
    await repo.createNotebook(title: 'Home');
    bool onWifi = false;
    final SyncController c = makeController(isOnWifi: () async => onWifi);
    await c.init();
    await c.connect(SyncProviderId.googleDrive);
    await settings.setWifiOnly(true);
    await repo.createNotebook(title: 'Second');

    final SyncReport blocked = await c.syncNow();
    expect(blocked.offline, isTrue);
    expect(c.status, const SyncOffline());
    expect(cloud.names.length, 1);

    onWifi = true;
    final SyncReport ok = await c.syncNow();
    expect(ok.uploaded, 1);
    await c.dispose();
  });

  test('local edits trigger an automatic sync after the delay', () async {
    final SyncController c =
        makeController(autoSyncDelay: const Duration(milliseconds: 30));
    await c.init();
    await c.connect(SyncProviderId.googleDrive);
    final Notebook nb = await repo.createNotebook(title: 'Auto');
    expect(cloud.names, isEmpty);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(cloud.contains('nb_${nb.id}.json'), isTrue);
    await c.dispose();
  });

  test('includeMedia from settings controls attachment sync', () async {
    final Notebook nb = await repo.createNotebook(title: 'Pics');
    await repo.createCard(
      notebookId: nb.id,
      type: CardType.photo,
      attachments: const <Attachment>[
        Attachment(
          id: 'p1',
          kind: AttachmentKind.image,
          fileName: 'p.jpg',
          byteLength: 1,
        ),
      ],
    );
    await attachments.save('p1', _one());
    await settings.setIncludeMedia(false);
    final SyncController c = makeController();
    await c.init();
    await c.connect(SyncProviderId.googleDrive);
    expect(cloud.contains('att_p1.bin'), isFalse);

    await settings.setIncludeMedia(true);
    final SyncReport r = await c.syncNow();
    expect(r.mediaUploaded, 1);
    expect(cloud.contains('att_p1.bin'), isTrue);
    await c.dispose();
  });

  test('conflicts are listed and resolved through the controller', () async {
    final Notebook nb = await repo.createNotebook(title: 'Home');
    final NoteCard card = await repo.createCard(
      notebookId: nb.id,
      type: CardType.text,
      title: 'Milk',
    );
    final SyncController c = makeController();
    await c.init();
    await c.connect(SyncProviderId.googleDrive);

    // Another device changes the card in the cloud ...
    final Device other = await Device.create(cloud, clock);
    clock.advance();
    await other.engine.sync();
    clock.advance();
    final NoteCard theirs = (await other.repo.getCard(card.id))!;
    await other.repo.updateCard(theirs.copyWith(title: 'Theirs'));
    await other.engine.sync();
    clock.advance();
    // ... while this one changes it too.
    await repo.updateCard(card.copyWith(title: 'Ours'));
    clock.advance();

    final SyncReport r = await c.syncNow();
    expect(r.conflicts, 1);
    expect(c.status, const SyncConflicts(1));
    final List<SyncConflict> list = await c.listConflicts();
    expect(list.single.id, card.id);
    expect((await c.getConflict(card.id))?.remoteTitle, 'Theirs');
    expect((await c.watchConflicts().first).length, 1);

    await c.resolveConflict(card.id, ConflictResolution.keepRemote);
    expect(await c.listConflicts(), isEmpty);
    expect((await repo.getCard(card.id))?.title, 'Theirs');
    await other.close();
    await c.dispose();
  });

  group('signed-out cloud', () {
    test('a manual sync signs in again once and carries on', () async {
      final _ExpiringStore store = _ExpiringStore(clock);
      final SyncController c =
          makeController(factory: (SyncProviderId id) => store);
      await c.init();
      await c.connect(SyncProviderId.googleDrive);
      store.available = false; // the Google session expired
      final Notebook nb = await repo.createNotebook(title: 'After expiry');

      final SyncReport r = await c.syncNow();
      expect(store.signInCalls, 1);
      expect(r.isOk, isTrue);
      expect(r.uploaded, 1);
      expect(store.contains('nb_${nb.id}.json'), isTrue);
      expect(c.status, isA<SyncSynced>());
      await c.dispose();
    });

    test('a refused sign-in says so instead of showing offline', () async {
      final _ExpiringStore store = _ExpiringStore(clock);
      final SyncController c =
          makeController(factory: (SyncProviderId id) => store);
      await c.init();
      await c.connect(SyncProviderId.googleDrive);
      store.available = false;
      store.allowSignIn = false;
      await repo.createNotebook(title: 'After expiry');

      final SyncReport r = await c.syncNow();
      expect(store.signInCalls, 1);
      expect(r.aborted, isTrue);
      expect(r.offline, isFalse);
      expect(c.status, const SyncError(kSignInAgainMessage));
      await c.dispose();
    });

    test('automatic syncs never prompt for a sign-in', () async {
      final _ExpiringStore store = _ExpiringStore(clock);
      final SyncController c =
          makeController(factory: (SyncProviderId id) => store);
      await c.init();
      await c.connect(SyncProviderId.googleDrive);
      store.available = false;

      final SyncReport r = await c.syncNow(manual: false);
      expect(store.signInCalls, 0);
      expect(r.aborted, isTrue);
      expect(c.status, const SyncError(kSignInAgainMessage));
      await c.dispose();
    });
  });

  group('edits during a sync', () {
    test('exactly one follow-up sync runs after the current one', () async {
      final _GatedStore gated = _GatedStore(clock);
      final SyncController c = makeController(
        autoSyncDelay: const Duration(milliseconds: 30),
        factory: (SyncProviderId id) => gated,
      );
      await c.init();
      await c.connect(SyncProviderId.googleDrive);
      final int listsBefore = gated.listCalls;
      gated.gate = Completer<void>();

      final Notebook first = await repo.createNotebook(title: 'First');
      await gated.blocked.future.timeout(const Duration(seconds: 3));
      // The user keeps typing while the first sync is still uploading.
      final Notebook second = await repo.createNotebook(title: 'Second');
      gated.gate!.complete();

      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(gated.contains('nb_${first.id}.json'), isTrue);
      expect(gated.contains('nb_${second.id}.json'), isTrue);
      // One run for the first edit, one follow-up; applying and uploading
      // never trigger more.
      expect(gated.listCalls - listsBefore, 2);
      expect(await c.pendingChanges(), 0);
      await c.dispose();
    });
  });

  group('launch and resume', () {
    test('init can run one silent sync after restoring the connection',
        () async {
      final SyncController first = makeController();
      await first.init();
      await first.connect(SyncProviderId.googleDrive);
      final Notebook later = await repo.createNotebook(title: 'Made offline');
      expect(cloud.contains('nb_${later.id}.json'), isFalse);

      final SyncController restarted = makeController();
      await restarted.init(syncAfterRestore: true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(cloud.contains('nb_${later.id}.json'), isTrue);

      // The launch sync counts for the resume throttle.
      expect(await restarted.onAppResumed(), isNull);
      await first.dispose();
      await restarted.dispose();
    });

    test('resume syncs at most once per minute', () async {
      final SyncController c = makeController();
      await c.init();
      await c.connect(SyncProviderId.googleDrive);

      expect(await c.onAppResumed(), isNotNull);
      final Notebook nb = await repo.createNotebook(title: 'Soon after');
      clock.advance(const Duration(seconds: 30));
      expect(await c.onAppResumed(), isNull);
      expect(cloud.contains('nb_${nb.id}.json'), isFalse);

      clock.advance(const Duration(seconds: 31));
      final SyncReport? r = await c.onAppResumed();
      expect(r?.uploaded, 1);
      expect(cloud.contains('nb_${nb.id}.json'), isTrue);
      await c.dispose();
    });

    test('resume does nothing without a connection', () async {
      final SyncController c = makeController();
      await c.init();
      expect(await c.onAppResumed(), isNull);
      await c.dispose();
    });
  });
}

/// Signs in fine but cannot list files.
class _BrokenAfterSignIn extends MemoryCloudStore {
  _BrokenAfterSignIn(TestClock clock) : super(clock: clock.call);

  @override
  Future<List<RemoteFile>> listFiles() async {
    throw CloudOfflineException();
  }
}

Uint8List _one() => Uint8List.fromList(<int>[1]);
