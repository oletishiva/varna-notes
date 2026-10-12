import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';
import 'package:varna/app_config.dart';
import 'package:varna/core/data/memory_database.dart';
import 'package:varna/core/data/notes_repository.dart';
import 'package:varna/core/data/settings_repository.dart';
import 'package:varna/core/models/models.dart';
import 'package:varna/core/services/entitlements.dart';
import 'package:varna/core/services/usage_limits.dart';

import 'support/test_support.dart';

void main() {
  late Database db;
  late TestClock clock;
  late SettingsRepository settings;

  setUp(() async {
    db = await openInMemoryDatabase();
    // Mid-October 2026 (local-style clock values; only y/m/d are used).
    clock = TestClock(DateTime(2026, 10, 15, 12));
    settings = SettingsRepository(db, clock: clock.call);
  });

  tearDown(() async {
    await db.close();
  });

  group('SettingsRepository', () {
    test('defaults', () async {
      final AppSettings s = await settings.load();
      expect(s.syncProvider, isNull);
      expect(s.wifiOnly, isFalse);
      expect(s.includeMedia, isTrue);
      expect(s.onboardingDone, isFalse);
      expect(s.plusDebug, isFalse);
      expect(s.lastSyncAt, isNull);
      expect(s.usage, const UsageSnapshot(monthKey: '2026-10', scans: 0, transcripts: 0));
    });

    test('values persist and can be cleared', () async {
      await settings.setSyncProvider(SyncProviderId.icloud);
      await settings.setWifiOnly(true);
      await settings.setIncludeMedia(false);
      await settings.setOnboardingDone(true);
      await settings.setPlusDebug(true);
      await settings.setLastSyncAt(DateTime.utc(2026, 10, 15, 6, 30));
      final AppSettings s = await settings.load();
      expect(s.syncProvider, SyncProviderId.icloud);
      expect(s.wifiOnly, isTrue);
      expect(s.includeMedia, isFalse);
      expect(s.onboardingDone, isTrue);
      expect(s.plusDebug, isTrue);
      expect(s.lastSyncAt, DateTime.utc(2026, 10, 15, 6, 30));
      expect(await settings.getSyncProvider(), SyncProviderId.icloud);

      await settings.setSyncProvider(null);
      await settings.setLastSyncAt(null);
      expect(await settings.getSyncProvider(), isNull);
      expect(await settings.getLastSyncAt(), isNull);
    });

    test('watch emits the current settings and then changes', () async {
      final List<AppSettings> seen = <AppSettings>[];
      final sub = settings.watch().listen(seen.add);
      await pumpEventQueue();
      expect(seen.last.onboardingDone, isFalse);
      await settings.setOnboardingDone(true);
      await pumpEventQueue();
      expect(seen.last.onboardingDone, isTrue);
      await sub.cancel();
    });
  });

  group('usage counters', () {
    test('count within a month', () async {
      await settings.incrementScans();
      await settings.incrementScans();
      final UsageSnapshot after = await settings.incrementTranscripts();
      expect(after.scans, 2);
      expect(after.transcripts, 1);
      expect(after.monthKey, '2026-10');
      expect((await settings.getUsage()).scans, 2);
      expect((await settings.incrementScans(3)).scans, 5);
    });

    test('reset when the month changes', () async {
      await settings.incrementScans(4);
      await settings.incrementTranscripts(2);
      expect((await settings.getUsage()).scans, 4);

      // 31 Oct 23:59 is still October ...
      clock.set(DateTime(2026, 10, 31, 23, 59, 59));
      expect(settings.currentMonthKey(), '2026-10');
      expect((await settings.getUsage()).scans, 4);

      // ... 1 Nov 00:00 is November: counters read as zero straight away.
      clock.set(DateTime(2026, 11, 1));
      expect(settings.currentMonthKey(), '2026-11');
      final UsageSnapshot fresh = await settings.getUsage();
      expect(fresh.monthKey, '2026-11');
      expect(fresh.scans, 0);
      expect(fresh.transcripts, 0);

      // The first increment of the new month starts from zero, not from 4.
      final UsageSnapshot first = await settings.incrementScans();
      expect(first.scans, 1);
      expect(first.transcripts, 0);
      expect((await settings.getUsage()).scans, 1);
    });

    test('reset across a year boundary', () async {
      clock.set(DateTime(2026, 12, 20));
      await settings.incrementScans(9);
      clock.set(DateTime(2027, 1, 2));
      expect(settings.currentMonthKey(), '2027-01');
      expect((await settings.getUsage()).scans, 0);
      expect((await settings.incrementScans()).scans, 1);
    });

    test('resetUsage zeroes both counters', () async {
      await settings.incrementScans(3);
      await settings.incrementTranscripts(2);
      await settings.resetUsage();
      final UsageSnapshot u = await settings.getUsage();
      expect(u.scans, 0);
      expect(u.transcripts, 0);
    });
  });

  group('UsageLimits (free plan)', () {
    late NotesRepository notes;
    late UsageLimits limits;

    setUp(() {
      notes = NotesRepository(db, clock: clock.call);
      limits = UsageLimits(
        notes: notes,
        settings: settings,
        entitlements: FixedEntitlements(plus: false),
      );
    });

    tearDown(() async {
      await notes.dispose();
    });

    test('notebooks: five are free, the sixth is refused', () async {
      for (int i = 0; i < AppConfig.freeNotebookLimit - 1; i++) {
        await notes.createNotebook(title: 'Notebook $i');
      }
      LimitCheck check = await limits.canCreateNotebook();
      expect(check.allowed, isTrue);
      expect(check.used, 4);
      expect(check.limit, 5);
      expect(check.remaining, 1);
      expect(check.reason, isNull);

      final Notebook fifth = await notes.createNotebook(title: 'Fifth');
      check = await limits.canCreateNotebook();
      expect(check.allowed, isFalse);
      expect(check.used, 5);
      expect(check.remaining, 0);
      expect(check.reason, LimitReason.notebookLimit);
      expect(check.message, contains('5 notebooks'));
      expect(check.message, contains('Plus'));

      // Deleting one frees a slot.
      await notes.deleteNotebook(fifth.id);
      expect((await limits.canCreateNotebook()).allowed, isTrue);
    });

    test('scans: ten per month, then blocked until next month', () async {
      for (int i = 0; i < 9; i++) {
        await limits.recordScan();
      }
      expect((await limits.canScan()).allowed, isTrue);
      expect((await limits.canScan()).remaining, 1);
      await limits.recordScan();
      final LimitCheck blocked = await limits.canScan();
      expect(blocked.allowed, isFalse);
      expect(blocked.reason, LimitReason.scanLimit);
      expect(blocked.used, 10);
      expect(blocked.message, contains('10 free scans'));

      clock.set(DateTime(2026, 11, 3));
      expect((await limits.canScan()).allowed, isTrue);
      expect((await limits.canScan()).used, 0);
    });

    test('transcripts: five per month', () async {
      for (int i = 0; i < 4; i++) {
        await limits.recordTranscript();
      }
      expect((await limits.canTranscribe()).allowed, isTrue);
      await limits.recordTranscript();
      final LimitCheck blocked = await limits.canTranscribe();
      expect(blocked.allowed, isFalse);
      expect(blocked.reason, LimitReason.transcriptLimit);
      expect(blocked.limit, 5);
    });

    test('Plus is unlimited', () async {
      final UsageLimits plus = UsageLimits(
        notes: notes,
        settings: settings,
        entitlements: FixedEntitlements(plus: true),
      );
      for (int i = 0; i < 7; i++) {
        await notes.createNotebook(title: 'N$i');
      }
      await settings.incrementScans(50);
      await settings.incrementTranscripts(50);
      final LimitCheck nb = await plus.canCreateNotebook();
      expect(nb.allowed, isTrue);
      expect(nb.limit, isNull);
      expect(nb.remaining, isNull);
      expect((await plus.canScan()).allowed, isTrue);
      expect((await plus.canTranscribe()).allowed, isTrue);
    });
  });

  group('Entitlements', () {
    test('the debug toggle is stored in settings', () async {
      final DebugToggleEntitlements e = DebugToggleEntitlements(settings);
      expect(e.supportsDebugToggle, isTrue);
      expect(await e.isPlus(), isFalse);
      await e.setDebugPlus(true);
      expect(await e.isPlus(), isTrue);
      expect(await settings.getPlusDebug(), isTrue);

      final List<bool> seen = <bool>[];
      final sub = e.watchIsPlus().listen(seen.add);
      await pumpEventQueue();
      expect(seen.last, isTrue);
      await e.setDebugPlus(false);
      await pumpEventQueue();
      expect(seen.last, isFalse);
      await sub.cancel();
    });

    test('FixedEntitlements cannot be toggled', () async {
      final FixedEntitlements e = FixedEntitlements(plus: true);
      expect(await e.isPlus(), isTrue);
      expect(await e.watchIsPlus().first, isTrue);
      expect(e.supportsDebugToggle, isFalse);
      expect(() => e.setDebugPlus(false), throwsUnsupportedError);
    });
  });
}
